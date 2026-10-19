import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/file_widgets.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../transfers/transfers_controller.dart';
import 'file_actions.dart';
import 'files_controller.dart';

/// W2（Windows 三栏文件管理）/ W7（深色变体）/ A2（Android 文件 Tab）。
///
/// 四态必须齐全：空目录 / 加载骨架 / 连接失败 / 离线（05 State design）。
class FilesPage extends ConsumerStatefulWidget {
  final String? initialPath;
  const FilesPage({super.key, this.initialPath});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  final _scroll = ScrollController();
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final path = widget.initialPath;
    if (path != null && path.isNotEmpty && path != '/') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(filesProvider.notifier).open(path);
      });
    }
  }

  void _onScroll() {
    final state = ref.read(filesProvider);
    if (!state.hasMore || state.loadingMore || state.loading) return;
    if (_scroll.position.extentAfter < 600) {
      ref.read(filesProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) return _buildMobile(context);
    return _buildDesktop(context);
  }

  // ------------------------------------------------------------------
  // W2 / W7 · Windows 三栏
  // ------------------------------------------------------------------
  Widget _buildDesktop(BuildContext context) {
    final state = ref.watch(filesProvider);
    final body = Row(
      children: [
        const _FilesSidebar(),
        Expanded(
          child: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (detail) async {
              setState(() => _dragging = false);
              if (detail.files.isEmpty) return;
              await uploadPaths(context, ref, detail.files.map((e) => e.path).toList());
            },
            child: Stack(
              children: [
                Column(
                  children: [
                    _BreadcrumbBar(onSearch: () => context.go('/search')),
                    _ListToolbar(onUpload: () => pickAndUpload(context, ref)),
                    Expanded(child: _buildBody(state)),
                    _DropHint(active: _dragging),
                    const _StatusBar(),
                  ],
                ),
                if (_dragging) const _DropOverlay(),
              ],
            ),
          ),
        ),
        SizedBox(width: 250, child: _DetailPanel()),
      ],
    );

    return AppFrame(
      navIndex: 0,
      child: _FilesShortcuts(
        onUpload: () => pickAndUpload(context, ref),
        onNewFolder: () => createFolder(context, ref),
        onRefresh: () => ref.read(filesProvider.notifier).refresh(),
        onSelectAll: () => ref.read(filesProvider.notifier).selectAll(),
        onClearSelection: () => ref.read(filesProvider.notifier).clearSelection(),
        onPreview: () {
          final items = ref.read(filesProvider).selectedItems;
          if (items.length == 1) previewItem(context, ref, items.first);
        },
        onRename: () {
          final items = ref.read(filesProvider).selectedItems;
          if (items.length == 1) renameItem(context, ref, items.first);
        },
        onDelete: () {
          final items = ref.read(filesProvider).selectedItems;
          if (items.isNotEmpty) deleteItems(context, ref, items);
        },
        onSearch: () => context.go('/search'),
        child: body,
      ),
    );
  }

  Widget _buildBody(FilesState state) {
    if (state.items.isEmpty && state.loading) return const _LoadingBody();
    if (state.items.isEmpty && state.error != null && !state.offline) return _ErrorBody(message: state.error!);
    if (state.items.isEmpty && !state.loading) return const _EmptyBody();
    return state.grid ? _GridView(state: state, scroll: _scroll) : _ListView(state: state, scroll: _scroll);
  }

  // ------------------------------------------------------------------
  // A2 · Android
  // ------------------------------------------------------------------
  Widget _buildMobile(BuildContext context) {
    final state = ref.watch(filesProvider);
    final p = context.ol;
    return AppFrame(
      navIndex: 0,
      child: Stack(
        children: [
          RefreshIndicator(
            color: OlTokens.sky600,
            onRefresh: () => ref.read(filesProvider.notifier).refresh(),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _MobileHeader(state: state)),
                const SliverToBoxAdapter(child: _MobileMounts()),
                const SliverToBoxAdapter(child: _MobileKindFilter()),
                SliverToBoxAdapter(child: _MobileBreadcrumb(state: state)),
                if (state.items.isEmpty && state.loading)
                  const SliverToBoxAdapter(child: _LoadingBody())
                else if (state.items.isEmpty && state.error != null && !state.offline)
                  SliverToBoxAdapter(child: _ErrorBody(message: state.error!))
                else if (state.items.isEmpty && !state.loading)
                  const SliverToBoxAdapter(child: _EmptyBody())
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= state.items.length) return null;
                        return _MobileRow(
                          item: state.items[index],
                          selected: state.selected.contains(state.items[index].name),
                          onTap: () => _openMobile(state.items[index]),
                          onLongPress: () async {
                            final box = context.findRenderObject() as RenderBox?;
                            final pos = box == null ? Offset.zero : box.localToGlobal(Offset.zero);
                            await showItemMenu(context, ref, state.items[index], pos);
                          },
                        );
                      },
                      childCount: state.items.length,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
          Positioned(
            right: OlGap.pageMobile,
            bottom: 78,
            child: _MobileFab(
              onNewFolder: () => createFolder(context, ref),
              onUpload: () => pickAndUpload(context, ref),
              onOffline: () => offlineDownload(context, ref),
            ),
          ),
          if (state.error != null && state.offline)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _OfflineBanner(message: state.error!, color: p.card),
            ),
        ],
      ),
    );
  }

  Future<void> _openMobile(FileItem item) async {
    if (item.isDir) {
      ref.read(filesProvider.notifier).open(joinPath(ref.read(filesProvider).path, item.name));
    } else {
      await openItem(context, ref, item);
    }
  }
}

