import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/app_info.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import 'download_dir.dart';
import 'settings_sidebar.dart';

/// W6（Windows 设置）/ A6（Android 我的）。
///
/// 账户与存储分开：账户决定登录态，存储只读展示每个挂载点的健康与容量。
/// 管理后台写操作一律跳浏览器（产品基线 02）。
///
/// 分区切换同时做两件事：本地 setState（保证点击即有反馈）+ 同步路由
/// `/settings/<tab>`（保证深链与返回栈正确）。只改 query 时同一路由不会重建，
/// 是 v1.0.5「设置分区点不开」的根因。
class SettingsPage extends ConsumerStatefulWidget {
  final String tab;
  const SettingsPage({super.key, this.tab = 'appearance'});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late String _tab = widget.tab;

  static const _known = {'servers', 'transfer', 'download', 'playback', 'appearance', 'about'};

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab != oldWidget.tab) _tab = widget.tab;
  }

  void _select(String tab) {
    if (!_known.contains(tab)) return;
    setState(() => _tab = tab);
    context.go('/settings/$tab');
  }

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) {
      // A6：/settings 是「我的」列表；/settings/<tab> 是分区页（带返回）。
      final showList = _tab == 'servers' || _tab == 'profile' || !_known.contains(_tab);
      if (showList) return const AppFrame(navIndex: 3, child: _MobileSettings());
      return _MobileSectionPage(tab: _tab);
    }
    return AppFrame(
      showNav: false,
      child: Row(
        children: [
          SettingsSidebar(active: _tab, onSelect: _select),
          Expanded(
            child: ColoredBox(
              color: context.ol.card,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: _SectionBody(section: _tab),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 分区路由
// ---------------------------------------------------------------------------
class _SectionBody extends ConsumerWidget {
  final String section;
  const _SectionBody({required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (section) {
      case 'transfer':
        return const _TransferSection();
      case 'download':
        return const _DownloadSection();
      case 'playback':
        return const _PlaybackSection();
      case 'about':
        return const _AboutSection();
      case 'appearance':
        return const _AppearanceSection();
      case 'servers':
      default:
        return const _ServersSection();
    }
  }
}

// ---------------------------------------------------------------------------
// 通用块
// ---------------------------------------------------------------------------
class _SectionHead extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  const _SectionHead({required this.title, required this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14.5, letterSpacing: -0.3, fontWeight: FontWeight.w800, color: p.ink)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 10.5, color: p.ink4)),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: p.line2),
      ),
      child: child,
    );
  }
}

class _Row extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
          child: Row(
            children: [
              Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(6)),
                child: Center(child: OlIcon(icon, size: 12, color: p.ink3)),
              ),
              const SizedBox(width: 9),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink2),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: p.ink4),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // v2.3：trailing 必须限宽并右对齐。之前服务端版本串没有约束，
              // 会把标题列挤到只剩 1 个字宽，整行变成竖排中文。
              Flexible(
                flex: 2,
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) => OlSectionLabel(text);
}

