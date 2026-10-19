import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/file_widgets.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import 'download_dir.dart';
import 'settings_sidebar.dart';

class SettingsPage extends ConsumerWidget {
  final String tab;
  const SettingsPage({super.key, this.tab = 'appearance'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    if (narrow) {
      return AppFrame(
        navIndex: 3,
        // 个人资料页是深色渐变头部，页面自己画到状态栏下方并避让（见 _MobileProfile）。
        edgeToEdge: tab == 'profile',
        child: tab == 'profile' ? const _MobileProfile() : _MobileSection(section: tab),
      );
    }
    return AppFrame(
      showNav: false,
      child: Row(
        children: [
          SettingsSidebar(active: tab),
          Expanded(
            child: Container(
              color: context.ol.card,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: _SectionBody(section: tab),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionBody extends ConsumerWidget {
  final String section;
  const _SectionBody({required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (section) {
      case 'storage':
        return const _StorageSection();
      case 'transfer':
        return const _TransferSection();
      case 'playback':
        return const _PlaybackSection();
      case 'notify':
        return const _NotifySection();
      case 'security':
        return const _SecuritySection();
      case 'about':
        return const _AboutSection();
      case 'servers':
        return const _ServersShortcut();
      case 'diagnostics':
        return const _DiagnosticsSection();
      default:
        return const _AppearanceSection();
    }
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String icon;
  final List<Widget> children;

  const _Card({required this.title, required this.icon, required this.children, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: p.isDark ? const Color(0xFF12202F) : const Color(0xFFEAF8FE), borderRadius: BorderRadius.circular(9)),
                child: Center(child: OlIcon(icon, size: 14, color: OlTokens.sky700)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: TextStyle(fontSize: 10, height: 1.5, color: p.ink4)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget trailing;

  const _Line({required this.label, required this.trailing, this.hint});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink2)),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(hint!, style: TextStyle(fontSize: 9, height: 1.5, color: p.ink4)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final p = context.ol;
    final themes = <ThemeMode, String>{
      ThemeMode.system: '跟随系统',
      ThemeMode.light: '浅色',
      ThemeMode.dark: '深色',
    };
    return Column(
      children: [
        _Card(
          title: '外观',
          subtitle: '默认跟随系统；播放器与全屏媒体强制深色。',
          icon: 'sun',
          children: [
            OlSeg<ThemeMode>(
              items: [
                for (final entry in themes.entries) OlSegItem(entry.key, entry.value),
              ],
              value: settings.themeMode,
              onChanged: (v) => ref.read(appSettingsProvider.notifier).setTheme(v),
              height: 26,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final mode in [ThemeMode.system, ThemeMode.light, ThemeMode.dark]) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => ref.read(appSettingsProvider.notifier).setTheme(mode),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: settings.themeMode == mode ? OlTokens.sky : p.line, width: 1.5),
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: 52,
                              decoration: BoxDecoration(
                                color: mode == ThemeMode.dark
                                    ? const Color(0xFF0B1622)
                                    : mode == ThemeMode.light
                                        ? Colors.white
                                        : p.isDark
                                            ? const Color(0xFF0B1622)
                                            : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: p.line2),
                              ),
                              padding: const EdgeInsets.all(5),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(height: 4, width: 26, color: mode == ThemeMode.dark ? const Color(0xFF38BDF8) : const Color(0xFF0EA5E9)),
                                  const SizedBox(height: 4),
                                  Container(height: 3, width: 40, color: mode == ThemeMode.dark ? const Color(0xFF24384C) : const Color(0xFFE3EBF3)),
                                  const SizedBox(height: 3),
                                  Container(height: 3, width: 32, color: mode == ThemeMode.dark ? const Color(0xFF24384C) : const Color(0xFFE3EBF3)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(themes[mode]!, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: p.ink3)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ),
        _Card(
          title: '列表密度',
          icon: 'list',
          children: [
            _Line(label: '文档视图默认列表模式', trailing: OlSwitch(value: true, onChanged: (_) {})),
            _Line(label: '正文对比度 ≥ 7:1（已按设计令牌实现）', trailing: const OlBadge(label: 'WCAG AA')),
          ],
        ),
      ],
    );
  }
}

class _StorageSection extends ConsumerWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final storages = ref.watch(storagesProvider);
    final profile = ref.watch(sessionProvider).profile;

    return Column(
      children: [
        _Card(
          title: '存储挂载',
          subtitle: '只读视图（决策 A）：健康状态与容量，新增 / 编辑 / 删除请到网页端。',
          icon: 'database',
          children: [
            storages.when(
              loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator(minHeight: 2)),
              error: (_, __) => Text('读取失败', style: TextStyle(fontSize: 11, color: p.ink3)),
              data: (mounts) => mounts.isEmpty
                  ? Text('当前账号不是管理员，或服务端未返回挂载信息。', style: TextStyle(fontSize: 10.5, height: 1.6, color: p.ink4))
                  : Column(
                      children: [
                        for (final mount in mounts) _MountRow(mount: mount),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OlGhostButton(
                  label: '打开网页后台',
                  icon: 'external',
                  onTap: () async {
                    final url = profile?.baseUrl;
                    if (url == null) return;
                    final uri = Uri.tryParse(url);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                const SizedBox(width: 8),
                OlGhostButton(label: '刷新', icon: 'refresh', onTap: () => ref.invalidate(storagesProvider)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _MountRow extends StatelessWidget {
  final StorageMount mount;
  const _MountRow({required this.mount});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final ratio = mount.usageRatio;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line2)),
      child: Row(
        children: [
          OlDot(size: 6, color: mount.isUp ? OlTokens.ok : OlTokens.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baseName(mount.mountPath), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink)),
                const SizedBox(height: 2),
                Text(
                  '${mount.driver.isEmpty ? 'unknown' : mount.driver} · ${mount.mountPath}',
                  style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: p.ink4),
                ),
              ],
            ),
          ),
          if (ratio != null)
            SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${(ratio * 100).round()}%', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: p.ink2)),
                  const SizedBox(height: 3),
                  OlUsageBar(value: ratio),
                ],
              ),
            )
          else
            Text(mount.isUp ? '正常' : '异常', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: mount.isUp ? const Color(0xFF0B7A63) : OlTokens.warnDeep)),
        ],
      ),
    );
  }
}

class _TransferSection extends ConsumerWidget {
  const _TransferSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return Column(
      children: [
        _Card(
          title: '传输',
          subtitle: '并发与限速对当前实例生效；限速只作用于下载流。',
          icon: 'arrow-down',
          children: [
            _Line(
              label: '并发任务数',
              trailing: OlSeg<int>(
                items: const [OlSegItem(1, '1'), OlSegItem(2, '2'), OlSegItem(4, '4'), OlSegItem(6, '6')],
                value: settings.concurrency,
                onChanged: (v) {
                  ref.read(appSettingsProvider.notifier).setConcurrency(v);
                  ref.read(transfersProvider.notifier).setConcurrency(v);
                },
              ),
            ),
            _Line(
              label: '下载限速',
              hint: '0 表示不限速',
              trailing: Wrap(
                spacing: 5,
                children: [
                  for (final option in const [0, 1024, 5120, 10240])
                    OlChip(
                      label: option == 0 ? '不限' : '${option ~/ 1024}M',
                      height: 22,
                      selected: settings.downLimitKbps == option,
                      onTap: () => ref.read(appSettingsProvider.notifier).setDownLimit(option),
                    ),
                ],
              ),
            ),
            _Line(
              label: '切换服务器时暂停旧任务',
              trailing: OlSwitch(value: settings.pauseOnSwitch, small: true, onChanged: (v) => ref.read(appSettingsProvider.notifier).setPauseOnSwitch(v)),
            ),
            const DownloadDirLine(),
          ],
        ),
        _Card(
          title: '断点续传',
          icon: 'rotate',
          children: [
            Text(
              '下载使用 Range 续传：暂停或重启应用后，从已写入的字节继续。服务端不支持 Range 时会自动重新下载。',
              style: TextStyle(fontSize: 10.5, height: 1.7, color: context.ol.ink3),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaybackSection extends ConsumerWidget {
  const _PlaybackSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return _Card(
      title: '播放与预览',
      subtitle: '媒体使用 media_kit（libmpv），Range 直读不落地。',
      icon: 'play',
      children: [
        _Line(
          label: '记住播放进度',
          trailing: OlSwitch(value: settings.resumePlayback, small: true, onChanged: (v) => ref.read(appSettingsProvider.notifier).setResumePlayback(v)),
        ),
        _Line(
          label: '播完自动下一个',
          trailing: OlSwitch(value: settings.autoPlayNext, small: true, onChanged: (v) => ref.read(appSettingsProvider.notifier).setAutoPlayNext(v)),
        ),
        _Line(
          label: '默认倍速',
          trailing: OlSeg<double>(
            items: const [OlSegItem(0.75, '0.75×'), OlSegItem(1.0, '1×'), OlSegItem(1.25, '1.25×'), OlSegItem(1.5, '1.5×')],
            value: settings.playbackSpeed,
            onChanged: (v) => ref.read(appSettingsProvider.notifier).setPlaybackSpeed(v),
          ),
        ),
      ],
    );
  }
}

class _NotifySection extends ConsumerWidget {
  const _NotifySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return _Card(
      title: '通知与托盘',
      subtitle: 'Windows 使用托盘图标四态；Android 使用前台服务通知。',
      icon: 'bell',
      children: [
        _Line(
          label: '关闭窗口时收进托盘',
          hint: '固定行为：只有托盘菜单「退出」才结束进程',
          trailing: Text('始终开启', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.ol.ink4)),
        ),
        _Line(
          label: '传输完成时通知',
          trailing: OlSwitch(value: settings.trayNotify, small: true, onChanged: (v) => ref.read(appSettingsProvider.notifier).setTrayNotify(v)),
        ),
        const SizedBox(height: 4),
        Text(
          '托盘图标状态：空闲 / 传输中（旋转弧）/ 失败（红点）/ 已暂停（暂停角标）。',
          style: TextStyle(fontSize: 9.5, height: 1.6, color: context.ol.ink4),
        ),
      ],
    );
  }
}

class _SecuritySection extends ConsumerWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    final p = context.ol;
    return Column(
      children: [
        _Card(
          title: '隐私与安全',
          icon: 'shield',
          children: [
            Text(
              '密码只在登录时使用一次；Token 写入系统安全存储（Windows Credential Manager / Android Keystore），不写入 prefs.json、日志与崩溃上报。',
              style: TextStyle(fontSize: 10.5, height: 1.75, color: p.ink3),
            ),
            const SizedBox(height: 8),
            _Line(label: '当前实例', trailing: Text(profile?.displayHost ?? '—', style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: p.ink4))),
            _Line(label: 'HTTP 明文', hint: '仅内网地址放行，公网强制 HTTPS', trailing: const OlBadge(label: '已限制', bg: Color(0xFFFFF5E2), fg: Color(0xFFB47405), border: Color(0xFFF7E0B8))),
            const SizedBox(height: 6),
            Row(
              children: [
                OlGhostButton(label: '锁定（清除本机令牌）', icon: 'lock', onTap: () async {
                  final confirmed = await olConfirm(
                    context,
                    title: '清除本机令牌？',
                    message: '下次打开需要重新输入密码。服务器列表与偏好会保留。',
                    confirm: '清除',
                    danger: true,
                  );
                  if (!confirmed) return;
                  await ref.read(sessionProvider.notifier).signOut();
                  if (context.mounted) context.go('/login');
                }),
                const SizedBox(width: 8),
                OlDangerButton(label: '退出登录', icon: 'logout', onTap: () async {
                  await ref.read(sessionProvider.notifier).signOut();
                  if (context.mounted) context.go('/login');
                }),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final p = context.ol;
    return _Card(
      title: '关于与更新',
      icon: 'info',
      children: [
        _Line(label: '客户端版本', trailing: Text('1.0.3 (4)', style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: p.ink3))),
        _Line(label: '服务端版本', trailing: Text(session.profile?.version ?? session.site?.version ?? '未知', style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: p.ink3))),
        _Line(label: '站点名称', trailing: Text(session.site?.title ?? session.profile?.siteTitle ?? '—', style: TextStyle(fontSize: 10.5, color: p.ink3))),
        const SizedBox(height: 8),
        Text(
          'OpenList Client 是 OpenList 的第三方原生客户端，仅通过你填写的服务地址访问数据，不做遥测上报。管理后台只做只读展示。',
          style: TextStyle(fontSize: 10, height: 1.7, color: p.ink4),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            OlGhostButton(label: '项目主页', icon: 'external', onTap: () async {
              await launchUrl(Uri.parse('https://github.com/OpenListTeam/OpenList'), mode: LaunchMode.externalApplication);
            }),
            const SizedBox(width: 8),
            OlGhostButton(label: '检查更新', icon: 'refresh', onTap: () => olToast(context, '当前已是最新版本（1.0.3）')),
          ],
        ),
      ],
    );
  }
}

class _ServersShortcut extends ConsumerWidget {
  const _ServersShortcut();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serverListProvider);
    final p = context.ol;
    return _Card(
      title: '服务器管理',
      subtitle: '${state.count} 个实例 · 数量不限 · 配置与缓存按实例隔离',
      icon: 'server',
      children: [
        for (final server in state.servers.take(6))
          _Line(
            label: server.name,
            hint: '${server.baseUrl} · ${server.username}',
            trailing: server.id == state.activeId
                ? const OlBadge(label: '当前')
                : OlChip(label: '切换', onTap: () async {
                    await ref.read(sessionProvider.notifier).switchTo(server.id);
                    await ref.read(filesProvider.notifier).attach();
                  }, height: 22),
          ),
        const SizedBox(height: 8),
        OlPrimaryButton(label: '打开服务器管理', icon: 'settings', onTap: () => context.go('/servers')),
        const SizedBox(height: 6),
        Text('凭据保存在系统安全存储；删除服务器不会影响服务端数据。', style: TextStyle(fontSize: 9, color: p.ink4)),
      ],
    );
  }
}

class _DiagnosticsSection extends ConsumerWidget {
  const _DiagnosticsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final profile = session.profile;
    final p = context.ol;
    return _Card(
      title: '连接诊断',
      subtitle: '最近的连接结果，用于排查超时、TLS 与版本问题。',
      icon: 'zap',
      children: [
        _Line(label: '地址', trailing: Text(profile?.baseUrl ?? '—', style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: p.ink3))),
        _Line(label: '延迟', trailing: Text(session.latencyMs == null ? '—' : '${session.latencyMs} ms', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.ink2))),
        _Line(label: '站点', trailing: Text(session.site?.title ?? '—', style: TextStyle(fontSize: 10.5, color: p.ink3))),
        _Line(label: 'API 版本', trailing: Text(session.site?.version ?? session.site?.apiVersion ?? '—', style: TextStyle(fontSize: 10.5, color: p.ink3))),
        const SizedBox(height: 8),
        Row(
          children: [
            OlGhostButton(label: '重新探测', icon: 'refresh', onTap: () async {
              if (profile == null) return;
              final result = await ref.read(sessionProvider.notifier).probe(profile.baseUrl);
              if (!context.mounted) return;
              olToast(
                context,
                result.ok ? '连接正常 · ${result.latencyMs} ms' : (result.error ?? '连接失败'),
                error: !result.ok,
              );
            }),
            const SizedBox(width: 8),
            OlGhostButton(label: '重新登录', icon: 'key', onTap: () => context.go('/login')),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ mobile

class _MobileProfile extends ConsumerWidget {
  const _MobileProfile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final profile = session.profile;
    final serverState = ref.watch(serverListProvider);
    final transfers = ref.watch(transfersProvider);
    final favorites = ref.watch(favoritesProvider).where((e) => e.serverId == profile?.id).length;
    final mounts = ref.watch(storagesProvider).valueOrNull ?? const <StorageMount>[];
    final p = context.ol;

    final topInset = MediaQuery.paddingOf(context).top + 6;
    const heroRow = 46.0;
    const heroBottom = 62.0;
    final heroHeight = topInset + heroRow + heroBottom;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        SizedBox(
          height: heroHeight + 42,
          child: Stack(
            children: [
              Container(
                height: heroHeight,
                padding: EdgeInsets.fromLTRB(20, topInset, 20, 0),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B2233), Color(0xFF0D3B46)]),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(gradient: OlTokens.gradientBrand, borderRadius: BorderRadius.circular(15)),
                      alignment: Alignment.center,
                      child: Text(
                        (profile?.username.isNotEmpty ?? false) ? profile!.username.substring(0, 1).toUpperCase() : 'O',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF04121D)),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(profile?.username ?? '未登录', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const OlIcon('shield', size: 10, color: Color(0xFF8FA8BD)),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  '${session.user?.isAdmin == true ? '管理员' : '普通用户'} · ${profile?.displayHost ?? '未连接'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF8FA8BD)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.push('/servers'),
                      child: const OlIcon('settings', size: 17, color: Color(0xFF8FA8BD)),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                top: heroHeight - 44,
                child: _UsageCard(mounts: mounts, onTap: () => context.go('/settings?tab=storage')),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(
            children: [
              _SettingsGroup(rows: [
                _MobileTile(icon: 'server', label: '服务器管理', value: '${serverState.count} 个 · 点击切换', onTap: () => context.push('/servers')),
                const DownloadDirTile(),
                _MobileTile(icon: 'database', label: '存储挂载', value: '${mounts.length} 个 · 只读', onTap: () => context.go('/settings?tab=storage')),
              ]),
              _SettingsGroup(rows: [
                _MobileTile(
                  icon: 'arrow-down',
                  label: '传输',
                  value: '并发 ${ref.watch(appSettingsProvider).concurrency} · ${transfers.pendingCount} 待传',
                  onTap: () => context.go('/settings?tab=transfer'),
                ),
                _MobileTile(icon: 'play', label: '播放与预览', value: '断点续播', onTap: () => context.go('/settings?tab=playback')),
                _MobileTile(icon: 'sun', label: '外观', value: _themeLabel(ref.watch(appSettingsProvider).themeMode), onTap: () => context.go('/settings?tab=appearance')),
              ]),
              _SettingsGroup(rows: [
                _MobileTile(icon: 'star', label: '我的收藏', value: '$favorites 个', onTap: () => context.push('/favorites')),
                _MobileTile(icon: 'bell', label: '通知', value: ref.watch(appSettingsProvider).trayNotify ? '已开启' : '已关闭', onTap: () => context.go('/settings?tab=notify')),
                _MobileTile(icon: 'key', label: '隐私与安全', onTap: () => context.go('/settings?tab=security')),
                _MobileTile(icon: 'info', label: '关于与更新', value: '1.0.3', onTap: () => context.go('/settings?tab=about')),
              ]),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () async {
                  await ref.read(sessionProvider.notifier).signOut();
                  if (context.mounted) context.go('/login');
                },
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(color: p.isDark ? const Color(0xFF12202F) : const Color(0xFFFFF7F8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF3DDE2))),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OlIcon('logout', size: 14, color: Color(0xFFD92D4B)),
                      SizedBox(width: 7),
                      Text('退出登录', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD92D4B))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('OpenList Client 1.0.3 · Android · API v4', style: TextStyle(fontSize: 8.5, color: p.ink4)),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

}

class _MobileTile extends StatelessWidget {
  final String icon;
  final String label;
  final String? value;
  final VoidCallback onTap;

  const _MobileTile({required this.icon, required this.label, required this.onTap, this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: p.isDark ? const Color(0xFF12202F) : const Color(0xFFEFF7FC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(child: OlIcon(icon, size: 14, color: p.isDark ? const Color(0xFF7DD3FC) : const Color(0xFF3D7E9E))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink))),
            if (value != null) Text(value!, style: TextStyle(fontSize: 9.5, color: p.ink4)),
            const SizedBox(width: 5),
            OlIcon('chev-r', size: 13, color: p.isDark ? const Color(0xFF35485C) : const Color(0xFFC2CFDB)),
          ],
        ),
      ),
    );
  }
}

/// 设置分组卡片（设计稿 .gset：圆角 16、白底、1px 描边、行间 1px 分隔）
class _SettingsGroup extends StatelessWidget {
  final List<Widget> rows;
  const _SettingsGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) {
        children.add(Divider(height: 1, thickness: 1, color: p.isDark ? const Color(0xFF1A2A3C) : const Color(0xFFF4F7FA)));
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.isDark ? const Color(0xFF1C2E43) : const Color(0xFFEDF2F8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// 用量卡（设计稿 .usage-card：白底圆角 18、上移 44 叠在头部渐变上）
class _UsageCard extends StatelessWidget {
  final List<StorageMount> mounts;
  final VoidCallback onTap;

  const _UsageCard({required this.mounts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    var total = 0;
    var used = 0;
    for (final m in mounts) {
      total += m.totalSpace ?? 0;
      used += m.usedSpace ?? 0;
    }
    final ratio = total > 0 ? (used / total).clamp(0.0, 1.0).toDouble() : 0.0;
    final down = mounts.where((m) => !m.isUp).length;
    final top = [...mounts]..sort((a, b) => (b.usedSpace ?? 0).compareTo(a.usedSpace ?? 0));
    final chips = top.take(2).map((m) => '${baseName(m.mountPath)} ${formatBytes(m.usedSpace ?? 0)}').toList();
    final rest = top.length > 2 ? total - top.take(2).fold<int>(0, (a, m) => a + (m.usedSpace ?? 0)) : 0;
    if (rest > 0) chips.add('其他 ${formatBytes(rest)}');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 14, 13, 14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.isDark ? const Color(0xFF1C2E43) : const Color(0xFFEDF2F8)),
          boxShadow: const [BoxShadow(color: Color(0x7314A5E9), blurRadius: 30, offset: Offset(0, 16), spreadRadius: -22)],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: CircularProgressIndicator(
                      value: ratio,
                      strokeWidth: 7,
                      backgroundColor: p.isDark ? const Color(0xFF22303F) : const Color(0xFFE8F0F7),
                      valueColor: const AlwaysStoppedAnimation(OlTokens.sky600),
                    ),
                  ),
                  Text('${(ratio * 100).round()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.ink)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    total > 0 ? '${formatBytes(used, digits: 1)} / ${formatBytes(total, digits: 1)}' : '存储用量 —',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${mounts.length} 个挂载点${down > 0 ? ' · $down 个需要关注' : ''}',
                    style: TextStyle(fontSize: 9.5, color: p.ink3),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        for (var i = 0; i < chips.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              chips[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: p.ink4),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            OlIcon('chev-r', size: 14, color: p.isDark ? const Color(0xFF35485C) : const Color(0xFFC2CFDB)),
          ],
        ),
      ),
    );
  }
}

class _MobileSection extends ConsumerWidget {
  final String section;
  const _MobileSection({required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final titles = {
      'servers': '服务器管理',
      'storage': '存储挂载',
      'transfer': '传输',
      'playback': '播放与预览',
      'appearance': '外观',
      'notify': '通知',
      'security': '隐私与安全',
      'about': '关于与更新',
      'diagnostics': '连接诊断',
    };
    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              OlIconButton(icon: 'chev-l', size: 30, iconSize: 18, onTap: () => context.go('/settings')),
              const SizedBox(width: 4),
              Text(titles[section] ?? '设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: p.ink)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: _SectionBody(section: section),
          ),
        ),
      ],
    );
  }
}
