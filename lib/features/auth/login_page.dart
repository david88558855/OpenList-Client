import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/models/server_profile.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _secret = TextEditingController();
  final _otp = TextEditingController();
  final _urlFocus = FocusNode();

  AuthMode _mode = AuthMode.password;
  bool _obscure = true;
  bool _keepLogin = true;
  bool _showOtp = false;
  bool _busy = false;
  String? _error;
  String? _urlError;
  String? _probeLabel;
  int? _probeLatency;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _url.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _url.removeListener(_onUrlChanged);
    _url.dispose();
    _user.dispose();
    _secret.dispose();
    _otp.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    _debounce?.cancel();
    if (_probeLabel != null || _urlError != null) {
      setState(() {
        _probeLabel = null;
        _urlError = null;
      });
    }
    if (_url.text.trim().length < 6) return;
    _debounce = Timer(const Duration(milliseconds: 700), _probe);
  }

  Future<void> _probe() async {
    final result = await ref.read(sessionProvider.notifier).probe(_url.text);
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _probeLabel = result.site?.title ?? '已连接';
        _probeLatency = result.latencyMs;
        _urlError = null;
      } else {
        _probeLabel = null;
        _urlError = result.error;
      }
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref.read(sessionProvider.notifier).connect(
          mode: _mode,
          baseUrl: _url.text,
          username: _user.text,
          secret: _secret.text,
          otp: _otp.text,
          persistToken: _keepLogin,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _urlError = error == null ? null : (error.contains('地址') ? error : _urlError);
    });
    if (error == null) {
      await ref.read(filesProvider.notifier).attach();
      if (mounted) context.go('/files');
    }
  }

  Future<void> _useRecent(ServerProfile profile) async {
    _url.text = profile.baseUrl;
    _user.text = profile.username;
    if (profile.id == ref.read(serverListProvider).activeId && ref.read(sessionProvider).signedIn) {
      if (mounted) context.go('/files');
      return;
    }
    setState(() => _busy = true);
    await ref.read(sessionProvider.notifier).switchTo(profile.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ref.read(sessionProvider).signedIn) {
      await ref.read(filesProvider.notifier).attach();
      if (mounted) context.go('/files');
    } else {
      _urlFocus.requestFocus();
      setState(() => _error = '请输入密码以重新连接「${profile.name}」');
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final body = narrow ? _buildMobile(context) : _buildDesktop(context);
    return AppFrame(showNav: false, child: body);
  }

  Widget _buildDesktop(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 56,
          child: _LoginArt(
            servers: ref.watch(serverListProvider).servers,
          ),
        ),
        Expanded(flex: 44, child: _buildForm(context, compact: false)),
      ],
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF07131F), Color(0xFF07131F)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _LoginGlow()),
          const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GridPainter(spacing: 44)))),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const OlMark(size: 30, radius: 9, iconSize: 14),
                      const SizedBox(width: 9),
                      const Text('OpenList', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFEAF5FC))),
                    ],
                  ),
                  const SizedBox(height: 44),
                  const Text('SELF-HOSTED CLOUD', style: TextStyle(fontSize: 8.5, letterSpacing: 2.4, fontWeight: FontWeight.w800, color: Color(0xFF7DD3FC))),
                  const SizedBox(height: 11),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 39, height: 1.03, letterSpacing: -1.7, fontWeight: FontWeight.w800, color: Colors.white),
                      children: [
                        TextSpan(text: '你的云盘，\n'),
                        TextSpan(text: '随身携带', style: TextStyle(color: Color(0xFF5EEAD4))),
                        TextSpan(text: '。'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '连接自建 OpenList，聚合阿里云盘、夸克、OneDrive 与 NAS。文件直连，不经过第三方。',
                    style: TextStyle(fontSize: 11.5, height: 1.65, color: Color(0xFF8FA8BD)),
                  ),
                  const SizedBox(height: 26),
                  _buildForm(context, compact: true),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context, {required bool compact}) {
    final p = context.ol;
    final servers = ref.watch(serverListProvider).servers;
    final recent = servers.take(4).toList();

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[
          const Text('WELCOME BACK', style: TextStyle(fontSize: 8.5, letterSpacing: 2.2, fontWeight: FontWeight.w800, color: Color(0xFF0EA5E9))),
          const SizedBox(height: 10),
          Text('连接到你的服务器', style: TextStyle(fontSize: 23, height: 1.2, letterSpacing: -0.7, fontWeight: FontWeight.w800, color: p.ink)),
          const SizedBox(height: 8),
          Text('输入 OpenList 地址，客户端会自动探测版本与站点名称。', style: TextStyle(fontSize: 11.5, height: 1.7, color: p.ink3)),
          const SizedBox(height: 20),
        ],
        _label('服务器地址', compact: compact, trailing: _probeLabel == null ? '含协议与端口' : null),
        _input(
          dark: compact,
          controller: _url,
          icon: 'globe',
          hint: 'https://pan.mydomain.com',
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _probe(),
          trailing: _probeLabel == null
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFE7FBF5), borderRadius: BorderRadius.circular(5)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const OlDot(size: 4, color: OlTokens.teal600),
                      const SizedBox(width: 4),
                      Text(
                        _probeLatency == null ? _probeLabel! : '$_probeLabel · ${_probeLatency}ms',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF0B7A63)),
                      ),
                    ],
                  ),
                ),
        ),
        if (_urlError != null) _inlineError(_urlError!),
        const SizedBox(height: 12),
        if (_mode == AuthMode.password) ...[
          _label('用户名', compact: compact),
          _input(dark: compact, controller: _user, icon: 'user', hint: 'admin', onSubmitted: (_) => _submit()),
          const SizedBox(height: 12),
          _label('密码', compact: compact, trailing: _showOtp ? null : '支持两步验证'),
          _input(
            dark: compact,
            controller: _secret,
            icon: 'lock',
            hint: '••••••••',
            obscure: _obscure,
            onSubmitted: (_) => _submit(),
            trailing: _eye(),
          ),
          if (_showOtp) ...[
            const SizedBox(height: 12),
            _label('两步验证码', compact: compact, trailing: '可留空'),
            _input(
              dark: compact,
              controller: _otp,
              icon: 'shield',
              hint: '6 位动态码',
              keyboardType: TextInputType.number,
            ),
          ],
        ] else ...[
          _label('API Token', compact: compact, trailing: '凭据仅存本机'),
          _input(
            dark: compact,
            controller: _secret,
            icon: 'key',
            hint: '粘贴 OpenList API Token',
            obscure: _obscure,
            onSubmitted: (_) => _submit(),
            trailing: _eye(),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            OlSwitch(value: _keepLogin, onChanged: (v) => setState(() => _keepLogin = v), small: true),
            const SizedBox(width: 7),
            Text('保持登录', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _showOtp = !_showOtp),
              child: Text(
                _showOtp ? '隐藏两步验证' : '两步验证',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF0A93C4)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SubmitButton(busy: _busy, onTap: _submit),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _inlineError(_error!),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Divider(color: p.line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('OR', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.ink4)),
            ),
            Expanded(child: Divider(color: p.line)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _AltButton(
                icon: 'key',
                dark: compact,
                label: _mode == AuthMode.token ? '使用密码' : '使用 API Token',
                onTap: () => setState(() {
                  _mode = _mode == AuthMode.token ? AuthMode.password : AuthMode.token;
                  _error = null;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AltButton(
                icon: 'qr',
                dark: compact,
                label: '扫码授权',
                onTap: () => olToast(context, '扫码授权需服务端开启 OAuth，请在网页端完成授权后使用 Token 登录'),
              ),
            ),
          ],
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: EdgeInsets.only(top: 12, left: 2, right: 2),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: compact ? const Color(0x1AFFFFFF) : p.line2))),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      '我的服务器',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: compact ? const Color(0xFF5E7488) : p.ink4,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.go('/servers'),
                      child: Text(
                        '管理',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: compact ? const Color(0xFF7DD3FC) : const Color(0xFF0A93C4),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final server in recent)
                  _RecentServerRow(
                    profile: server,
                    dark: compact,
                    onTap: () => _useRecent(server),
                  ),
              ],
            ),
          ),
        ],
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                OlIcon('info', size: 9, color: p.ink4),
                const SizedBox(width: 4),
                Text(
                  '服务器数量不限，配置与缓存按实例隔离',
                  style: TextStyle(fontSize: 8, color: p.ink4),
                ),
              ],
            ),
          ),
      ],
    );

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: form,
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 348),
          child: form,
        ),
      ),
    );
  }

  Widget _eye() {
    final p = context.ol;
    return GestureDetector(
      onTap: () => setState(() => _obscure = !_obscure),
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: OlIcon(_obscure ? 'eye' : 'eye-off', size: 15, color: p.ink3),
      ),
    );
  }

  Widget _input({
    required bool dark,
    required TextEditingController controller,
    required String icon,
    String? hint,
    bool obscure = false,
    Widget? trailing,
    TextInputType? keyboardType,
    ValueChanged<String>? onSubmitted,
  }) {
    if (dark) {
      return OlDarkField(
        controller: controller,
        icon: icon,
        hint: hint ?? '',
        obscure: obscure,
        trailing: trailing,
        keyboardType: keyboardType,
        onSubmitted: onSubmitted,
      );
    }
    return OlField(
      controller: controller,
      icon: icon,
      hint: hint,
      obscure: obscure,
      trailing: trailing,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
    );
  }

  Widget _label(String text, {required bool compact, String? trailing}) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 5),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: compact ? const Color(0xFF7E97AC) : p.ink3,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing,
              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: compact ? const Color(0xFF5E7488) : p.ink4),
            ),
        ],
      ),
    );
  }

  Widget _inlineError(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: OlIcon('alert', size: 11, color: Color(0xFFE8476F)),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 10, height: 1.5, fontWeight: FontWeight.w600, color: Color(0xFFE8476F)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _SubmitButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            gradient: OlTokens.gradientPrimary,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Color(0x5538BDF8), blurRadius: 24, offset: Offset(0, 12))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
              else
                const OlIcon('arrow-up', size: 14, color: Colors.white, strokeWidth: 2),
              const SizedBox(width: 7),
              Text(
                busy ? '正在连接…' : '连接并登录',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AltButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool dark;
  const _AltButton({required this.icon, required this.label, required this.onTap, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: dark ? const Color(0x0DFFFFFF) : Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: dark ? const Color(0x1AFFFFFF) : p.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OlIcon(icon, size: 13, color: dark ? const Color(0xFF8FA8BD) : p.ink2),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: dark ? const Color(0xFFB9CAD8) : p.ink2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentServerRow extends StatelessWidget {
  final ServerProfile profile;
  final bool dark;
  final VoidCallback onTap;

  const _RecentServerRow({required this.profile, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final dotColor = switch (profile.health) {
      ServerHealth.ok => OlTokens.ok,
      ServerHealth.timeout => OlTokens.warn,
      ServerHealth.unauthorized => OlTokens.danger,
      ServerHealth.unknown => p.ink4,
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: dark ? const Color(0x0AFFFFFF) : p.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: dark ? const Color(0x12FFFFFF) : p.line2),
          ),
          child: Row(
            children: [
              OlIcon('server', size: 14, color: dark ? const Color(0xFF7DD3FC) : const Color(0xFF0A93C4)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  profile.displayHost,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: dark ? const Color(0xFFC7D8E6) : p.ink2,
                  ),
                ),
              ),
              Text(
                relativeTime(profile.lastUsed),
                style: TextStyle(fontSize: 8.5, color: dark ? const Color(0xFF6E879C) : p.ink4),
              ),
              const SizedBox(width: 6),
              OlDot(size: 5, color: dotColor),
            ],
          ),
        ),
      ),
    );
  }
}