// ---------------------------------------------------------------------------
// 服务器
// ---------------------------------------------------------------------------
class _ServersSection extends ConsumerWidget {
  const _ServersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    final profile = session.profile;
    final servers = ref.watch(serverListProvider).servers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHead(
          title: '服务器管理',
          subtitle: '当前连接的 OpenList 实例与登录身份',
          action: OlGhostButton(label: '添加服务器', icon: 'plus', height: 28, fontSize: 10.5, onTap: () => context.push('/servers')),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF7FCFE), Color(0xFFF2FBF9)],
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: p.line2),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(gradient: OlTokens.gradientBrand, borderRadius: BorderRadius.circular(11)),
                child: const Center(child: OlIcon('server', size: 18, color: Colors.white)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile?.displayHost ?? '未连接',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.ink),
                          ),
                        ),
                        const SizedBox(width: 7),
                        OlBadge(
                          label: session.signedIn ? '已连接' : '未连接',
                          fg: session.signedIn ? const Color(0xFF0B7A63) : const Color(0xFFB47405),
                          bg: session.signedIn ? const Color(0xFFE7FBF5) : const Color(0xFFFFF6E5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        profile?.username ?? '—',
                        session.user?.role == 3 ? '管理员' : '普通用户',
                        profile?.version ?? session.site?.version ?? 'API v4',
                        if (session.latencyMs != null) '${session.latencyMs} ms',
                        '${servers.length} 个服务器',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9.5, color: p.ink4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OlGhostButton(label: '管理', height: 26, fontSize: 10, onTap: () => context.push('/servers')),
            ],
          ),
        ),
        _GroupLabel('已保存的服务器'),
        _Card(
          child: Column(
            children: [
              if (servers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text('还没有服务器，点右上角「添加服务器」', style: TextStyle(fontSize: 10.5, color: p.ink4)),
                ),
              for (var i = 0; i < servers.length; i++)
                _Row(
                  icon: 'server',
                  title: servers[i].name,
                  subtitle: servers[i].baseUrl,
                  trailing: Text(
                    servers[i].id == profile?.id ? '当前' : '切换',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: servers[i].id == profile?.id ? OlTokens.sky700 : p.ink4),
                  ),
                  onTap: () => context.go('/servers/edit/${servers[i].id}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _InfoStrip(text: '管理后台（只读）：客户端只调用 /api/admin/storage/list；创建、用户与索引在浏览器完成。'),
      ],
    );
  }
}