// ---------------------------------------------------------------------------
// 快捷键（05 · Windows 快捷键）
// ---------------------------------------------------------------------------
class _UploadIntent extends Intent {
  const _UploadIntent();
}
class _NewFolderIntent extends Intent {
  const _NewFolderIntent();
}
class _RefreshIntent extends Intent {
  const _RefreshIntent();
}
class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}
class _PreviewIntent extends Intent {
  const _PreviewIntent();
}
class _RenameIntent extends Intent {
  const _RenameIntent();
}
class _DeleteIntent extends Intent {
  const _DeleteIntent();
}
class _SearchIntent extends Intent {
  const _SearchIntent();
}
class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

class _FilesShortcuts extends StatelessWidget {
  final VoidCallback onUpload;
  final VoidCallback onNewFolder;
  final VoidCallback onRefresh;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onPreview;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onSearch;
  final Widget child;

  const _FilesShortcuts({
    required this.onUpload,
    required this.onNewFolder,
    required this.onRefresh,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onPreview,
    required this.onRename,
    required this.onDelete,
    required this.onSearch,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyU, control: true): const _UploadIntent(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): const _NewFolderIntent(),
        const SingleActivator(LogicalKeyboardKey.f5): const _RefreshIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): const _SelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.space): const _PreviewIntent(),
        const SingleActivator(LogicalKeyboardKey.f2): const _RenameIntent(),
        const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): const _SearchIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const _EscapeIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UploadIntent: CallbackAction<_UploadIntent>(onInvoke: (_) => onUpload()),
          _NewFolderIntent: CallbackAction<_NewFolderIntent>(onInvoke: (_) => onNewFolder()),
          _RefreshIntent: CallbackAction<_RefreshIntent>(onInvoke: (_) => onRefresh()),
          _SelectAllIntent: CallbackAction<_SelectAllIntent>(onInvoke: (_) => onSelectAll()),
          _PreviewIntent: CallbackAction<_PreviewIntent>(onInvoke: (_) => onPreview()),
          _RenameIntent: CallbackAction<_RenameIntent>(onInvoke: (_) => onRename()),
          _DeleteIntent: CallbackAction<_DeleteIntent>(onInvoke: (_) => onDelete()),
          _SearchIntent: CallbackAction<_SearchIntent>(onInvoke: (_) => onSearch()),
          _EscapeIntent: CallbackAction<_EscapeIntent>(onInvoke: (_) => onClearSelection()),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 左侧栏（W2）
// ---------------------------------------------------------------------------
class _FilesSidebar extends ConsumerWidget {
  const _FilesSidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final files = ref.watch(filesProvider);
    final transfers = ref.watch(transfersProvider);
    final storages = ref.watch(storagesProvider).valueOrNull ?? const <StorageMount>[];
    final favorites = ref.watch(favoritesProvider);
    final session = ref.watch(sessionProvider);
    final serverId = session.profile?.id;

