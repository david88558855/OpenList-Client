import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/openlist_api.dart';
import '../../core/models/api_types.dart';
import '../../core/models/server_profile.dart';
import '../../core/storage/secure_store.dart';

class SessionState {
  final ServerProfile? profile;
  final UserInfo? user;
  final SiteInfo? site;
  final OpenListApi? api;
  final bool connecting;
  final bool signedIn;
  final String? error;
  final int? latencyMs;

  const SessionState({
    this.profile,
    this.user,
    this.site,
    this.api,
    this.connecting = false,
    this.signedIn = false,
    this.error,
    this.latencyMs,
  });

  SessionState copyWith({
    ServerProfile? profile,
    UserInfo? user,
    SiteInfo? site,
    OpenListApi? api,
    bool? connecting,
    bool? signedIn,
    String? error,
    int? latencyMs,
  }) =>
      SessionState(
        profile: profile ?? this.profile,
        user: user ?? this.user,
        site: site ?? this.site,
        api: api ?? this.api,
        connecting: connecting ?? this.connecting,
        signedIn: signedIn ?? this.signedIn,
        error: error,
        latencyMs: latencyMs ?? this.latencyMs,
      );
}

class ProbeResult {
  final bool ok;
  final SiteInfo? site;
  final int latencyMs;
  final String? error;

  const ProbeResult({required this.ok, this.site, this.latencyMs = 0, this.error});
}

class SessionNotifier extends StateNotifier<SessionState> {
  final Ref ref;
  final SecureStore _secure;

  SessionNotifier(this.ref)
      : _secure = ref.read(secureStoreProvider),
        super(const SessionState());

  Future<ProbeResult> probe(String rawUrl) async {
    final urlError = validateBaseUrl(rawUrl);
    if (urlError != null) return ProbeResult(ok: false, error: urlError);
    final api = OpenListApi(baseUrl: normalizeBaseUrl(rawUrl));
    final watch = Stopwatch()..start();
    try {
      final site = await api.publicSettings();
      watch.stop();
      return ProbeResult(ok: true, site: site, latencyMs: watch.elapsedMilliseconds);
    } on ApiException catch (e) {
      watch.stop();
      return ProbeResult(ok: false, error: e.friendly, latencyMs: watch.elapsedMilliseconds);
    }
  }

  /// Restores the last active server from the keychain on cold start.
  Future<void> boot() async {
    final list = ref.read(serverListProvider);
    final profile = list.active;
    if (profile == null) {
      state = const SessionState();
      return;
    }
    final token = await _secure.read(profile.tokenKey);
    if (token == null || token.isEmpty) {
      state = SessionState(profile: profile);
      return;
    }
    final api = OpenListApi(baseUrl: profile.baseUrl, token: token);
    state = SessionState(profile: profile, api: api, connecting: true);
    final watch = Stopwatch()..start();
    try {
      final user = await api.me();
      final site = await api.publicSettings();
      watch.stop();
      state = SessionState(
        profile: profile,
        user: user,
        site: site,
        api: api,
        signedIn: true,
        latencyMs: watch.elapsedMilliseconds,
      );
      await ref.read(serverListProvider.notifier).touch(
            profile.id,
            latencyMs: watch.elapsedMilliseconds,
            health: ServerHealth.ok,
            siteTitle: site.title,
            version: site.version ?? site.apiVersion,
          );
      ref.read(appSettingsProvider.notifier).rememberLatency(watch.elapsedMilliseconds);
    } on ApiException catch (e) {
      watch.stop();
      if (e.needsReauth) {
        await _secure.delete(profile.tokenKey);
        state = SessionState(profile: profile, error: '登录已失效，请重新连接');
      } else {
        state = SessionState(profile: profile, api: api, error: e.friendly, connecting: false);
      }
    }
  }

  /// Password / token login. Returns an inline error message, or null on success.
  Future<String?> connect({
    required AuthMode mode,
    required String baseUrl,
    required String username,
    required String secret,
    String otp = '',
    String displayName = '',
    String? existingId,
    bool persistToken = true,
  }) async {
    final urlError = validateBaseUrl(baseUrl);
    if (urlError != null) return urlError;
    final base = normalizeBaseUrl(baseUrl);
    if (mode == AuthMode.password && username.trim().isEmpty) return '请填写用户名';
    if (secret.isEmpty) return mode == AuthMode.token ? '请填写 API Token' : '请填写密码';

    state = state.copyWith(connecting: true, error: null);
    final api = OpenListApi(baseUrl: base);
    try {
      final site = await api.publicSettings();
      String token;
      if (mode == AuthMode.token) {
        token = secret.trim();
        api.token = token;
      } else {
        token = await api.login(username: username.trim(), password: secret, otpCode: otp);
      }
      final user = await api.me();
      final profile = ServerProfile(
        id: existingId ?? newServerId(),
        name: displayName.trim().isEmpty ? site.title : displayName.trim(),
        baseUrl: base,
        username: username.trim().isEmpty ? user.username : username.trim(),
        mode: mode,
        siteTitle: site.title,
        version: site.version ?? site.apiVersion,
        lastUsed: DateTime.now(),
        health: ServerHealth.ok,
        latencyMs: state.latencyMs,
      );
      if (persistToken) {
        await _secure.write(profile.tokenKey, token);
      } else {
        await _secure.delete(profile.tokenKey);
      }
      final servers = ref.read(serverListProvider.notifier);
      await servers.upsert(profile);
      await servers.setActive(profile.id);
      state = SessionState(
        profile: profile,
        user: user,
        site: site,
        api: api,
        signedIn: true,
        latencyMs: state.latencyMs,
      );
      return null;
    } on ApiException catch (e) {
      state = state.copyWith(connecting: false, error: e.friendly);
      return e.friendly;
    } catch (e) {
      const message = '连接失败，请检查地址与网络';
      state = state.copyWith(connecting: false, error: message);
      return message;
    }
  }

  Future<void> switchTo(String serverId) async {
    if (state.profile?.id == serverId) return;
    await ref.read(serverListProvider.notifier).setActive(serverId);
    state = const SessionState();
    await boot();
  }

  Future<void> refreshUser() async {
    final api = state.api;
    final profile = state.profile;
    if (api == null || profile == null) return;
    try {
      final user = await api.me();
      state = SessionState(
        profile: profile,
        user: user,
        site: state.site,
        api: api,
        signedIn: true,
        latencyMs: state.latencyMs,
      );
    } on ApiException catch (_) {
      // keep the current session; a stale /api/me must not log the user out
    }
  }

  /// Called by any request that came back 401.
  Future<void> expire() async {
    final profile = state.profile;
    if (profile != null) await _secure.delete(profile.tokenKey);
    state = SessionState(profile: profile, error: '登录已失效，请重新连接');
  }

  Future<void> signOut() async {
    final profile = state.profile;
    if (profile != null) await _secure.delete(profile.tokenKey);
    state = SessionState(profile: profile);
  }

  Future<void> retry() async {
    state = const SessionState();
    await boot();
  }
}