class _InfoStrip extends StatelessWidget {
  final String text;
  const _InfoStrip({required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.line2),
      ),
      child: Row(
        children: [
          const OlIcon('info', size: 14, color: Color(0xFF0EA5E9)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 9.5, height: 1.6, color: p.ink3))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 存储挂载（只读）
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// 下载目录（v2.2：独立分区，替代原「存储挂载」入口）
// ---------------------------------------------------------------------------
class _DownloadSection extends ConsumerStatefulWidget {
  const _DownloadSection();

  @override
  ConsumerState<_DownloadSection> createState() => _DownloadSectionState();
}

class _DownloadSectionState extends ConsumerState<_DownloadSection> {
  String? _dir;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final profile = ref.read(sessionProvider).profile;
    if (profile == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final dir = await resolveDownloadDir(ref, profile);
    if (!mounted) return;
    setState(() {
      _dir = dir;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final profile = ref.watch(sessionProvider).profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '下载目录', subtitle: '下载与断点续传的落盘位置，按实例隔离'),
        _GroupLabel('当前目录'),
        _Card(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(9)),
                    child: Center(child: OlIcon('download', size: 15, color: p.ink3)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      profile == null
                          ? '未连接服务器'
                          : (_loading ? '读取中…' : (_dir ?? '默认目录（按实例隔离）')),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, height: 1.5, fontWeight: FontWeight.w600, color: p.ink2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OlSoftButton(
                      label: '更改目录',
                      icon: 'folder',
                      onTap: profile == null
                          ? null
                          : () async {
                              await showDownloadDirDialog(context, ref);
                              await _load();
                            },
                    ),
                  ),
                  // v2.3：Android 去掉「授权说明」按钮（授权在选目录时按提示完成），
                  // 桌面保留「打开目录」——这是唯一能从设置跳到磁盘的入口。
                  if (!Platform.isAndroid) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OlGhostButton(
                        label: '打开目录',
                        icon: 'external',
                        onTap: () {
                          final dir = _dir;
                          if (dir == null) return;
                          Process.run('explorer', [dir]);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        _GroupLabel('其他'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'refresh',
                title: '恢复默认目录',
                subtitle: '清除本实例的自定义目录',
                trailing: Text('重置', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: p.ink3)),
                onTap: profile == null
                    ? null
                    : () async {
                        await ref.read(serverStoreProvider).clearDownloadDir(profile.id);
                        await _load();
                        if (context.mounted) olToast(context, '已恢复默认目录');
                      },
              ),
              _Row(
                icon: 'hard-drive',
                title: '按实例隔离',
                subtitle: '多服务器各自独立目录，避免同名覆盖',
                trailing: Text(profile?.isolatedDownload == true ? '已开启' : '已关闭', style: TextStyle(fontSize: 9.5, color: p.ink4)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 传输 / 播放 / 通知
// ---------------------------------------------------------------------------
class _TransferSection extends ConsumerWidget {
  const _TransferSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.watch(appSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '传输', subtitle: '并发与限速'),
        _GroupLabel('限速'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'download',
                title: '下载限速',
                subtitle: '0 表示不限速',
                trailing: _ValuePill('${settings.downLimitKbps} KB/s'),
                onTap: () => _editNumber(
                  context,
                  title: '下载限速',
                  current: settings.downLimitKbps,
                  onDone: notifier.setDownLimit,
                ),
              ),
              _Row(
                icon: 'upload',
                title: '上传限速',
                subtitle: '0 表示不限速',
                trailing: _ValuePill('${settings.upLimitKbps} KB/s'),
                onTap: () => _editNumber(
                  context,
                  title: '上传限速',
                  current: settings.upLimitKbps,
                  onDone: notifier.setUpLimit,
                ),
              ),
              _Row(
                icon: 'zap',
                title: '并发任务数',
                subtitle: '同时进行的传输数量',
                trailing: _ValuePill('${settings.concurrency}'),
                onTap: () => _editNumber(
                  context,
                  title: '并发任务数',
                  current: settings.concurrency,
                  onDone: notifier.setConcurrency,
                  max: 8,
                ),
              ),
            ],
          ),
        ),
        _GroupLabel('行为'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'wifi',
                title: '仅在 Wi-Fi 下传输',
                subtitle: '移动网络下排队等待',
                trailing: OlSwitch(value: settings.wifiOnly, small: true, onChanged: notifier.setWifiOnly),
              ),
              _Row(
                icon: 'cloud',
                title: '后台保持传输',
                subtitle: '关闭窗口后继续下载',
                trailing: OlSwitch(value: settings.backgroundTransfer, small: true, onChanged: notifier.setBackgroundTransfer),
              ),
              _Row(
                icon: 'anchor',
                title: '切换服务器时暂停旧任务',
                subtitle: '避免多实例抢占带宽',
                trailing: OlSwitch(value: settings.pauseOnSwitch, small: true, onChanged: notifier.setPauseOnSwitch),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editNumber(
    BuildContext context, {
    required String title,
    required int current,
    required ValueChanged<int> onDone,
    int max = 1024 * 1024,
  }) async {
    final controller = TextEditingController(text: '$current');
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '0 表示不限'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop((int.tryParse(controller.text.trim()) ?? 0).clamp(0, max).toInt()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) onDone(value);
  }
}

class _ValuePill extends StatelessWidget {
  final String text;
  const _ValuePill(this.text);

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line2)),
      child: Text(text, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: p.ink2)),
    );
  }
}

class _PlaybackSection extends ConsumerWidget {
  const _PlaybackSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.watch(appSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '播放与预览', subtitle: '断点续播、自动播放与默认倍速'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'clock',
                title: '断点续播',
                subtitle: '记住上次播放位置',
                trailing: OlSwitch(value: settings.resumePlayback, small: true, onChanged: notifier.setResumePlayback),
              ),
              _Row(
                icon: 'play',
                title: '自动播放下一集',
                subtitle: '同目录视频按顺序连播',
                trailing: OlSwitch(value: settings.autoPlayNext, small: true, onChanged: notifier.setAutoPlayNext),
              ),
              _Row(
                icon: 'zap',
                title: '默认倍速',
                subtitle: '播放器首次打开时使用',
                trailing: _ValuePill('${settings.playbackSpeed.toStringAsFixed(1)}×'),
                onTap: () => _pickSpeed(context, notifier, settings.playbackSpeed),
              ),
              _Row(
                icon: 'film',
                title: '优先直连播放',
                subtitle: 'Range 直读，不落地缓存',
                trailing: Text('固定', style: TextStyle(fontSize: 9.5, color: context.ol.ink4)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickSpeed(BuildContext context, AppSettingsNotifier notifier, double current) async {
    final value = await showModalBottomSheet<double>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final speed in const [0.75, 1.0, 1.25, 1.5, 2.0])
              ListTile(
                dense: true,
                title: Text('${speed.toStringAsFixed(2)}×', style: const TextStyle(fontSize: 12.5)),
                trailing: speed == current ? const OlIcon('check', size: 14, color: Color(0xFF0EA5E9)) : null,
                onTap: () => Navigator.of(sheetContext).pop(speed),
              ),
          ],
        ),
      ),
    );
    if (value != null) notifier.setPlaybackSpeed(value);
  }
}

