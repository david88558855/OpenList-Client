import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'file_actions.dart';
import 'files_controller.dart';

/// W2（Windows 三栏文件管理）/ W7（深色变体）/ A2（Android 文件列表）。
///
/// 三栏：挂载点导航 204 → 列表（面包屑 50 / 工具条 48 / 表头 28 / 行 44 /
/// 拖拽提示 / 状态栏 30）→ 详情面板 250。
/// 四态齐全：空目录 / 加载骨架 / 连接失败 / 离线。
class FilesPage extends ConsumerStatefulWidget {
  final String? initialPath;
  const FilesPage({super.key, this.initialPath});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  final _scroll = ScrollController();
  bool _dragging = false;
  FileKind? _kind;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _openInitial();
  }

  @override
  void didUpdateWidget(covariant FilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 侧栏挂载点走 /files?path=…，同一路由重建时 State 不会重建。
    if (widget.initialPath != oldWidget.initialPath) _openInitial();
  }

  void _openInitial() {
    final path = widget.initialPath;
    if (path == null || path.isEmpty || path == '/') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(filesProvider.notifier).open(path);
    });
  }

  void _onScroll() {
    final state = ref.read(filesProvider);
    if (!state.hasMore || state.loadingMore || state.loading) return;
    if (_scroll.position.extentAfter < 600) ref.read(filesProvider.notifier).loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  List<FileItem> _filtered(List<FileItem> items) {
    final kind = _kind;
    if (kind == null) return items;
    return items.where((e) => kindOf(e.name, e.isDir) == kind).toList();
  }

  void _openItem(FileItem item) {
    if (item.isDir) {
      ref.read(filesProvider.notifier).open(joinPath(ref.read(filesProvider).path, item.name));
    } else {
      openItem(context, ref, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) return _buildMobile(context);
    return _buildDesktop(context);
  }

  // ------------------------------------------------------------------ W2 桌面
  Widget _buildDesktop(BuildContext context) {
    final state = ref.watch(filesProvider);
    return AppFrame(
      navIndex: 0,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => context.go('/search'),
          const SingleActivator(LogicalKeyboardKey.f5): () => ref.read(filesProvider.notifier).refresh(),
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => ref.read(filesProvider.notifier).selectAll(),
          const SingleActivator(LogicalKeyboardKey.escape): () => ref.read(filesProvider.notifier).clearSelection(),
          const SingleActivator(LogicalKeyboardKey.delete): () {
            final selected = ref.read(filesProvider).selectedItems;
            if (selected.isNotEmpty) deleteItems(context, ref, selected);
          },
        },
        child: Focus(
          autofocus: true,
          child: Row(
            children: [
              const _Sidebar(),
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
                          const _TopBar(),
                          _Toolbar(
                            kind: _kind,
                            onKind: (k) => setState(() => _kind = k),
                          ),
                          Expanded(child: _buildBody(state)),
                          const _DropHint(),
                          const _StatusBar(),
                        ],
                      ),
                      if (_dragging) const _DropOverlay(),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 250, child: _DetailPanel()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(FilesState state) {
    final items = _filtered(state.items);
    if (items.isEmpty && state.loading) return const _SkeletonBody();
    if (items.isEmpty && state.error != null && !state.offline) {
      return _ErrorBody(
        message: state.error!,
        onRetry: () => ref.read(filesProvider.notifier).refresh(),
      );
    }
    if (items.isEmpty) return _EmptyBody(filtered: _kind != null);
    return state.grid
        ? _GridView(items: items, scroll: _scroll, onOpen: _openItem)
        : _ListView(items: items, scroll: _scroll, onOpen: _openItem);
  }

  // ---------------------------------------------------------------- A2 移动端
  Widget _buildMobile(BuildContext context) {
    final state = ref.watch(filesProvider);
    final items = _filtered(state.items);
    return AppFrame(
      navIndex: 0,
      child: Stack(
        children: [
          RefreshIndicator(
            color: OlTokens.sky600,
            onRefresh: () => ref.read(filesProvider.notifier).refresh(),
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _MobileHead()),
                const SliverToBoxAdapter(child: _MobileMounts()),
                SliverToBoxAdapter(
                  child: _KindFilter(value: _kind, onChanged: (k) => setState(() => _kind = k)),
                ),
                SliverToBoxAdapter(child: _MobileCrumb(state: state)),
                if (items.isEmpty && state.loading)
                  const SliverToBoxAdapter(child: SizedBox(height: 420, child: _SkeletonBody()))
                else if (items.isEmpty && state.error != null && !state.offline)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 300,
                      child: _ErrorBody(
                        message: state.error!,
                        onRetry: () => ref.read(filesProvider.notifier).refresh(),
                      ),
                    ),
                  )
                else if (items.isEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(height: 300, child: _EmptyBody(filtered: _kind != null)),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = items[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
                          child: _MobileRow(
                            item: item,
                            onTap: () => _openItem(item),
                            onLongPress: () async {
                              final box = context.findRenderObject() as RenderBox?;
                              final pos = box == null ? Offset.zero : box.localToGlobal(Offset.zero);
                              await showItemMenu(context, ref, item, pos);
                            },
                          ),
                        );
                      },
                      childCount: items.length,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 112)),
              ],
            ),
          ),
          Positioned(
            right: 18,
            bottom: 86,
            child: _Fab(
              onUpload: () => pickAndUpload(context, ref),
              onNewFolder: () => createFolder(context, ref),
              onOffline: () => offlineDownload(context, ref),
            ),
          ),
          if (state.offline)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                color: const Color(0xFFFFF6E5),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                child: const Row(
                  children: [
                    OlIcon('alert', size: 12, color: Color(0xFFB47405)),
                    SizedBox(width: 6),
                    Text('离线模式 · 显示本地缓存', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF5E4A22))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 左侧导航（W2 · dside 204）
// ---------------------------------------------------------------------------
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final files = ref.watch(filesProvider);
    final transfers = ref.watch(transfersProvider);
    final favorites = ref.watch(favoritesProvider);
    final storages = ref.watch(storagesProvider).valueOrNull ?? const <StorageMount>[];
    final serverId = ref.watch(sessionProvider).profile?.id;

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
                const _NavRow(icon: 'folder', label: '所有文件', badge: 0, active: true),
                _NavRow(icon: 'clock', label: '最近使用', onTap: () => context.go('/favorites?tab=recent')),
                _NavRow(
                  icon: 'star',
                  label: '收藏',
                  badge: favorites.where((e) => e.serverId == serverId).length,
                  onTap: () => context.go('/favorites'),
                ),
                _NavRow(icon: 'share', label: '我的分享', onTap: () => context.go('/favorites?tab=share')),
                _NavRow(
                  icon: 'arrow-down',
                  label: '传输任务',
                  badge: transfers.pendingCount,
                  onTap: () => context.go('/transfers'),
                ),
                const OlSectionLabel('挂载点'),
                if (storages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    child: Text('暂无挂载点', style: TextStyle(fontSize: 10.5, color: p.ink4)),
                  ),
                for (final mount in storages) _MountRow(mount: mount),
              ],
            ),
          ),
          _UsageCard(storages: storages, total: files.total),
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
  final VoidCallback? onTap;

  const _NavRow({required this.icon, required this.label, this.badge = 0, this.active = false, this.onTap});

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
                    child: Text(
                      badge > 999 ? '999+' : '$badge',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: active ? const Color(0xFF0B7A9E) : p.ink4),
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

