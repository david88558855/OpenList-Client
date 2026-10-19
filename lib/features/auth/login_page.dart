import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app.dart';
import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/models/server_profile.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_icon.dart';
import 'session.dart';

/// W1（Windows 连接页）/ A1（Android 沉浸式登录）。
///
/// 验收要点：
///   - 地址可达 / TLS / 版本探测，失败一律内联提示，不弹窗；
///   - 支持密码与 API Token 两种登录；
///   - HTTP 仅内网放行（校验在 validateBaseUrl 内）；
///   - 首次运行（0 个已保存）也必须显示「服务器管理」入口。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _url = TextEditingController();
  final _user = TextEditingController(text: 'admin');
  final _secret = TextEditingController();
  final _name = TextEditingController();

  AuthMode _mode = AuthMode.password;
  bool _keepSignedIn = true;
  bool _obscure = true;
  bool _busy = false;

  String? _inlineError;
  String? _probeOk;
  int? _probeMs;

  @override
  void initState() {
    super.initState();
    final active = ref.read(serverListProvider).active;
    if (active != null) {
      _url.text = active.baseUrl;
      _user.text = active.username;
      _name.text = active.name;
      _mode = active.mode;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _secret.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final urlError = validateBaseUrl(_url.text);
    if (urlError != null) {
      setState(() => _inlineError = urlError);
      return;
    }
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    final error = await ref.read(sessionProvider.notifier).connect(
          mode: _mode,
          baseUrl: _url.text,
          username: _user.text,
          secret: _secret.text.trim(),
          displayName: _name.text.trim(),
          persistToken: _keepSignedIn,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _inlineError = error;
    });
    if (error == null) context.go('/files');
  }

  Future<void> _probe() async {
    final raw = _url.text.trim();
    if (raw.isEmpty) return;
    final result = await ref.read(sessionProvider.notifier).probe(raw);
    if (!mounted) return;
    setState(() {
      _inlineError = result.ok ? null : result.error;
      _probeOk = result.ok ? (result.site?.title ?? 'OpenList') : null;
      _probeMs = result.ok ? result.latencyMs : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) return _buildMobile(context);
    return _buildDesktop(context);
  }

  // ---------- W1 · Windows ----------
  Widget _buildDesktop(BuildContext context) {
    final p = context.ol;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const OlTitleBar(),
          Expanded(
            child: Row(
              children: [
                const Expanded(flex: 5, child: _BrandHero()),
                Expanded(
                  flex: 4,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(OlGap.lg),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 372),
                        child: _FormCard(
                          mode: _mode,
                          url: _url,
                          user: _user,
                          secret: _secret,
                          name: _name,
                          obscure: _obscure,
                          busy: _busy,
                          keepSignedIn: _keepSignedIn,
                          inlineError: _inlineError,
                          probeOk: _probeOk,
                          probeMs: _probeMs,
                          onMode: (m) => setState(() => _mode = m),
                          onObscure: () => setState(() => _obscure = !_obscure),
                          onKeep: (v) => setState(() => _keepSignedIn = v),
                          onProbe: _probe,
                          onSubmit: _submit,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- A1 · Android ----------
  Widget _buildMobile(BuildContext context) {
    return OlDarkScaffold(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 0, OlGap.pageMobile, OlGap.lg),
          children: [
            SizedBox(height: MediaQuery.paddingOf(context).top + 40),
            const OlMark(size: 52, radius: 15, iconSize: 26),
            const SizedBox(height: OlGap.md),
            const Text(
              'OpenList',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: Color(0xFFE8F2FA)),
            ),
            const SizedBox(height: 6),
            const Text(
              'SELF-HOSTED CLOUD',
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 2.4, color: Color(0xFF7DD3FC)),
            ),
            const SizedBox(height: OlGap.md),
            const _ImmersiveHeadline(),
            const SizedBox(height: OlGap.xs),
            const Text(
              '连接自建 OpenList，聚合阿里云盘、夸克、OneDrive 与 NAS。文件直连，不经过第三方。',
              style: TextStyle(fontSize: 11.5, height: 1.7, color: Color(0xFF8FA8BD)),
            ),
            const SizedBox(height: OlGap.lg),
            OlDarkField(
              controller: _url,
              icon: 'globe',
              hint: 'https://pan.mydomain.com',
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _probe(),
            ),
            const SizedBox(height: OlGap.sm),
            OlDarkField(
              controller: _user,
              icon: 'user',
              hint: _mode == AuthMode.token ? '账号（可选）' : 'admin',
            ),
            const SizedBox(height: OlGap.sm),
            OlDarkField(
              controller: _secret,
              icon: _mode == AuthMode.token ? 'key' : 'lock',
              hint: _mode == AuthMode.token ? 'API Token' : '••••••••',
              obscure: _obscure,
              onSubmitted: (_) => _submit(),
              trailing: GestureDetector(
                onTap: () => setState(() => _obscure = !_obscure),
                child: OlIcon(_obscure ? 'eye-off' : 'eye', size: 16, color: const Color(0xFF6E879C)),
              ),
            ),
            if (_inlineError != null) ...[const SizedBox(height: OlGap.xs), _InlineError(_inlineError!)],
            if (_probeOk != null) ...[const SizedBox(height: OlGap.xs), _ProbeOk(_probeOk!, _probeMs)],
            const SizedBox(height: OlGap.lg),
            OlPrimaryButton(
              label: '连接并登录',
              icon: 'zap',
              height: 46,
              fontSize: 13,
              expand: true,
              busy: _busy,
              onTap: _busy ? null : _submit,
            ),
            const SizedBox(height: OlGap.sm),
            Center(
              child: GestureDetector(
                onTap: () => setState(() => _mode = _mode == AuthMode.password ? AuthMode.token : AuthMode.password),
                child: Text(
                  '使用 API Token 登录',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _mode == AuthMode.token ? const Color(0xFF7DD3FC) : const Color(0xFF8FA8BD),
                  ),
                ),
              ),
            ),
            const SizedBox(height: OlGap.lg),
            const _ServerEntry(dark: true),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// W1 左侧品牌区
// ---------------------------------------------------------------------------
class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.8, -1),
          end: Alignment(0.9, 1),
          colors: [Color(0xFF0A1A2B), Color(0xFF0E2C40), Color(0xFF0F3A46)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(left: -80, top: -120, child: _glow(420, const Color(0x2638BDF8))),
          Positioned(right: -120, bottom: -140, child: _glow(420, const Color(0x1F2DD4BF))),
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 40, 36, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const OlMark(size: 34, radius: 10, iconSize: 17),
                    const SizedBox(width: OlGap.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'OpenList Client',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: Color(0xFFE8F2FA)),
                        ),
                        Text(
                          'WINDOWS EDITION',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: const Color(0xFF7DD3FC).withAlpha(200),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 44),
                const Text(
                  'YOUR CLOUDS, ONE WINDOW',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 2.4, color: Color(0xFF7DD3FC)),
                ),
                const SizedBox(height: 14),
                const Text(
                  '所有云盘，收进一个窗口。',
                  style: TextStyle(fontSize: 34, height: 1.12, letterSpacing: -1.4, fontWeight: FontWeight.w800, color: Color(0xFFF2F8FD)),
                ),
                const SizedBox(height: 16),
                const SizedBox(
                  width: 420,
                  child: Text(
                    '直连你自建的 OpenList 服务。文件不中转、不落第三方，速度只取决于你的带宽。',
                    style: TextStyle(fontSize: 12.5, height: 1.75, color: Color(0xFF9EBBCE)),
                  ),
                ),
                const SizedBox(height: 32),
                const _HeroFeature(icon: 'zap', title: '原生多线程传输', desc: '断点续传、并发可调、托盘后台不中断'),
                const _HeroFeature(icon: 'play', title: '边下边播', desc: '支持 4K HDR 与字幕轨道，Range 直读不落地'),
                const _HeroFeature(icon: 'shield', title: '凭据本地保存', desc: 'Token 写入 Windows 凭据管理器，可随时吊销'),
                const Spacer(),
                const _MountedCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withAlpha(0)])),
      );
}