// ---------------------------------------------------------------------------
// 外观
// ---------------------------------------------------------------------------
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.watch(appSettingsProvider.notifier);
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '外观', subtitle: '默认跟随系统；播放器始终深色'),
        _GroupLabel('主题'),
        _Card(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              _ThemeCard(
                label: '浅色',
                selected: settings.themeMode == ThemeMode.light,
                gradient: const LinearGradient(colors: [Color(0xFFF4F8FC), Color(0xFFE9F1F8)]),
                onTap: () => notifier.setTheme(ThemeMode.light),
              ),
              const SizedBox(width: 9),
              _ThemeCard(
                label: '深色',
                selected: settings.themeMode == ThemeMode.dark,
                gradient: const LinearGradient(colors: [Color(0xFF0D1A29), Color(0xFF13293B)]),
                onTap: () => notifier.setTheme(ThemeMode.dark),
              ),
              const SizedBox(width: 9),
              _ThemeCard(
                label: '跟随系统',
                selected: settings.themeMode == ThemeMode.system,
                gradient: const LinearGradient(colors: [Color(0xFFF4F8FC), Color(0xFF0D1A29)]),
                onTap: () => notifier.setTheme(ThemeMode.system),
              ),
            ],
          ),
        ),
        _GroupLabel('列表'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'panel',
                title: '紧凑列表',
                subtitle: '行高 36px，单屏显示更多',
                trailing: Text('固定 44px', style: TextStyle(fontSize: 9.5, color: p.ink4)),
              ),
              _Row(
                icon: 'image',
                title: '显示缩略图',
                subtitle: '图片与视频封面预览',
                trailing: Text('自动', style: TextStyle(fontSize: 9.5, color: p.ink4)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final String label;
  final bool selected;
  final LinearGradient gradient;
  final VoidCallback onTap;
  const _ThemeCard({required this.label, required this.selected, required this.gradient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              height: 54,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: selected ? OlTokens.sky600 : p.line2, width: selected ? 2 : 1),
              ),
              child: selected
                  ? const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(5),
                        child: OlIcon('check', size: 12, color: Color(0xFF0EA5E9)),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? p.ink : p.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '关于与更新', subtitle: '版本信息与项目链接'),
        _Card(
          child: Column(
            children: [
              _Row(
                icon: 'layers',
                title: 'OpenList Client',
                subtitle: 'Windows 便携版 · Android · 单代码库',
                trailing: Text(
                  AppInfo.versionLabel,
                  maxLines: 1,
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: p.ink3),
                ),
              ),
              _Row(
                icon: 'server',
                title: '服务端',
                subtitle: session.profile?.displayHost ?? '未连接',
                trailing: Text(
                  AppInfo.shortVersion(session.profile?.version ?? session.site?.version),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: p.ink3),
                ),
              ),
              _Row(
                icon: 'external',
                title: '项目主页',
                subtitle: 'github.com/david88558855/OpenList-Client',
                trailing: const OlIcon('chev-r', size: 13, color: Color(0xFF0EA5E9)),
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/david88558855/OpenList-Client'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              _Row(
                icon: 'refresh',
                title: '检查更新',
                subtitle: '便携版 zip 解压即用',
                trailing: Text('已是最新', maxLines: 1, style: TextStyle(fontSize: 10, color: p.ink4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '第三方程式库版权归各自作者所有；OpenList 品牌素材归 OpenList Team。',
          style: TextStyle(fontSize: 9, height: 1.6, color: p.ink4),
        ),
        const SizedBox(height: 16),
        // v2.1：退出登录从「隐私与安全」移到「关于」下方，作为最后一项。
        SizedBox(
          width: double.infinity,
          child: OlDangerButton(
            label: '退出登录',
            icon: 'logout',
            height: 34,
            onTap: () async {
              await ref.read(sessionProvider.notifier).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// A6 · Android 我的
// ---------------------------------------------------------------------------

/// A6 分区页：带返回的分区详情（v2.2）。
class _MobileSectionPage extends ConsumerWidget {
  final String tab;
  const _MobileSectionPage({required this.tab});

  static const _titles = {
    'transfer': '传输',
    'download': '下载目录',
    'playback': '播放与预览',
    'appearance': '外观',
    'about': '关于与更新',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/settings');
      },
      child: AppFrame(
        navIndex: 3,
        showNav: false,
        child: ColoredBox(
          color: p.card,
          child: Column(
            children: [
              SizedBox(
                height: 54,
                child: Row(
                  children: [
                    OlIconButton(icon: 'chev-l', size: 34, iconSize: 18, onTap: () => context.go('/settings')),
                    const SizedBox(width: 2),
                    Text(
                      _titles[tab] ?? '设置',
                      style: TextStyle(fontSize: 17, letterSpacing: -0.4, fontWeight: FontWeight.w800, color: p.ink),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  child: _SectionBody(section: tab),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileSettings extends ConsumerWidget {
  const _MobileSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    final profile = session.profile;
    return ColoredBox(
      color: p.card,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 10, OlGap.pageMobile, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0B2233), Color(0xFF0D3B46)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(gradient: OlTokens.gradientBrand, borderRadius: BorderRadius.circular(14)),
                  child: const Center(child: OlIcon('user', size: 22, color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.username ?? '未登录',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile == null
                            ? '未连接服务器'
                            : '${profile.displayHost} · ${AppInfo.shortVersion(profile.version ?? session.site?.version)}',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9DB4C8)),
                      ),
                    ],
                  ),
                ),
                OlBadge(
                  label: session.offline ? '离线' : (session.signedIn ? '已连接' : '未登录'),
                  fg: session.offline ? const Color(0xFF5E4A22) : const Color(0xFF0B5C4C),
                  bg: session.offline ? const Color(0xFFFCD9A0) : const Color(0xFF7DD3FC),
                ),
              ],
            ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileGroup(
                  title: '账户',
                  children: [
                    _MobileTile(icon: 'server', label: '服务器管理', value: '切换 / 添加 / 编辑', onTap: () => context.push('/servers')),
                  ],
                ),
                _MobileGroup(
                  title: '传输与播放',
                  children: [
                    // v2.3：下载目录提到传输设置之上（真机上更常改目录）。
                    _MobileTile(icon: 'download', label: '下载目录', value: '查看 / 更改', onTap: () => context.go('/settings/download')),
                    _MobileTile(icon: 'arrow-down', label: '传输设置', value: '并发 / 限速', onTap: () => context.go('/settings/transfer')),
                    _MobileTile(icon: 'play', label: '播放与预览', value: '续播 / 自动播放 / 倍速', onTap: () => context.go('/settings/playback')),
                  ],
                ),
                _MobileGroup(
                  title: '应用',
                  children: [
                    _MobileTile(icon: 'sun', label: '外观', value: '跟随系统', onTap: () => context.go('/settings/appearance')),
                    _MobileTile(icon: 'info', label: '关于 OpenList', value: AppInfo.version, onTap: () => context.go('/settings/about')),
                    // v2.1：退出登录放在「关于」下方。
                    _MobileTile(
                      icon: 'logout',
                      label: '退出登录',
                      value: '',
                      danger: true,
                      onTap: () async {
                        await ref.read(sessionProvider.notifier).signOut();
                        if (context.mounted) context.go('/login');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${AppInfo.shortLabel} · Android · API v4',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8.5, color: p.ink4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _MobileGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
          child: Text(
            title,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.ink4),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: p.line2),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _MobileTile extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final bool danger;
  final VoidCallback onTap;
  const _MobileTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return InkWell(
      onTap: onTap,
      child: Container(
        // v2.3：行高 50 → 58，图标与字号同步放大，避免文字被裁。
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
        child: Row(
          children: [
            OlIcon(icon, size: 18, color: danger ? const Color(0xFFD92D4B) : p.ink3),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: danger ? const Color(0xFFD92D4B) : p.ink),
              ),
            ),
            if (value.isNotEmpty)
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: p.ink4),
                ),
              ),
            const SizedBox(width: 6),
            OlIcon('chev-r', size: 15, color: p.ink4),
          ],
        ),
      ),
    );
  }
}
