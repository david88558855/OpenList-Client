import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/file_widgets.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';

/// 收藏 / 最近使用。
///
/// v1.0.14：「我的分享」已拆成独立页面 `/shares`，这里只保留收藏与最近使用。
/// 左侧工作区导航 204 + 列表（Windows 行高 56 / Android 58）。
class FavoritesPage extends ConsumerStatefulWidget {
  final String initialTab;
  const FavoritesPage({super.key, this.initialTab = 'star'});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  late String _tab = _normalize(widget.initialTab);

  static String _normalize(String tab) {
    if (tab == 'recent') return tab;
    return 'star';
  }

  @override
  void didUpdateWidget(covariant FavoritesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      setState(() => _tab = _normalize(widget.initialTab));
    }
  }

  void _select(String tab) {
    setState(() => _tab = tab);
    context.go('/favorites?tab=$tab');
  }

  @override
  Widget build(BuildContext context) {
    return AppFrame(
      navIndex: 2,
      handleBack: true,
      child: context.isNarrow
          ? _MobileBody(tab: _tab, onTab: _select)
          : Row(
              children: [
                _Sidebar(tab: _tab, onTab: _select),
                Expanded(child: _DesktopBody(tab: _tab, onTab: _select)),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// 左侧工作区导航
// ---------------------------------------------------------------------------
class _Sidebar extends ConsumerWidget {
  final String tab;
  final ValueChanged<String> onTab;
  const _Sidebar({required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final profile = ref.watch(sessionProvider).profile;
    final entries = ref.watch(favoritesProvider).where((e) => e.serverId == profile?.id).length;
    final recent = profile == null ? 0 : ref.read(serverStoreProvider).readRecent(profile.id).length;
    final shares = ref.watch(sharesProvider).valueOrNull?.length ?? 0;

    return Container(
      width: 204,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.line2)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 0),
              children: [
                const OlSectionLabel('工作区'),
                _NavRow(icon: 'folder', label: '所有文件', onTap: () => context.go('/files')),
                _NavRow(icon: 'star', label: '收藏', badge: entries, active: tab == 'star', onTap: () => onTab('star')),
                _NavRow(icon: 'clock', label: '最近使用', badge: recent, active: tab == 'recent', onTap: () => onTab('recent')),
                _NavRow(icon: 'share', label: '我的分享', badge: shares, onTap: () => context.go('/shares')),
                _NavRow(icon: 'arrow-down', label: '传输任务', onTap: () => context.go('/transfers')),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  child: Divider(height: 1),
                ),
                _NavRow(icon: 'settings', label: '设置', onTap: () => context.go('/settings')),
                const OlSectionLabel('存储'),
                if (profile != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    child: Row(
                      children: [
                        const OlDot(color: OlTokens.ok, size: 6),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            profile.displayHost,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Text('收藏与最近使用只存在本机，不写入服务端。', style: TextStyle(fontSize: 8.5, height: 1.6, color: p.ink4)),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String icon;
  final String label;
  final int badge;
  final bool active;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.label, required this.onTap, this.badge = 0, this.active = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 31,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: active ? p.navOnBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                OlIcon(icon, size: 15, color: active ? OlTokens.sky600 : p.navIcon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? p.navOn : p.nav),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: active ? p.card : p.navBadgeBg,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('$badge', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: p.ink4)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 主区（Windows / Android）
// ---------------------------------------------------------------------------
class _DesktopBody extends StatelessWidget {
  final String tab;
  final ValueChanged<String> onTab;
  const _DesktopBody({required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final title = tab == 'recent' ? '最近使用' : '收藏';
    return ColoredBox(
      color: p.card,
      child: Column(
        children: [
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
            child: Row(
              children: [
                OlIconButton(icon: 'chev-l', size: 30, iconSize: 17, tooltip: '返回', onTap: () => goBackOrFiles(context)),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 18, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: p.ink)),
                const SizedBox(width: 14),
                OlSeg<String>(
                  items: const [
                    OlSegItem('star', '收藏', icon: 'star'),
                    OlSegItem('recent', '最近', icon: 'clock'),
                  ],
                  value: tab,
                  onChanged: onTab,
                ),
                const Spacer(),
                OlGhostButton(label: '刷新', icon: 'refresh', height: 30, onTap: () => context.go('/favorites?tab=$tab')),
              ],
            ),
          ),
          Expanded(child: _Body(tab: tab)),
        ],
      ),
    );
  }
}

class _MobileBody extends StatelessWidget {
  final String tab;
  final ValueChanged<String> onTab;
  const _MobileBody({required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return ColoredBox(
      color: p.card,
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                OlIconButton(icon: 'chev-l', size: 34, iconSize: 18, onTap: () => goBackOrFiles(context)),
                const SizedBox(width: 2),
                Text(
                  tab == 'recent' ? '最近使用' : '收藏',
                  style: TextStyle(fontSize: 17, letterSpacing: -0.4, fontWeight: FontWeight.w800, color: p.ink),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
            child: Row(
              children: [
                OlChip(label: '收藏', selected: tab == 'star', onTap: () => onTab('star')),
                const SizedBox(width: 7),
                OlChip(label: '最近', selected: tab == 'recent', onTap: () => onTab('recent')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _Body(tab: tab)),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String tab;
  const _Body({required this.tab});

  @override
  Widget build(BuildContext context) {
    if (tab == 'recent') return const _RecentList();
    return const _FavoriteList();
  }
}

// ---------------------------------------------------------------------------
// 收藏
// ---------------------------------------------------------------------------
class _FavoriteList extends ConsumerWidget {
  const _FavoriteList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    final entries = ref.watch(favoritesProvider).where((e) => e.serverId == profile?.id).toList();
    if (entries.isEmpty) {
      return const OlEmptyState(
        icon: 'star',
        title: '还没有收藏',
        subtitle: '在文件上右键或长按，选「收藏」即可固定到这里',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      itemCount: entries.length,
      separatorBuilder: (context, index) => Divider(height: 1, color: context.ol.divider),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _EntryRow(
          leading: FileGlyph(name: entry.name, isDir: entry.isDir, size: 32, radius: 9, iconSize: 16),
          name: entry.name,
          subtitle: entry.path,
          trailing: entry.isDir ? '文件夹' : formatBytes(entry.size),
          onOpen: () async {
            if (entry.isDir) {
              await ref.read(filesProvider.notifier).open(entry.path);
              if (context.mounted) context.go('/files?path=${Uri.encodeComponent(entry.path)}');
            } else {
              context.go('/files?path=${Uri.encodeComponent(parentOf(entry.path))}');
            }
          },
          onRemove: () async {
            await ref.read(favoritesProvider.notifier).removeEntry(entry);
            if (context.mounted) olToast(context, '已取消收藏');
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 最近使用
// ---------------------------------------------------------------------------
class _RecentList extends ConsumerWidget {
  const _RecentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    if (profile == null) {
      return const OlEmptyState(icon: 'clock', title: '尚未连接服务器', subtitle: '登录后这里会记录最近访问的目录');
    }
    final raw = ref.read(serverStoreProvider).readRecent(profile.id);
    if (raw.isEmpty) {
      return const OlEmptyState(icon: 'clock', title: '还没有访问记录', subtitle: '浏览过的目录会按时间列在这里');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      itemCount: raw.length,
      separatorBuilder: (context, index) => Divider(height: 1, color: context.ol.divider),
      itemBuilder: (context, index) {
        final item = raw[index];
        final path = (item['path'] ?? '/').toString();
        final at = DateTime.tryParse((item['at'] ?? '').toString());
        return _EntryRow(
          leading: FileGlyph(name: baseName(path), isDir: true, size: 32, radius: 9, iconSize: 16),
          name: path == '/' ? '全部文件' : baseName(path),
          subtitle: path,
          trailing: relativeTime(at),
          onOpen: () async {
            await ref.read(filesProvider.notifier).open(path);
            if (context.mounted) context.go('/files?path=${Uri.encodeComponent(path)}');
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 我的分享（只读 + 浏览器打开）
// ---------------------------------------------------------------------------

/// 分享行使用图标底（非文件图标）。

// ---------------------------------------------------------------------------
// 通用行
// ---------------------------------------------------------------------------
class _EntryRow extends StatefulWidget {
  final Widget leading;
  final String name;
  final String subtitle;
  final String trailing;
  final VoidCallback onOpen;
  final Future<void> Function()? onRemove;

  const _EntryRow({
    required this.leading,
    required this.name,
    required this.subtitle,
    required this.trailing,
    required this.onOpen,
    this.onRemove,
  });

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onOpen,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          color: _hover ? p.rowHover : null,
          child: Row(
            children: [
              widget.leading,
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9.5, color: p.ink4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(widget.trailing, style: TextStyle(fontSize: 9.5, color: p.ink4)),
              if (widget.onRemove != null) ...[
                const SizedBox(width: 8),
                OlIconButton(
                  icon: 'trash',
                  size: 26,
                  iconSize: 13,
                  tooltip: '移除收藏',
                  onTap: () => widget.onRemove!(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