class _HeroFeature extends StatelessWidget {
  final String icon;
  final String title;
  final String desc;

  const _HeroFeature({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(OlTokens.r4),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Center(child: OlIcon(icon, size: 15, color: const Color(0xFF7DD3FC))),
          ),
          const SizedBox(width: OlGap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFFE8F2FA))),
                const SizedBox(height: 3),
                Text(desc, style: const TextStyle(fontSize: 10.5, height: 1.55, color: Color(0xFF8FA8BD))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MountedCard extends StatelessWidget {
  const _MountedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420,
      padding: const EdgeInsets.all(OlGap.sm),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(OlTokens.rPanel),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'MOUNTED',
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: Color(0xFF7DD3FC)),
              ),
              const SizedBox(width: 6),
              Container(width: 1, height: 9, color: const Color(0x24FFFFFF)),
              const SizedBox(width: 6),
              const Text(
                '5 SOURCES',
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Color(0xFF8FA8BD)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _MountRow('阿里云盘', '2.4 TB', Color(0xFF38BDF8)),
          const _MountRow('OneDrive', '1.0 TB', Color(0xFF2DD4BF)),
          const _MountRow('本地 NAS', '8.0 TB', Color(0xFF7C5CFC)),
          const SizedBox(height: 8),
          const Text(
            '统一命名空间 · 一棵目录树',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF6E879C)),
          ),
        ],
      ),
    );
  }
}