/// Left art panel (W1): grid, glow, brand, copy, features, mounted card.
class _LoginArt extends StatelessWidget {
  final List<ServerProfile> servers;
  const _LoginArt({required this.servers});

  @override
  Widget build(BuildContext context) {
    final mounts = servers.take(3).toList();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.6, -1),
          end: Alignment(0.9, 1),
          colors: [Color(0xFF08141F), Color(0xFF0B2433), Color(0xFF0A2C33)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _LoginGlow()),
          const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GridPainter(spacing: 46)))),
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(40, 30, 40, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const OlMark(size: 30, radius: 9, iconSize: 14),
                      const SizedBox(width: 9),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('OpenList Client', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.1)),
                          SizedBox(height: 1),
                          Text('WINDOWS EDITION', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Color(0xFF7E97AC))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 52),
                  const Text('YOUR CLOUDS, ONE WINDOW', style: TextStyle(fontSize: 8.5, letterSpacing: 2.6, fontWeight: FontWeight.w800, color: Color(0xFF7DD3FC))),
                  const SizedBox(height: 14),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 41, height: 1.06, letterSpacing: -1.9, fontWeight: FontWeight.w800, color: Colors.white),
                      children: [
                        TextSpan(text: '所有云盘，\n收进'),
                        TextSpan(text: '一个窗口', style: TextStyle(color: Color(0xFF5EEAD4))),
                        TextSpan(text: '。'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(
                    width: 330,
                    child: Text(
                      '直连你自建的 OpenList 服务。文件不中转、不落第三方，速度只取决于你的带宽。',
                      style: TextStyle(fontSize: 11.5, height: 1.8, color: Color(0xFF8FA8BD)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _MountedCard(servers: mounts),
                  const SizedBox(height: 30),
                  const _FeatureRow(icon: 'zap', title: '原生多线程传输', subtitle: '断点续传、并发可调、托盘后台不中断'),
                  const SizedBox(height: 11),
                  const _FeatureRow(icon: 'play', title: '边下边播', subtitle: '支持 4K HDR 与字幕轨道，Range 直读不落地'),
                  const SizedBox(height: 11),
                  const _FeatureRow(icon: 'shield', title: '凭据本地保存', subtitle: 'Token 写入 Windows 凭据管理器，可随时吊销'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  const _FeatureRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0x1A7DD3FC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x297DD3FC)),
          ),
          child: Center(child: OlIcon(icon, size: 13, color: const Color(0xFF7DD3FC))),
        ),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFD6E4EF))),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 9, height: 1.5, color: Color(0xFF7E97AC))),
          ],
        ),
      ],
    );
  }
}