    return Container(
      width: 204,
      color: p.surface,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: p.line2))),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(9, 10, 9, 0),
              children: [
                const OlSectionLabel('工作区'),
                _NavRow(icon: 'folder', label: '所有文件', badge: files.total, active: true, route: '/files'),
                _NavRow(icon: 'clock', label: '最近使用', route: '/favorites?tab=recent'),
                _NavRow(icon: 'star', label: '收藏', badge: favorites.forServer(serverId).length, route: '/favorites'),
                _NavRow(icon: 'share', label: '我的分享', badge: 0, route: '/favorites?tab=star'),
                _NavRow(icon: 'arrow-down', label: '传输任务', badge: transfers.pendingCount, route: '/transfers'),
                const OlSectionLabel('挂载点'),
                if (storages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    child: Text('暂无挂载点', style: TextStyle(fontSize: 10.5, color: p.ink4)),
                  ),
                for (final m in storages) _MountTile(mount: m),
              ],
            ),
          ),
          _UsageCard(storages: storages),
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
  final String route;

  const _NavRow({required this.icon, required this.label, required this.route, this.badge = 0, this.active = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final showBadge = badge > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: GestureDetector(
        onTap: () => context.go(route),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w650, color: active ? p.navOn : p.nav),
                  ),
                ),
                if (showBadge)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: active ? p.card : p.navBadgeBg,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      badge > 999 ? '999+' : '$badge',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: p.ink3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MountTile extends StatelessWidget {
  final StorageMount mount;
  const _MountTile({required this.mount});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final up = mount.isUp;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onTap: () => context.go('/files?path=${Uri.encodeComponent(mount.mountPath)}'),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: up ? OlTokens.sky600 : const Color(0xFF9AABBC),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mount.driver.isEmpty ? mount.mountPath : mount.driver,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w650, color: p.ink2),
                  ),
                ),
                Text(
                  mount.totalSpace == null ? (up ? '正常' : '离线') : formatBytes(mount.totalSpace),
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  final List<StorageMount> storages;
  const _UsageCard({required this.storages});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    var total = 0;
    var used = 0;
    for (final m in storages) {
      total += m.totalSpace ?? 0;
      used += m.usedSpace ?? 0;
    }
    final ratio = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0).toDouble();
    final bad = storages.where((e) => !e.isUp).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(9, 8, 9, 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        gradient: OlTokens.deepPanel,
        borderRadius: BorderRadius.circular(OlTokens.r3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('存储用量', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9DB4C8))),
              ),
              Text('${(ratio * 100).round()}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${formatBytes(used)} / ${formatBytes(total)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Colors.white),
          ),
          const SizedBox(height: 8),
          OlUsageBar(value: ratio, dark: true),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${storages.length} 个挂载点', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
              Text(
                bad == 0 ? '全部正常' : '$bad 个异常',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: bad == 0 ? const Color(0xFF5EEAD4) : const Color(0xFFFB923C)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 面包屑 + 搜索 + 上传（W2 顶栏）
// ---------------------------------------------------------------------------
class _BreadcrumbBar extends ConsumerWidget {
  final VoidCallback onSearch;
  const _BreadcrumbBar({required this.onSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final segs = segmentsOf(state.path);
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
      child: Row(
        children: [
          OlIconButton(
            icon: 'chev-l',
            tooltip: '返回上级',
            squared: true,
            onTap: state.path == '/' ? null : () => ref.read(filesProvider.notifier).goUp(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: GestureDetector(
                    onTap: () => ref.read(filesProvider.notifier).open('/'),
                    child: Text(
                      '全部文件',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: segs.isEmpty ? p.ink : p.ink3,
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < segs.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: OlIcon('chev-r', size: 12, color: const Color(0xFFC2CFDB)),
                  ),
                  Flexible(
                    child: GestureDetector(
                      onTap: () => ref.read(filesProvider.notifier).open('/${segs.take(i + 1).join('/')}'),
                      child: Text(
                        segs[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: i == segs.length - 1 ? 14 : 13,
                          fontWeight: i == segs.length - 1 ? FontWeight.w800 : FontWeight.w650,
                          color: i == segs.length - 1 ? p.ink : p.ink3,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SearchMini(onTap: onSearch),
          const SizedBox(width: 6),
          OlIconButton(icon: 'refresh', tooltip: '刷新 F5', squared: true, onTap: () => ref.read(filesProvider.notifier).refresh()),
        ],
      ),
    );
  }
}

class _SearchMini extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchMini({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 186,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: p.isDark ? const Color(0xFF101F31) : const Color(0xFFF4F8FC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.isDark ? const Color(0xFF1C2E43) : const Color(0xFFE9F0F7)),
          ),
          child: Row(
            children: [
              OlIcon('search', size: 14, color: p.ink4),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '搜索当前目录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w550, color: p.ink4),
                ),
              ),
              const OlKbd('Ctrl K'),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 工具条：数量 / 视图切换 / 上传
// ---------------------------------------------------------------------------
class _ListToolbar extends ConsumerWidget {
  final VoidCallback onUpload;
  const _ListToolbar({required this.onUpload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final selected = state.selected.length;
    final text = selected == 0
        ? '${state.items.length} 个项目'
        : '${state.items.length} 个项目 · 已选 $selected 项';

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
      child: Row(
        children: [
          if (selected > 0) ...[
            OlIconButton(icon: 'x', tooltip: '取消选择 Esc', onTap: () => ref.read(filesProvider.notifier).clearSelection()),
            const SizedBox(width: 4),
            OlGhostButton(label: '下载', icon: 'download', height: 28, onTap: () async {
              for (final item in state.selectedItems) {
                await downloadItem(context, ref, item);
              }
            }),
            const SizedBox(width: 6),
            OlGhostButton(label: '删除', icon: 'trash', height: 28, onTap: () => deleteItems(context, ref, state.selectedItems)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink4),
            ),
          ),
          OlSeg<bool>(
            items: const [
              OlSegItem(false, '列表', icon: 'list'),
              OlSegItem(true, '网格', icon: 'grid'),
            ],
            value: state.grid,
            onChanged: (v) {
              if (v != state.grid) ref.read(filesProvider.notifier).toggleGrid();
            },
          ),
          const SizedBox(width: 8),
          OlPrimaryButton(label: '上传', icon: 'upload', height: 30, onTap: onUpload),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 列表视图（行高 44）
// ---------------------------------------------------------------------------
class _ListView extends ConsumerWidget {
  final FilesState state;
  final ScrollController scroll;

  const _ListView({required this.state, required this.scroll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return Column(
      children: [
        Container(
          height: 28,
          color: p.tableHeadBg,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const SizedBox(width: 22),
              Expanded(
                flex: 5,
                child: _SortHeader(label: '名称', field: 'name', state: state),
              ),
              Expanded(
                flex: 2,
                child: _SortHeader(label: '大小', field: 'size', state: state),
              ),
              Expanded(
                flex: 3,
                child: _SortHeader(label: '修改时间', field: 'modified', state: state),
              ),
              const SizedBox(width: 34),
            ],
          ),
        ),
        if (state.error != null && state.offline) _OfflineBanner(message: state.error!, color: p.card),
        Expanded(
          child: Scrollbar(
            controller: scroll,
            thumbVisibility: true,
            child: ListView.builder(
              controller: scroll,
              itemCount: state.items.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= state.items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }
                final item = state.items[index];
                return _FileRow(
                  item: item,
                  selected: state.selected.contains(item.name),
                  onTap: () => ref.read(filesProvider.notifier).toggleSelect(item.name),
                  onDoubleTap: () async {
                    if (item.isDir) {
                      ref.read(filesProvider.notifier).open(joinPath(state.path, item.name));
                    } else {
                      await openItem(context, ref, item);
                    }
                  },
                  onSecondaryTap: (pos) => showItemMenu(context, ref, item, pos),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SortHeader extends ConsumerWidget {
  final String label;
  final String field;
  final FilesState state;

  const _SortHeader({required this.label, required this.field, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final active = state.orderBy == field;
    return GestureDetector(
      onTap: () => ref.read(filesProvider.notifier).setSort(field),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          children: [
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: active ? OlTokens.sky600 : p.th,
                ),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 3),
              OlIcon(state.desc ? 'chev-d' : 'chev-u', size: 11, color: OlTokens.sky600),
            ],
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  final FileItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onSecondaryTap;

  const _FileRow({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTap,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final item = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapDown: (d) => widget.onSecondaryTap(d.globalPosition),
        child: Container(
          height: OlGap.rowDesktop,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.selected ? p.rowSel : (_hover ? p.rowHover : null),
            border: Border(bottom: BorderSide(color: p.divider)),
          ),
          child: Row(
            children: [
              OlCheckbox(value: widget.selected, onChanged: (_) => widget.onTap()),
              const SizedBox(width: 9),
              FileGlyph(item: item, size: 29, radius: 8, iconSize: 15),
              const SizedBox(width: 9),
              Expanded(
                flex: 5,
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  item.isDir ? '—' : formatBytes(item.size),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w550, color: p.ink3),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  formatDate(item.modified),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w550, color: p.ink3),
                ),
              ),
              SizedBox(
                width: 34,
                child: _hover || widget.selected
                    ? OlIconButton(
                        icon: 'more',
                        size: 24,
                        iconSize: 14,
                        onTap: () async {
                          final box = context.findRenderObject() as RenderBox?;
                          final pos = box == null ? Offset.zero : box.localToGlobal(const Offset(20, 40));
                          await widget.onSecondaryTap(pos);
                        },
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 网格视图
// ---------------------------------------------------------------------------
class _GridView extends ConsumerWidget {
  final FilesState state;
  final ScrollController scroll;

  const _GridView({required this.state, required this.scroll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return Scrollbar(
      controller: scroll,
      thumbVisibility: true,
      child: GridView.builder(
        controller: scroll,
        padding: const EdgeInsets.all(14),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          mainAxisExtent: 132,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: state.items.length,
        itemBuilder: (context, index) {
          final item = state.items[index];
          return _GridTile(
            item: item,
            selected: state.selected.contains(item.name),
            onTap: () => ref.read(filesProvider.notifier).toggleSelect(item.name),
            onDoubleTap: () async {
              if (item.isDir) {
                ref.read(filesProvider.notifier).open(joinPath(state.path, item.name));
              } else {
                await openItem(context, ref, item);
              }
            },
            onSecondaryTap: (pos) => showItemMenu(context, ref, item, pos),
            borderColor: p.line,
          );
        },
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  final FileItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onSecondaryTap;
  final Color borderColor;

  const _GridTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTap,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: (d) => onSecondaryTap(d.globalPosition),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? p.rowSel : p.card,
          borderRadius: BorderRadius.circular(OlTokens.r3),
          border: Border.all(color: selected ? OlTokens.sky600 : borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: FileGlyph(item: item, size: 52, radius: 12, iconSize: 24)),
            const SizedBox(height: 9),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 1.35, fontWeight: FontWeight.w700, color: p.ink),
            ),
            const Spacer(),
            Text(
              item.isDir ? '文件夹' : formatBytes(item.size),
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 四态：空 / 骨架 / 错误 / 离线
// ---------------------------------------------------------------------------
class _EmptyBody extends ConsumerWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(filesProvider);
    return OlEmptyState(
      icon: 'folder',
      title: '这个目录是空的',
      subtitle: state.canWrite ? '把文件拖进来，或者上传第一批文件。' : '当前目录没有可显示的内容。',
      action: state.canWrite
          ? OlPrimaryButton(label: '上传文件', icon: 'upload', height: 32, onTap: () => pickAndUpload(context, ref))
          : null,
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (context, index) {
        return Container(
          height: OlGap.rowDesktop,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
          child: Row(
            children: [
              const OlSkeleton(height: 29, width: 29, radius: 8),
              const SizedBox(width: 9),
              Expanded(flex: 5, child: OlSkeleton(height: 10, width: 140 + (index % 3) * 40.0)),
              Expanded(flex: 2, child: OlSkeleton(height: 9, width: 48)),
              Expanded(flex: 3, child: OlSkeleton(height: 9, width: 72)),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorBody extends ConsumerWidget {
  final String message;
  const _ErrorBody({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(child: OlIcon('alert', size: 22, color: Color(0xFFD92D4B))),
          ),
          const SizedBox(height: 14),
          Text('无法加载该目录', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
          const SizedBox(height: 6),
          SizedBox(
            width: 320,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, height: 1.6, color: p.ink3),
            ),
          ),
          const SizedBox(height: 14),
          OlPrimaryButton(
            label: '重试',
            icon: 'refresh',
            height: 32,
            onTap: () => ref.read(filesProvider.notifier).refresh(),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final String message;
  final Color color;
  const _OfflineBanner({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        border: Border(bottom: BorderSide(color: const Color(0xFFF59E0B).withAlpha(60))),
      ),
      child: Row(
        children: [
          const OlIcon('wifi', size: 14, color: Color(0xFFB47405)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '离线：正在显示已缓存内容 · $message',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFB47405)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 拖拽提示 + 状态栏
// ---------------------------------------------------------------------------
class _DropHint extends ConsumerWidget {
  final bool active;
  const _DropHint({required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final folder = baseName(state.path);
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEAF8FE) : p.surfaceAlt,
        border: Border(top: BorderSide(color: p.line2)),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OlIcon('upload', size: 13, color: active ? OlTokens.sky600 : const Color(0xFFB4C3D1)),
            const SizedBox(width: 7),
            Text(
              '将文件拖到这里，上传到「$folder」',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFF0A93C4) : const Color(0xFFB4C3D1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0x0F38BDF8),
            borderRadius: BorderRadius.circular(OlTokens.r3),
            border: Border.all(color: OlTokens.sky600, width: 1.5),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OlIcon('upload', size: 30, color: Color(0xFF0EA5E9)),
                SizedBox(height: 10),
                Text('松开即可上传', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0A93C4))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    final transfers = ref.watch(transfersProvider);
    final speed = transfers.downSpeed;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(top: BorderSide(color: p.line2)),
      ),
      child: Row(
        children: [
          const OlDot(color: OlTokens.ok, size: 5),
          const SizedBox(width: 5),
          Text(
            session.signedIn
                ? '已连接${session.latencyMs == null ? '' : ' · 延迟 ${session.latencyMs} ms'}'
                : '未连接',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4),
          ),
          const SizedBox(width: 14),
          if (speed > 0) ...[
            Text(
              '${session.profile?.name ?? '服务器'} · 读取 ${formatSpeed(speed)}',
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4),
            ),
            const SizedBox(width: 14),
          ],
          const Spacer(),
          Text(
            session.site?.version == null ? 'API v4' : 'v${session.site!.version}',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 详情面板（W2 右侧 250px）
// ---------------------------------------------------------------------------
class _DetailPanel extends ConsumerWidget {
  const _DetailPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final items = state.selectedItems;
    final item = items.length == 1 ? items.first : null;

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(left: BorderSide(color: p.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '详情',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: p.th),
                  ),
                ),
                if (item != null)
                  OlIconButton(icon: 'x', size: 22, iconSize: 12, onTap: () => ref.read(filesProvider.notifier).clearSelection()),
              ],
            ),
          ),
          if (item == null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    items.isEmpty ? '选中一个项目查看详情' : '已选中 ${items.length} 个项目',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, height: 1.6, color: p.ink4),
                  ),
                ),
              ),
            )
          else
            Expanded(child: _DetailBody(item: item, dir: state.path)),
        ],
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final FileItem item;
  final String dir;
  const _DetailBody({required this.item, required this.dir});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final kind = kindOf(item.name, item.isDir);
    final fullPath = joinPath(dir, item.name);
    final favorites = ref.watch(favoritesProvider);
    final serverId = ref.read(sessionProvider).profile?.id;
    final isFav = favorites.isFavorite(serverId, fullPath);
    final siblings = ref.read(filesProvider.notifier).siblingsOf(item.name);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        OlMediaThumb(
          height: 112,
          title: item.name,
          subtitle: item.isDir ? '文件夹' : (extensionOf(item.name).toUpperCase().isEmpty ? '文件' : extensionOf(item.name).toUpperCase()),
          tag: kind == FileKind.video ? '4K HDR' : null,
          imageUrl: item.thumb,
        ),
        const SizedBox(height: 10),
        Text(item.name, style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w800, color: p.ink)),
        const SizedBox(height: 3),
        Text(
          item.isDir ? '文件夹' : '${formatBytes(item.size)} · ${extensionOf(item.name).toUpperCase()}',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: p.ink4),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _DetailAction(icon: 'play', label: '播放', onTap: () => openItem(context, ref, item))),
            const SizedBox(width: 6),
            Expanded(child: _DetailAction(icon: 'download', label: '下载', onTap: () => downloadItem(context, ref, item))),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _DetailAction(icon: 'share', label: '分享', onTap: () => shareItem(context, ref, item))),
            const SizedBox(width: 6),
            Expanded(
              child: _DetailAction(
                icon: isFav ? 'star' : 'star',
                label: '收藏',
                active: isFav,
                onTap: () => ref.read(favoritesProvider.notifier).toggle(serverId ?? '', item, dir),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: p.isDark ? const Color(0xFF101F31) : const Color(0xFFF7FAFD),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line2),
          ),
          child: Column(
            children: [
              _MetaRow('位置', dir),
              _MetaRow('存储', item.provider ?? '—'),
              _MetaRow('修改时间', formatDateTime(item.modified)),
              _MetaRow('哈希', item.hashInfo ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '同目录',
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: p.th),
        ),
        const SizedBox(height: 5),
        for (final s in siblings)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                FileGlyph(item: s, size: 22, radius: 6, iconSize: 11),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2),
                  ),
                ),
                Text(
                  s.isDir ? '—' : formatBytes(s.size),
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: p.ink4),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DetailAction extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _DetailAction({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final fg = active ? OlTokens.sky600 : const Color(0xFF3E5268);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 28,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: p.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OlIcon(icon, size: 12, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: p.ink4)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.ink2)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A2 · Android 头部 / 挂载卡片 / 筛选 / 面包屑 / 行 / FAB
// ---------------------------------------------------------------------------
class _MobileHeader extends ConsumerWidget {
  final FilesState state;
  const _MobileHeader({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 12, OlGap.pageMobile, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.profile?.displayHost ?? '未连接',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink4),
                ),
              ),
              OlIconButton(icon: 'refresh', size: 30, onTap: () => ref.read(filesProvider.notifier).refresh()),
              const SizedBox(width: 4),
              OlIconButton(icon: 'search', size: 30, onTap: () => context.go('/search')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('所有文件', style: OlText.title.copyWith(color: p.ink)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: p.chipBg, borderRadius: BorderRadius.circular(OlTokens.rPill)),
                child: Text(
                  '${state.total} 项',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: p.ink3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('最近修改', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.ink4)),
        ],
      ),
    );
  }
}

class _MobileMounts extends ConsumerWidget {
  const _MobileMounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storages = ref.watch(storagesProvider).valueOrNull ?? const <StorageMount>[];
    if (storages.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 74,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: storages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _MountCard(mount: storages[index]),
      ),
    );
  }
}

class _MountCard extends ConsumerWidget {
  final StorageMount mount;
  const _MountCard({required this.mount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final ratio = mount.usageRatio ?? 0;
    return GestureDetector(
      onTap: () => context.go('/files?path=${Uri.encodeComponent(mount.mountPath)}'),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(OlTokens.r3),
          border: Border.all(color: p.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: mount.isUp ? OlTokens.sky600 : const Color(0xFF9AABBC),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    mount.driver.isEmpty ? mount.mountPath : mount.driver,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              formatBytes(mount.totalSpace),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: p.ink),
            ),
            const SizedBox(height: 5),
            OlUsageBar(value: ratio),
            const SizedBox(height: 4),
            Text(
              mount.usageRatio == null ? (mount.isUp ? '正常' : '离线') : '已用 ${formatBytes(mount.usedSpace)} · ${(ratio * 100).round()}%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: p.ink4),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileKindFilter extends ConsumerStatefulWidget {
  const _MobileKindFilter();

  @override
  ConsumerState<_MobileKindFilter> createState() => _MobileKindFilterState();
}

class _MobileKindFilterState extends ConsumerState<_MobileKindFilter> {
  String _kind = 'all';

  static const kinds = <String, String>{
    'all': '全部',
    'video': '视频',
    'image': '图片',
    'text': '文档',
  };

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(filesProvider).items.where((e) {
      if (_kind == 'all') return true;
      return kindOf(e.name, e.isDir) == _kindOf(_kind);
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 4, OlGap.pageMobile, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final entry in kinds.entries)
                OlChip(
                  label: entry.value,
                  selected: _kind == entry.key,
                  onTap: () => setState(() => _kind = entry.key),
                ),
            ],
          ),
          if (_kind != 'all')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '筛选出 ${items.length} 项 · 点击可打开',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.ol.ink4),
              ),
            ),
        ],
      ),
    );
  }

  FileKind _kindOf(String key) {
    switch (key) {
      case 'video':
        return FileKind.video;
      case 'image':
        return FileKind.image;
      case 'text':
        return FileKind.text;
      default:
        return FileKind.other;
    }
  }
}

class _MobileBreadcrumb extends ConsumerWidget {
  final FilesState state;
  const _MobileBreadcrumb({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final segs = segmentsOf(state.path);
    return Padding(
      padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 6, OlGap.pageMobile, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => ref.read(filesProvider.notifier).open('/'),
                child: Text('全部文件', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0A93C4))),
              ),
              for (var i = 0; i < segs.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OlIcon('chev-r', size: 11, color: p.ink4),
                ),
                Flexible(
                  child: GestureDetector(
                    onTap: () => ref.read(filesProvider.notifier).open('/${segs.take(i + 1).join('/')}'),
                    child: Text(
                      segs[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink2),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Text('/', style: TextStyle(fontSize: 12, color: p.ink4)),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${state.folderCount} 个文件夹 · ${state.fileCount} 个文件',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink4),
          ),
        ],
      ),
    );
  }
}

class _MobileRow extends StatelessWidget {
  final FileItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MobileRow({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Material(
      color: selected ? p.rowSel : p.card,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: OlGap.rowMobile,
          padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
          child: Row(
            children: [
              FileGlyph(item: item, size: 36, radius: 10, iconSize: 17),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.isDir
                          ? '文件夹'
                          : '${formatBytes(item.size)} · ${formatDate(item.modified)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w550, color: p.ink4),
                    ),
                  ],
                ),
              ),
              OlIcon('more-v', size: 16, color: p.ink4),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileFab extends StatefulWidget {
  final VoidCallback onNewFolder;
  final VoidCallback onUpload;
  final VoidCallback onOffline;

  const _MobileFab({required this.onNewFolder, required this.onUpload, required this.onOffline});

  @override
  State<_MobileFab> createState() => _MobileFabState();
}

class _MobileFabState extends State<_MobileFab> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) ...[
          _FabItem(label: '新建文件夹', icon: 'folder-plus', onTap: widget.onNewFolder, card: p.card, line: p.line, ink: p.ink2),
          const SizedBox(height: 8),
          _FabItem(label: '上传文件', icon: 'upload', onTap: widget.onUpload, card: p.card, line: p.line, ink: p.ink2),
          const SizedBox(height: 8),
          _FabItem(label: '离线下载', icon: 'cloud-dl', onTap: widget.onOffline, card: p.card, line: p.line, ink: p.ink2),
          const SizedBox(height: 10),
        ],
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: OlTokens.gradientPrimary,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Color(0x6638BDF8), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: Center(
              child: OlIcon(_open ? 'x' : 'plus', size: 24, color: Colors.white, strokeWidth: 2.2),
            ),
          ),
        ),
      ],
    );
  }
}

class _FabItem extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;
  final Color card;
  final Color line;
  final Color ink;

  const _FabItem({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.card,
    required this.line,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(OlTokens.rPill),
          border: Border.all(color: line),
          boxShadow: const [BoxShadow(color: Color(0x1A0D1B2A), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OlIcon(icon, size: 15, color: const Color(0xFF0EA5E9)),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ink)),
          ],
        ),
      ),
    );
  }
}
