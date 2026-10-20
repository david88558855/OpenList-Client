part of '../settings_page.dart';

// 各设置分区：服务器（只读）、下载目录、传输、播放与预览、外观、关于

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
          action: OlGhostButton(label: '添加服务器', icon: 'plus', height: 28, fontSize: 10.5, onTap: () => context.go('/servers')),
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
                        if (AppInfo.hasMeaningfulVersion(profile?.version ?? session.site?.version))
                          AppInfo.shortVersion(profile?.version ?? session.site?.version),
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
              OlGhostButton(label: '管理', height: 26, fontSize: 10, onTap: () => context.go('/servers')),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(title: '关于与更新', subtitle: '项目链接'),
        _Card(
          child: Column(
            children: [
              // v1.0.28：关于页只保留「项目主页」，其余（客户端版本 / 服务端 /
              // 数据目录 / 检查更新 / 退出登录）已移除。
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
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '第三方程式库版权归各自作者所有；OpenList 品牌素材归 OpenList Team。',
          style: TextStyle(fontSize: 9, height: 1.6, color: p.ink4),
        ),
      ],
    );
  }
}