class _MountRow extends StatelessWidget {
  final StorageMount mount;
  const _MountRow({required this.mount});

  static const _dotColors = [
    Color(0xFF38BDF8),
    Color(0xFF7C5CFC),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFF94A3B8),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final up = mount.isUp;
    final dot = _dotColors[mount.id.abs() % _dotColors.length];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go('/files?path=${Uri.encodeComponent(mount.mountPath)}'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 30,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: up ? dot : const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2.5)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mount.mountPath == '/' ? '根目录' : mount.mountPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink2),
                ),
              ),
              Text(
                up ? formatBytes(mount.totalSpace) : '离线',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  final List<StorageMount> storages;
  final int total;
  const _UsageCard({required this.storages, required this.total});

  @override
  Widget build(BuildContext context) {
    var spaceTotal = 0;
    var spaceUsed = 0;
    for (final s in storages) {
      spaceTotal += s.totalSpace ?? 0;
      spaceUsed += s.usedSpace ?? 0;
    }
    final ratio = spaceTotal <= 0 ? 0.0 : (spaceUsed / spaceTotal).clamp(0.0, 1.0);
    final down = storages.where((e) => !e.isUp).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(9, 8, 9, 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        gradient: OlTokens.deepPanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('存储用量', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9DB4C8))),
              const Spacer(),
              Text(
                total > 0 ? '$total 个文件' : '—',
                style: const TextStyle(fontSize: 9, color: Color(0xFF9DB4C8)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(ratio * 100).round()}',
                style: const TextStyle(fontSize: 22, height: 1, letterSpacing: -0.6, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 2, left: 2),
                child: Text('%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF8FA8BD))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OlUsageBar(value: ratio, dark: true, height: 4),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${storages.length} 个挂载点', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
              const Spacer(),
              Text(down == 0 ? '全部正常' : '$down 个异常', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 面包屑 / 工具条 / 状态栏
// ---------------------------------------------------------------------------
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final segs = state.path.split('/').where((e) => e.isNotEmpty).toList();
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
      child: Row(
        children: [
          _RoundBtn(
            icon: 'chev-l',
            tooltip: '返回上级',
            onTap: state.path == '/' ? null : () => ref.read(filesProvider.notifier).goUp(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                _Crumb(text: '全部文件', current: segs.isEmpty, onTap: () => ref.read(filesProvider.notifier).open('/')),
                for (var i = 0; i < segs.length; i++) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: OlIcon('chev-r', size: 12, color: Color(0xFFC2CFDB)),
                  ),
                  Flexible(
                    child: _Crumb(
                      text: segs[i],
                      current: i == segs.length - 1,
                      onTap: () => ref.read(filesProvider.notifier).open('/${segs.take(i + 1).join('/')}'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _SearchMini(onTap: () => context.go('/search')),
          const SizedBox(width: 6),
          OlIconButton(
            icon: 'refresh',
            tooltip: '刷新 F5',
            squared: true,
            onTap: () => ref.read(filesProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
          OlPrimaryButton(label: '上传', icon: 'upload', height: 30, onTap: () => pickAndUpload(context, ref)),
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  final String text;
  final bool current;
  final VoidCallback onTap;
  const _Crumb({required this.text, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: current ? 14 : 13,
              fontWeight: current ? FontWeight.w800 : FontWeight.w600,
              color: current ? p.ink : p.ink3,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final String icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _RoundBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: p.fieldBg, borderRadius: BorderRadius.circular(6)),
            child: Center(child: OlIcon(icon, size: 13, color: onTap == null ? p.ink4 : p.ink3)),
          ),
        ),
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 186,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: p.fieldBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.line2),
          ),
          child: Row(
            children: [
              OlIcon('search', size: 13, color: p.ink4),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '搜索当前目录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: p.ink4),
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

class _Toolbar extends ConsumerWidget {
  final FileKind? kind;
  final ValueChanged<FileKind?> onKind;
  const _Toolbar({required this.kind, required this.onKind});

  Future<void> _sortMenu(BuildContext context, WidgetRef ref, Offset pos) async {
    final state = ref.read(filesProvider);
    final notifier = ref.read(filesProvider.notifier);
    await showOlMenu(
      context,
      position: pos,
      items: [
        OlMenuItem('按名称', 'sort', () => notifier.setSort('name')),
        OlMenuItem('按大小', 'sort', () => notifier.setSort('size')),
        OlMenuItem('按修改时间', 'clock', () => notifier.setSort('modified')),
        OlMenuItem(state.desc ? '改为升序' : '改为降序', 'arrow-up', () {
          notifier.setSort(state.orderBy, desc: !state.desc);
        }),
      ],
    );
  }

  Future<void> _filterMenu(BuildContext context, Offset pos) async {
    await showOlMenu(
      context,
      position: pos,
      items: [
        OlMenuItem('全部类型', 'filter', () => onKind(null)),
        OlMenuItem('仅文件夹', 'folder', () => onKind(FileKind.folder)),
        OlMenuItem('仅视频', 'film', () => onKind(FileKind.video)),
        OlMenuItem('仅图片', 'image', () => onKind(FileKind.image)),
        OlMenuItem('仅文档', 'file-text', () => onKind(FileKind.text)),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final selected = state.selected.length;
    final allSelected = state.items.isNotEmpty && selected == state.items.length;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
      child: Row(
        children: [
          OlCheckbox(
            value: allSelected,
            onChanged: (_) {
              final notifier = ref.read(filesProvider.notifier);
              if (allSelected) {
                notifier.clearSelection();
              } else {
                notifier.selectAll();
              }
            },
          ),
          const SizedBox(width: 9),
          Text(
            selected == 0 ? '${state.items.length} 个项目' : '${state.items.length} 个项目 · 已选 $selected 项',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink4),
          ),
          const Spacer(),
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
          Builder(
            builder: (btnContext) => OlIconButton(
              icon: 'sort',
              tooltip: '排序',
              onTap: () {
                final box = btnContext.findRenderObject() as RenderBox?;
                final pos = box == null ? Offset.zero : box.localToGlobal(const Offset(0, 28));
                _sortMenu(context, ref, pos);
              },
            ),
          ),
          Builder(
            builder: (btnContext) => OlIconButton(
              icon: 'filter',
              tooltip: kind == null ? '筛选类型' : '已筛选类型',
              color: kind == null ? null : OlTokens.sky700,
              onTap: () {
                final box = btnContext.findRenderObject() as RenderBox?;
                final pos = box == null ? Offset.zero : box.localToGlobal(const Offset(0, 28));
                _filterMenu(context, pos);
              },
            ),
          ),
          OlIconButton(icon: 'folder-plus', tooltip: '新建文件夹', onTap: () => createFolder(context, ref)),
        ],
      ),
    );
  }
}

class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return SizedBox(
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OlIcon('upload', size: 13, color: p.ink4),
          const SizedBox(width: 6),
          Text('将文件拖到这里上传到当前目录', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4)),
        ],
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
    final files = ref.watch(filesProvider);
    final latency = session.latencyMs;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(top: BorderSide(color: p.line2)),
      ),
      child: Row(
        children: [
          OlDot(color: session.signedIn ? OlTokens.ok : OlTokens.warn, size: 5),
          const SizedBox(width: 6),
          Text(
            session.signedIn ? '已连接${latency == null ? '' : ' · 延迟 $latency ms'}' : '未连接',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: p.ink3),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              files.provider ?? session.profile?.displayHost ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: p.ink3),
            ),
          ),
          const Spacer(),
          if (files.offline)
            Text('离线 · 缓存目录', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: OlTokens.warn)),
          const SizedBox(width: 12),
          Text(
            session.profile?.version ?? session.site?.version ?? '',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: p.ink3),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 列表 / 网格
// ---------------------------------------------------------------------------
class _ListView extends ConsumerWidget {
  final List<FileItem> items;
  final ScrollController scroll;
  final ValueChanged<FileItem> onOpen;

  const _ListView({required this.items, required this.scroll, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    return Column(
      children: [
        Container(
          height: 28,
          color: p.tableHeadBg,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const SizedBox(width: 30),
              Expanded(
                flex: 5,
                child: Text('名称', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.th)),
              ),
              SizedBox(
                width: 74,
                child: Text('大小', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.th)),
              ),
              SizedBox(
                width: 108,
                child: Text('修改时间', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.th)),
              ),
              const SizedBox(width: 34),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _FileRow(
                item: item,
                selected: state.selected.contains(item.name),
                onTap: () => ref.read(filesProvider.notifier).toggleSelect(item.name),
                onDoubleTap: () => onOpen(item),
                onMenu: (pos) => showItemMenu(context, ref, item, pos, selection: state.selectedItems),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatefulWidget {
  final FileItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onMenu;

  const _FileRow({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onMenu,
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
        onSecondaryTapDown: (d) => widget.onMenu(d.globalPosition),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.selected ? p.rowSel : (_hover ? p.rowHover : null),
            border: Border(bottom: BorderSide(color: p.divider)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: OlCheckbox(value: widget.selected, onChanged: (_) => widget.onTap()),
              ),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    FileGlyph(item: item, size: 29, radius: 8, iconSize: 15),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 74,
                child: Text(item.isDir ? '—' : formatBytes(item.size), style: TextStyle(fontSize: 11.5, color: p.ink3)),
              ),
              SizedBox(
                width: 108,
                child: Text(formatDate(item.modified), style: TextStyle(fontSize: 11.5, color: p.ink3)),
              ),
              SizedBox(
                width: 34,
                child: (_hover || widget.selected)
                    ? OlIconButton(
                        icon: 'more',
                        size: 24,
                        iconSize: 13,
                        onTap: () {
                          final box = context.findRenderObject() as RenderBox?;
                          final pos = box == null ? Offset.zero : box.localToGlobal(const Offset(20, 30));
                          widget.onMenu(pos);
                        },
                      )
                    : OlIcon('more', size: 13, color: p.ink4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridView extends ConsumerWidget {
  final List<FileItem> items;
  final ScrollController scroll;
  final ValueChanged<FileItem> onOpen;

  const _GridView({required this.items, required this.scroll, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    return GridView.builder(
      controller: scroll,
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.92,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = state.selected.contains(item.name);
        return GestureDetector(
          onTap: () => ref.read(filesProvider.notifier).toggleSelect(item.name),
          onDoubleTap: () => onOpen(item),
          onSecondaryTapDown: (d) => showItemMenu(context, ref, item, d.globalPosition, selection: state.selectedItems),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected ? p.rowSel : p.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? OlTokens.sky.withAlpha(90) : p.line2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FileGlyph(item: item, size: 38, radius: 10, iconSize: 18),
                const Spacer(),
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, height: 1.35, fontWeight: FontWeight.w700, color: p.ink),
                ),
                const SizedBox(height: 3),
                Text(item.isDir ? '文件夹' : formatBytes(item.size), style: TextStyle(fontSize: 9.5, color: p.ink4)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 四态
// ---------------------------------------------------------------------------
class _SkeletonBody extends StatelessWidget {
  const _SkeletonBody();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: 10,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: const [
            OlSkeleton(width: 29, height: 29, radius: 8),
            SizedBox(width: 10),
            Expanded(child: OlSkeleton(height: 11)),
            SizedBox(width: 40),
            OlSkeleton(width: 70, height: 10),
            SizedBox(width: 14),
            OlSkeleton(width: 80, height: 10),
          ],
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  final bool filtered;
  const _EmptyBody({this.filtered = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OlEmptyState(
        icon: filtered ? 'filter' : 'folder',
        title: filtered ? '没有匹配的文件' : '这个目录还是空的',
        subtitle: filtered ? '切换筛选条件，或搜索全部挂载点' : '把文件拖进来，或点右上角「上传」',
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OlEmptyState(
        icon: 'alert',
        title: '无法读取这个目录',
        subtitle: message,
        action: OlGhostButton(label: '重试', icon: 'refresh', onTap: onRetry),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Positioned.fill(
      child: Container(
        color: OlTokens.sky.withAlpha(18),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OlTokens.sky.withAlpha(120)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const OlIcon('upload', size: 18, color: Color(0xFF0EA5E9)),
              const SizedBox(width: 10),
              Text('松手即可上传到当前目录', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 右侧详情面板（W2 · ddetail 250）
// ---------------------------------------------------------------------------
class _DetailPanel extends ConsumerWidget {
  const _DetailPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(filesProvider);
    final selected = state.selectedItems;
    final item = selected.length == 1 ? selected.first : null;

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(left: BorderSide(color: p.line2)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text('详情', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.ink4)),
                  const Spacer(),
                  if (item != null)
                    OlIconButton(
                      icon: 'x',
                      size: 22,
                      iconSize: 13,
                      onTap: () => ref.read(filesProvider.notifier).clearSelection(),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: item == null
                ? _DetailHint(count: selected.length)
                : _DetailBody(item: item, dir: state.path),
          ),
        ],
      ),
    );
  }
}

class _DetailHint extends StatelessWidget {
  final int count;
  const _DetailHint({required this.count});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final multi = count > 1;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OlIcon(multi ? 'layers' : 'panel', size: 26, color: p.ink4),
            const SizedBox(height: 10),
            Text(
              multi ? '已选择 $count 个项目' : '选中文件查看详情',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink3),
            ),
            const SizedBox(height: 4),
            Text(
              multi ? '可批量下载、移动或删除' : '缩略图、属性与同目录文件',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, height: 1.6, color: p.ink4),
            ),
          ],
        ),
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
    final path = joinPath(dir, item.name);
    final profile = ref.watch(sessionProvider).profile;
    final favorites = ref.watch(favoritesProvider);
    final isFav = favorites.any((e) => e.serverId == profile?.id && e.path == path);
    final siblings = ref.read(filesProvider.notifier).siblingsOf(item.name);
    final playable = kind == FileKind.video || kind == FileKind.audio;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      children: [
        OlMediaThumb(
          height: 112,
          title: item.name,
          subtitle: item.isDir ? '文件夹' : extensionOf(item.name).toUpperCase(),
          tag: kind == FileKind.video ? '4K HDR' : null,
        ),
        const SizedBox(height: 10),
        Text(item.name, style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w800, color: p.ink)),
        const SizedBox(height: 3),
        Text(
          item.isDir ? '文件夹' : '${formatBytes(item.size)} · ${extensionOf(item.name).toUpperCase()}',
          style: TextStyle(fontSize: 10, color: p.ink4),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OlPrimaryButton(
                label: item.isDir ? '打开' : (playable ? '播放' : '预览'),
                icon: item.isDir ? 'folder' : (playable ? 'play' : 'eye'),
                height: 28,
                fontSize: 10.5,
                onTap: () => openItem(context, ref, item),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OlGhostButton(
                label: '下载',
                icon: 'download',
                height: 28,
                fontSize: 10.5,
                onTap: item.isDir ? null : () => downloadItem(context, ref, item),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OlGhostButton(
                label: '分享',
                icon: 'share',
                height: 28,
                fontSize: 10.5,
                onTap: () => shareItem(context, ref, item),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OlGhostButton(
                label: isFav ? '已收藏' : '收藏',
                icon: 'star',
                height: 28,
                fontSize: 10.5,
                onTap: () async {
                  if (profile == null) return;
                  await ref.read(favoritesProvider.notifier).toggle(profile.id, item, dir);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line2),
          ),
          child: Column(
            children: [
              _Kv(label: '位置', value: dir),
              _Kv(label: '存储', value: item.provider ?? profile?.displayHost ?? '—'),
              _Kv(label: '修改时间', value: formatDateTime(item.modified)),
              if (item.hashInfo != null && item.hashInfo!.isNotEmpty) _Kv(label: '哈希', value: item.hashInfo!),
            ],
          ),
        ),
        if (siblings.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('同目录', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.ink4)),
          const SizedBox(height: 4),
          for (final s in siblings.take(4))
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _openSibling(context, ref, s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      FileGlyph(item: s, size: 22, radius: 6, iconSize: 11),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: p.ink2),
                        ),
                      ),
                      Text(s.isDir ? '—' : formatBytes(s.size), style: TextStyle(fontSize: 9, color: p.ink4)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _openSibling(BuildContext context, WidgetRef ref, FileItem sibling) async {
    if (sibling.isDir) {
      await ref.read(filesProvider.notifier).open(joinPath(dir, sibling.name));
    } else {
      await openItem(context, ref, sibling);
    }
  }
}

class _Kv extends StatelessWidget {
  final String label;
  final String value;
  const _Kv({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: p.ink3)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A2 · 移动端零件
// ---------------------------------------------------------------------------
class _MobileHead extends ConsumerWidget {
  const _MobileHead();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final profile = ref.watch(sessionProvider).profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 10, OlGap.pageMobile, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const OlDot(color: OlTokens.ok, size: 6),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.go('/servers'),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile?.displayHost ?? '未连接',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.ink2),
                        ),
                      ),
                      const SizedBox(width: 3),
                      OlIcon('chev-r', size: 10, color: p.ink4),
                    ],
                  ),
                ),
              ),
              _CircleBtn(icon: 'search', onTap: () => context.go('/search')),
              const SizedBox(width: 8),
              _CircleBtn(icon: 'more-v', onTap: () => context.go('/settings')),
            ],
          ),
          const SizedBox(height: 10),
          Text('所有文件', style: TextStyle(fontSize: 23, letterSpacing: -0.8, fontWeight: FontWeight.w800, color: p.ink)),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle, border: Border.all(color: p.line2)),
        child: Center(child: OlIcon(icon, size: 14, color: p.ink2)),
      ),
    );
  }
}

class _MobileMounts extends ConsumerWidget {
  const _MobileMounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final storages = ref.watch(storagesProvider).valueOrNull ?? const <StorageMount>[];
    if (storages.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 8, OlGap.pageMobile, 8),
        itemCount: storages.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mount = storages[index];
          final ratio = mount.usageRatio ?? 0;
          return GestureDetector(
            onTap: () => context.go('/files?path=${Uri.encodeComponent(mount.mountPath)}'),
            child: Container(
              width: 148,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.line2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OlIcon('hard-drive', size: 12, color: mount.isUp ? OlTokens.sky700 : p.ink4),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          mount.mountPath == '/' ? '根目录' : mount.mountPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.ink),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  OlUsageBar(value: ratio, height: 3),
                  const SizedBox(height: 5),
                  Text(
                    mount.isUp ? '${formatBytes(mount.usedSpace)} / ${formatBytes(mount.totalSpace)}' : '离线',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 8.5, color: p.ink4),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KindFilter extends StatelessWidget {
  final FileKind? value;
  final ValueChanged<FileKind?> onChanged;
  const _KindFilter({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 4, OlGap.pageMobile, 4),
      child: Row(
        children: [
          OlChip(label: '全部', selected: value == null, onTap: () => onChanged(null)),
          const SizedBox(width: 7),
          OlChip(label: '视频', selected: value == FileKind.video, onTap: () => onChanged(FileKind.video)),
          const SizedBox(width: 7),
          OlChip(label: '图片', selected: value == FileKind.image, onTap: () => onChanged(FileKind.image)),
          const SizedBox(width: 7),
          OlChip(label: '文档', selected: value == FileKind.text, onTap: () => onChanged(FileKind.text)),
        ],
      ),
    );
  }
}

class _MobileCrumb extends ConsumerWidget {
  final FilesState state;
  const _MobileCrumb({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final segs = state.path.split('/').where((e) => e.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 2, OlGap.pageMobile, 6),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => ref.read(filesProvider.notifier).open('/'),
              child: Text(
                segs.isEmpty ? '全部文件' : '/${segs.join('/')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink2),
              ),
            ),
          ),
          Text('${state.items.length} 个项目', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.ink4)),
        ],
      ),
    );
  }
}

class _MobileRow extends StatelessWidget {
  final FileItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _MobileRow({required this.item, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 58,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
        child: Row(
          children: [
            FileGlyph(item: item, size: 34, radius: 9, iconSize: 17),
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
                    item.isDir ? '文件夹' : '${formatBytes(item.size)} · ${formatDate(item.modified)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: p.ink4),
                  ),
                ],
              ),
            ),
            OlIcon('chev-r', size: 14, color: p.ink4),
          ],
        ),
      ),
    );
  }
}

class _Fab extends StatefulWidget {
  final VoidCallback onUpload;
  final VoidCallback onNewFolder;
  final VoidCallback onOffline;
  const _Fab({required this.onUpload, required this.onNewFolder, required this.onOffline});

  @override
  State<_Fab> createState() => _FabState();
}

class _FabState extends State<_Fab> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) ...[
          _FabAction(icon: 'folder-plus', label: '新建文件夹', onTap: widget.onNewFolder),
          const SizedBox(height: 8),
          _FabAction(icon: 'cloud-dl', label: '离线下载', onTap: widget.onOffline),
          const SizedBox(height: 8),
          _FabAction(icon: 'upload', label: '上传文件', onTap: widget.onUpload),
          const SizedBox(height: 10),
        ],
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: OlTokens.gradientBrand,
              borderRadius: BorderRadius.circular(19),
              boxShadow: const [BoxShadow(color: Color(0x6638BDF8), blurRadius: 22, offset: Offset(0, 12))],
            ),
            child: Center(
              child: AnimatedRotation(
                turns: _open ? 0.125 : 0,
                duration: const Duration(milliseconds: 180),
                child: const OlIcon('plus', size: 22, color: Colors.white, strokeWidth: 2.2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FabAction extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _FabAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.line2),
          boxShadow: const [BoxShadow(color: Color(0x140D1B2A), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OlIcon(icon, size: 13, color: OlTokens.sky700),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.ink2)),
          ],
        ),
      ),
    );
  }
}