/// The glass “mounted sources” card from the art panel.
class _MountedCard extends StatelessWidget {
  final List<ServerProfile> servers;
  const _MountedCard({required this.servers});

  @override
  Widget build(BuildContext context) {
    final labels = servers.isEmpty
        ? const ['阿里云盘', 'OneDrive', '本地 NAS']
        : servers.map((e) => e.siteTitle ?? e.name).take(3).toList();
    final dots = const [Color(0xFF38BDF8), Color(0xFF7DD3FC), Color(0xFFC4B5FD)];
    final caps = const ['2.4 TB', '1.0 TB', '8.0 TB'];
    return Container(
      width: 268,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 16))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text('MOUNTED', style: TextStyle(fontSize: 8, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: Color(0xFF6E879C))),
              Spacer(),
              Text('5 SOURCES', style: TextStyle(fontSize: 8, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: Color(0xFF6E879C))),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: dots[i], borderRadius: BorderRadius.circular(2.5))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFD6E4EF)),
                    ),
                  ),
                  Text(caps[i], style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: Color(0xFF8FA8BD))),
                  const SizedBox(width: 6),
                  const OlDot(size: 4, color: Color(0xFF22C55E)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          const Text('统一命名空间 · 一棵目录树', style: TextStyle(fontSize: 8.5, color: Color(0xFF7E97AC))),
        ],
      ),
    );
  }
}

class _LoginGlow extends StatelessWidget {
  const _LoginGlow();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.7, -0.85),
          radius: 1.1,
          colors: [Color(0x4D38BDF8), Color(0x0007131F)],
          stops: [0, 0.62],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double spacing;
  const _GridPainter({this.spacing = 46});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..strokeWidth = 1
      ..shader = const RadialGradient(
        center: Alignment(0.4, -0.35),
        radius: 0.9,
        colors: [Color(0x22FFFFFF), Color(0x00FFFFFF)],
        stops: [0, 0.72],
      ).createShader(rect);
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.spacing != spacing;
}