class _MountRow extends StatelessWidget {
  final String name;
  final String size;
  final Color color;

  const _MountRow(this.name, this.size, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2.5))),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w650, color: Color(0xFFCFE6F3)))),
          Text(size, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF8FA8BD))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// W1 右侧表单卡
// ---------------------------------------------------------------------------
class _FormCard extends StatelessWidget {
  final AuthMode mode;
  final TextEditingController url;
  final TextEditingController user;
  final TextEditingController secret;
  final TextEditingController name;
  final bool obscure;
  final bool busy;
  final bool keepSignedIn;
  final String? inlineError;
  final String? probeOk;
  final int? probeMs;
  final ValueChanged<AuthMode> onMode;
  final VoidCallback onObscure;
  final ValueChanged<bool> onKeep;
  final VoidCallback onProbe;
  final VoidCallback onSubmit;

  const _FormCard({
    required this.mode,
    required this.url,
    required this.user,
    required this.secret,
    required this.name,
    required this.obscure,
    required this.busy,
    required this.keepSignedIn,
    required this.inlineError,
    required this.probeOk,
    required this.probeMs,
    required this.onMode,
    required this.onObscure,
    required this.onKeep,
    required this.onProbe,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.all(OlGap.lg),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(OlTokens.rCard),
        border: Border.all(color: p.line),
        boxShadow: const [BoxShadow(color: Color(0x1A0D1B2A), blurRadius: 34, offset: Offset(0, 14))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'WELCOME BACK',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2.2, color: Color(0xFF0EA5E9)),
          ),
          const SizedBox(height: 8),
          Text('连接到你的服务器', style: OlText.h3.copyWith(color: p.ink)),
          const SizedBox(height: 6),
          Text('输入 OpenList 地址，客户端会自动探测版本与站点名称。', style: TextStyle(fontSize: 11, height: 1.6, color: p.ink3)),
          const SizedBox(height: OlGap.lg),
          const _Label('服务器地址', hint: '含协议与端口'),
          const SizedBox(height: 6),
          OlField(
            controller: url,
            icon: 'globe',
            hint: 'https://pan.mydomain.com',
            keyboardType: TextInputType.url,
            onSubmitted: (_) => onProbe(),
            trailing: _ProbePill(ok: probeOk, ms: probeMs, onTap: onProbe),
          ),
          if (inlineError != null) ...[const SizedBox(height: 7), _InlineError(inlineError!)],
          if (probeOk != null) ...[const SizedBox(height: 7), _ProbeOk(probeOk!, probeMs)],
          const SizedBox(height: OlGap.sm),
          const _Label('显示名称', hint: '留空则用站点名'),
          const SizedBox(height: 6),
          OlField(controller: name, icon: 'server', hint: '家庭主服务器'),
          const SizedBox(height: OlGap.sm),
          const _Label('认证方式'),
          const SizedBox(height: 6),
          OlSeg<AuthMode>(
            items: const [
              OlSegItem(AuthMode.password, '密码', icon: 'lock'),
              OlSegItem(AuthMode.token, 'API Token', icon: 'key'),
            ],
            value: mode,
            onChanged: onMode,
          ),
          const SizedBox(height: OlGap.sm),
          _Label(mode == AuthMode.token ? '用户名（可选）' : '用户名'),
          const SizedBox(height: 6),
          OlField(controller: user, icon: 'user', hint: 'admin'),
          const SizedBox(height: OlGap.sm),
          _Label(mode == AuthMode.token ? 'API Token' : '密码'),
          const SizedBox(height: 6),
          OlField(
            controller: secret,
            icon: mode == AuthMode.token ? 'key' : 'lock',
            hint: mode == AuthMode.token ? '粘贴服务端生成的 Token' : '••••••••',
            obscure: obscure,
            onSubmitted: (_) => onSubmit(),
            trailing: GestureDetector(
              onTap: onObscure,
              child: OlIcon(obscure ? 'eye-off' : 'eye', size: 15, color: const Color(0xFF8FA1B3)),
            ),
          ),
          const SizedBox(height: OlGap.md),
          Row(
            children: [
              OlSwitch(value: keepSignedIn, onChanged: onKeep, small: true),
              const SizedBox(width: 8),
              Text('保持登录', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w650, color: p.ink2)),
            ],
          ),
          const SizedBox(height: OlGap.lg),
          OlPrimaryButton(
            label: '连接并登录',
            icon: 'zap',
            height: 36,
            fontSize: 12.5,
            expand: true,
            busy: busy,
            onTap: busy ? null : onSubmit,
          ),
          const SizedBox(height: OlGap.sm),
          Row(
            children: [
              Expanded(child: Container(height: 1, color: p.line2)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('OR', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: p.ink4)),
              ),
              Expanded(child: Container(height: 1, color: p.line2)),
            ],
          ),
          const SizedBox(height: OlGap.sm),
          SizedBox(
            width: double.infinity,
            child: OlGhostButton(
              label: '使用 API Token 登录',
              icon: 'key',
              height: 34,
              onTap: () => onMode(AuthMode.token),
            ),
          ),
          const SizedBox(height: OlGap.md),
          const _ServerEntry(dark: false),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final String? hint;

  const _Label(this.text, {this.hint});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Row(
      children: [
        Text(text.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: p.ink3)),
        if (hint != null) ...[
          const SizedBox(width: 7),
          Text(hint!, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4)),
        ],
      ],
    );
  }
}

class _ProbePill extends StatelessWidget {
  final String? ok;
  final int? ms;
  final VoidCallback onTap;

  const _ProbePill({required this.ok, required this.ms, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = ok != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: done ? const Color(0xFFE7FBF5) : const Color(0xFFF3F8FC),
          borderRadius: BorderRadius.circular(OlTokens.r4),
          border: Border.all(color: done ? const Color(0xFFCDEFE7) : const Color(0xFFE7EEF6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OlIcon(done ? 'check' : 'refresh', size: 12, color: done ? const Color(0xFF0B7A63) : const Color(0xFF8FA1B3)),
            const SizedBox(width: 5),
            Text(
              done ? '已连接' : '探测',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: done ? const Color(0xFF0B7A63) : const Color(0xFF8FA1B3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError(this.message);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OlIcon('alert', size: 13, color: Color(0xFFD92D4B)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 10.5, height: 1.5, fontWeight: FontWeight.w600, color: Color(0xFFD92D4B)),
          ),
        ),
      ],
    );
  }
}

class _ProbeOk extends StatelessWidget {
  final String title;
  final int? ms;
  const _ProbeOk(this.title, this.ms);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const OlIcon('check', size: 13, color: Color(0xFF0B7A63)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ms == null ? '$title · 已连接' : '$title · 已连接 ${ms}ms',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF0B7A63)),
          ),
        ),
      ],
    );
  }
}

/// 「服务器管理」入口 —— 0 个已保存时也必须可见（08 验收标准）。
class _ServerEntry extends StatelessWidget {
  final bool dark;
  const _ServerEntry({required this.dark});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final fg = dark ? const Color(0xFFCFE6F3) : p.ink2;
    final border = dark ? const Color(0x1AFFFFFF) : p.line;
    final bg = dark ? const Color(0x0FFFFFFF) : p.surface;
    return GestureDetector(
      onTap: () => context.go('/servers'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(OlTokens.rField),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              OlIcon('server', size: 15, color: dark ? const Color(0xFF7DD3FC) : const Color(0xFF0EA5E9)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('服务器管理', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: fg)),
                    const SizedBox(height: 2),
                    Text(
                      '切换 / 添加 / 编辑，数量不限',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: dark ? const Color(0xFF6E879C) : p.ink4),
                    ),
                  ],
                ),
              ),
              OlIcon('chev-r', size: 13, color: dark ? const Color(0xFF6E879C) : p.ink4),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImmersiveHeadline extends StatelessWidget {
  const _ImmersiveHeadline();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        style: TextStyle(fontSize: 26, height: 1.2, letterSpacing: -0.8, fontWeight: FontWeight.w800, color: Color(0xFFF2F8FD)),
        children: [
          TextSpan(text: '你的云盘，'),
          TextSpan(
            text: '随身携带',
            style: TextStyle(color: Color(0xFF7DD3FC), shadows: [Shadow(color: Color(0x4D38BDF8), blurRadius: 18)]),
          ),
          TextSpan(text: '。'),
        ],
      ),
    );
  }
}
