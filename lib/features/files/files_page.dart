import 'dart:io';

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

class FilesPage extends ConsumerStatefulWidget {
  final String? initialPath;
  const FilesPage({super.key, this.initialPath});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  final _scroll = ScrollController();
  bool _dragging = false;
  FileKind? _filter;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = widget.initialPath;
      if (initial != null && initial.isNotEmpty && initial != ref.read(filesProvider).path) {
        ref.read(filesProvider.notifier).open(initial);
      }
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      ref.read(filesProvider.notifier).loadMore();
    }
  }

  List<FileItem> _visible(List<FileItem> items) {
    if (_filter == null) return items;
    return items.where((e) => kindOf(e.name, e.isDir) == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final body = narrow ? _buildMobile(context) : _buildDesktop(context);
    return AppFrame(navIndex: 0, child: body);
  }

  // ------------------------------------------------------------- desktop

  Widget _buildDesktop(BuildContext context) {
    final files = ref.watch(filesProvider);
    final visible = _visible(files.items);
    final selectedItems = files.selectedItems;

    Widget content = Row(
      children: [
        const _FilesSidebar(),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: context.ol.card,
              border: Border(left: BorderSide(color: context.ol.line2)),
            ),
            child: Column(
              children: [
                _DesktopTopBar(onUpload: () => pickAndUpload(context, ref)),
                _Toolbar(
                  visible: visible,
                  filter: _filter,
                  onFilter: (value) => setState(() => _filter = value),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildListArea(context, files, visible)),
                      if (selectedItems.length == 1)
                        _DetailPanel(
                          item: selectedItems.first,
                          onClose: () => ref.read(filesProvider.notifier).clearSelection(),
                        ),
                    ],
                  ),
                ),
                const _StatusBar(),
              ],
            ),
          ),
        ),
      ],
    );

    if (_dragging) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: const Color(0x33277DDE),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(color: context.ol.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: OlTokens.sky)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const OlIcon('upload', size: 18, color: OlTokens.sky600),
                      const SizedBox(width: 8),
                      Text('松开即可上传到「${files.path == '/' ? '根目录' : baseName(files.path)}」', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.ol.ink)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final keyboardScoped = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => ref.read(filesProvider.notifier).selectAll(),
        const SingleActivator(LogicalKeyboardKey.f5): () => ref.read(filesProvider.notifier).refresh(),
        const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => pickAndUpload(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => context.push('/search'),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): () => createFolder(context, ref),
        const SingleActivator(LogicalKeyboardKey.f2): () {
          final selection = ref.read(filesProvider).selectedItems;
          if (selection.length == 1) renameItem(context, ref, selection.first);
        },
        const SingleActivator(LogicalKeyboardKey.delete): () {
          final selection = ref.read(filesProvider).selectedItems;
          if (selection.isNotEmpty) deleteItems(context, ref, selection);
        },
        const SingleActivator(LogicalKeyboardKey.space): () {
          final selection = ref.read(filesProvider).selectedItems;
          if (selection.length == 1) previewItem(context, ref, selection.first);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () => ref.read(filesProvider.notifier).clearSelection(),
      },
      child: Focus(autofocus: true, child: content),
    );

    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return keyboardScoped;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        final paths = detail.files.map((e) => e.path).where((e) => e.isNotEmpty).toList();
        if (paths.isNotEmpty) await uploadPaths(context, ref, paths);
      },
      child: keyboardScoped,
    );
  }

  Widget _buildListArea(BuildContext context, FilesState files, List<FileItem> visible) {
    if (files.showSkeleton) return _SkeletonTable(grid: files.grid);
    if (files.loading && files.items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        if (files.error != null) _ErrorBanner(message: files.error!, offline: files.offline),
        if (files.offline) const _OfflineBanner(),
        Expanded(
          child: files.items.isEmpty
              ? OlEmptyState(
                  icon: 'folder',
                  title: '这个目录还是空的',
                  subtitle: '把文件拖进来，或点击右上角「上传」把本地文件放到这里。',
                  action: OlPrimaryButton(label: '上传文件', icon: 'upload', onTap: () => pickAndUpload(context, ref)),
                )
              : visible.isEmpty
                  ? OlEmptyState(
                      icon: 'filter',
                      title: '没有符合筛选的文件',
                      subtitle: '当前筛选为「${_filterLabel(_filter)}」，切换筛选或清除条件查看全部内容。',
                      action: OlGhostButton(label: '清除筛选', onTap: () => setState(() => _filter = null)),
                    )
                  : files.grid
                      ? _GridBody(items: visible, files: files)
                      : _TableBody(items: visible, files: files, controller: _scroll),
        ),
        if (!files.grid && files.items.isNotEmpty)
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            child: Text(
              files.hasMore ? '已加载 ${files.items.length} / ${files.total} 项 · 继续滚动加载' : '已全部加载 · ${files.total} 项',
              style: TextStyle(fontSize: 9.5, color: context.ol.ink4),
            ),
          ),
      ],
    );
  }

  Widget _buildMobile(BuildContext context) {
    final files = ref.watch(filesProvider);
    final visible = _visible(files.items);
    final p = context.ol;

    return Column(
      children: [
        _MobileHeader(path: files.path),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  files.path == '/' ? '所有文件' : baseName(files.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: p.ink),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('${files.total} 项', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4)),
              ),
              const Spacer(),
              _SortChip(),
            ],
          ),
        ),
        const _MobileStorageRow(),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
            children: [
              OlChip(label: '全部', selected: _filter == null, onTap: () => setState(() => _filter = null)),
              const SizedBox(width: 6),
              OlChip(label: '视频', icon: 'film', selected: _filter == FileKind.video, onTap: () => setState(() => _filter = FileKind.video)),
              const SizedBox(width: 6),
              OlChip(label: '图片', icon: 'image', selected: _filter == FileKind.image, onTap: () => setState(() => _filter = FileKind.image)),
              const SizedBox(width: 6),
              OlChip(label: '文档', icon: 'file-text', selected: _filter == FileKind.text, onTap: () => setState(() => _filter = FileKind.text)),
              const SizedBox(width: 6),
              OlChip(label: '音频', icon: 'music', selected: _filter == FileKind.audio, onTap: () => setState(() => _filter = FileKind.audio)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  files.path == '/' ? '根目录' : files.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.ink4),
                ),
              ),
              Text('${files.folderCount} 个文件夹 · ${files.fileCount} 个文件', style: TextStyle(fontSize: 9, color: p.ink4)),
            ],
          ),
        ),
        if (files.error != null && files.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: _MobileError(message: files.error!),
          ),
        Expanded(
          child: RefreshIndicator(
            color: OlTokens.sky600,
            onRefresh: () => ref.read(filesProvider.notifier).refresh(),
            child: files.showSkeleton
                ? ListView(children: [for (var i = 0; i < 7; i++) const _SkeletonRow()])
                : files.items.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 60),
                          OlEmptyState(
                            icon: 'folder',
                            title: '这个目录还是空的',
                            subtitle: '点击右下角 + 上传文件或新建文件夹。',
                            action: OlPrimaryButton(label: '上传文件', icon: 'upload', onTap: () => pickAndUpload(context, ref)),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          return _MobileRow(
                            item: item,
                            onTap: () => openItem(context, ref, item),
                            onLongPress: () => _showMobileSheet(context, item),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  Future<void> _showMobileSheet(BuildContext context, FileItem item) async {
    final profile = ref.read(sessionProvider).profile;
    final files = ref.read(filesProvider);
    final path = item.parent ?? joinPath(files.path, item.name);
    final favored = profile != null && ref.read(favoritesProvider).any((e) => e.serverId == profile.id && e.path == path);
    final kind = kindOf(item.name, item.isDir);

    await olSheet<void>(
      context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('已选择 1 个项目', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: context.ol.ink2)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Text('取消', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF0A93C4))),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FileGlyph(item: item, size: 36, radius: 10, iconSize: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.ol.ink)),
                      const SizedBox(height: 2),
                      Text(
                        '${item.isDir ? '文件夹' : formatBytes(item.size)} · ${profile?.name ?? ''}',
                        style: TextStyle(fontSize: 9.5, color: context.ol.ink4),
                      ),
                    ],
                  ),
                ),
                OlIcon('info', size: 15, color: context.ol.ink4),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!item.isDir && (kind == FileKind.video || kind == FileKind.audio))
                  _SheetAction(icon: 'play', label: '播放', onTap: () {
                    Navigator.of(context).pop();
                    openItem(context, ref, item);
                  }),
                if (!item.isDir) _SheetAction(icon: 'download', label: '下载', onTap: () {
                  Navigator.of(context).pop();
                  downloadItem(context, ref, item);
                }),
                _SheetAction(icon: 'share', label: '分享', onTap: () {
                  Navigator.of(context).pop();
                  shareItem(context, ref, item);
                }),
                _SheetAction(icon: 'star', label: favored ? '已收藏' : '收藏', onTap: () async {
                  Navigator.of(context).pop();
                  if (profile == null) return;
                  await ref.read(favoritesProvider.notifier).toggle(profile.id, item, files.path);
                  if (context.mounted) olToast(context, favored ? '已取消收藏' : '已加入收藏');
                }),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in <List<String>>[
              ['重命名', 'edit'],
              ['移动到…', 'move'],
              ['复制到…', 'copy'],
              ['删除', 'trash'],
            ])
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  switch (row[0]) {
                    case '重命名':
                      renameItem(context, ref, item);
                      break;
                    case '移动到…':
                      moveOrCopyItems(context, ref, [item], move: true);
                      break;
                    case '复制到…':
                      moveOrCopyItems(context, ref, [item], move: false);
                      break;
                    case '删除':
                      deleteItems(context, ref, [item]);
                      break;
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
                  child: Row(
                    children: [
                      OlIcon(row[1], size: 15, color: row[0] == '删除' ? const Color(0xFFE06B82) : context.ol.ink3),
                      const SizedBox(width: 10),
                      Text(
                        row[0],
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: row[0] == '删除' ? const Color(0xFFD92D4B) : context.ol.ink2),
                      ),
                      const Spacer(),
                      OlIcon('chev-r', size: 13, color: context.ol.ink4),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _filterLabel(FileKind? kind) {
    switch (kind) {
      case FileKind.video:
        return '视频';
      case FileKind.image:
        return '图片';
      case FileKind.text:
        return '文档';
      case FileKind.audio:
        return '音频';
      case FileKind.folder:
        return '文件夹';
      case FileKind.archive:
        return '压缩包';
      default:
        return '全部';
    }
  }
}

// --------------------------------------------------------------- widgets

class _FilesSidebar extends ConsumerWidget {
  const _FilesSidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final files = ref.watch(filesProvider);
    final transfers = ref.watch(transfersProvider);
    final storages = ref.watch(storagesProvider);

    return Container(
      width: 204,
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OlSectionLabel('工作区'),
          _NavRow(
            icon: 'folder',
            label: '所有文件',
            badge: files.total > 0 ? '${files.total}' : null,
            active: true,
            onTap: () => ref.read(filesProvider.notifier).open('/'),
          ),
          _NavRow(icon: 'clock', label: '最近使用', onTap: () => context.push('/favorites?tab=recent')),
          _NavRow(icon: 'star', label: '收藏', onTap: () => context.push('/favorites')),
          _NavRow(icon: 'share', label: '我的分享', onTap: () => _showShares(context, ref)),
          _NavRow(
            icon: 'arrow-down',
            label: '传输任务',
            badge: transfers.pendingCount > 0 ? '${transfers.pendingCount}' : null,
            onTap: () => context.go('/transfers'),
          ),
          const OlSectionLabel('挂载点'),
          Expanded(
            child: storages.when(
              loading: () => Column(
                children: [for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.symmetric(vertical: 7, horizontal: 9), child: OlSkeleton(height: 9))],
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (mounts) => ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < mounts.length; i++)
                    InkWell(
                      onTap: () => ref.read(filesProvider.notifier).open(mounts[i].mountPath),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: _mountColor(i, mounts[i].isUp), borderRadius: BorderRadius.circular(2.5)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                baseName(mounts[i].mountPath),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.isDark ? const Color(0xFFA9BDCE) : const Color(0xFF4A5E74)),
                              ),
                            ),
                            if (mounts[i].totalSpace != null)
                              Text(formatBytes(mounts[i].totalSpace), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4)),
                            if (!mounts[i].isUp)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text('异常', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: OlTokens.warn)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (mounts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                      child: Text('服务端未返回挂载点（仅管理员可见）', style: TextStyle(fontSize: 9.5, height: 1.6, color: p.ink4)),
                    ),
                ],
              ),
            ),
          ),
          _StorageCard(files: files, storages: storages.valueOrNull ?? const []),
        ],
      ),
    );
  }

  Color _mountColor(int index, bool up) {
    if (!up) return const Color(0xFF94A3B8);
    const palette = [Color(0xFF38BDF8), Color(0xFF7C5CFC), Color(0xFF22C55E), Color(0xFFF59E0B), Color(0xFF2DD4BF)];
    return palette[index % palette.length];
  }

  Future<void> _showShares(BuildContext context, WidgetRef ref) async {
    final shares = ref.refresh(sharesProvider.future);
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x59091424),
      builder: (dialogContext) => FutureBuilder<List<ShareInfo>>(
        future: shares,
        builder: (context, snapshot) {
          final p = context.ol;
          final items = snapshot.data ?? const [];
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 460,
              height: 420,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const OlIcon('share', size: 15, color: OlTokens.sky700),
                      const SizedBox(width: 8),
                      Text('我的分享', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
                      const Spacer(),
                      OlIconButton(icon: 'x', onTap: () => Navigator.of(dialogContext).pop()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: snapshot.connectionState == ConnectionState.waiting
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : items.isEmpty
                            ? Center(child: Text('暂无分享记录', style: TextStyle(fontSize: 11.5, color: p.ink4)))
                            : ListView.builder(
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final share = items[index];
                                  final base = ref.read(sessionProvider).profile?.baseUrl ?? '';
                                  final link = (share.link?.startsWith('http') ?? false) ? share.link! : '$base/s/${share.id}';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 7),
                                    child: Row(
                                      children: [
                                        const OlIcon('link', size: 14, color: OlTokens.sky600),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(share.name ?? share.id, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink)),
                                              Text(link, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: p.ink4)),
                                            ],
                                          ),
                                        ),
                                        OlIconButton(
                                          icon: 'copy',
                                          squared: true,
                                          tooltip: '复制链接',
                                          onTap: () async {
                                            await copyToClipboard(link);
                                            if (context.mounted) olToast(context, '链接已复制');
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
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

class _NavRow extends StatelessWidget {
  final String icon;
  final String label;
  final String? badge;
  final bool active;
  final VoidCallback onTap;

  const _NavRow({required this.icon, required this.label, required this.onTap, this.badge, this.active = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: active ? p.navOnBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            OlIcon(icon, size: 15, color: active ? const Color(0xFF0EA5E9) : p.navIcon),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? p.navOn : p.nav),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: active ? p.card : p.navBadgeBg, borderRadius: BorderRadius.circular(5)),
                child: Text(
                  badge!,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: active ? const Color(0xFF0B7A9E) : p.ink3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  final FilesState files;
  final List<StorageMount> storages;

  const _StorageCard({required this.files, required this.storages});

  @override
  Widget build(BuildContext context) {
    int? total;
    int? used;
    for (final mount in storages) {
      if (mount.totalSpace != null) total = (total ?? 0) + mount.totalSpace!;
      if (mount.usedSpace != null) used = (used ?? 0) + mount.usedSpace!;
    }
    final hasUsage = total != null && used != null && total > 0;
    final ratio = hasUsage ? (used / total).clamp(0.0, 1.0).toDouble() : (files.items.isEmpty ? 0.0 : (files.items.length / (files.total == 0 ? 1 : files.total)));

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        gradient: OlTokens.deepPanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('存储用量', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF9DB4C8))),
              const Spacer(),
              Text(
                hasUsage ? '${formatBytes(used)} / ${formatBytes(total)}' : '${storages.length} 个挂载点',
                style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasUsage ? '${(ratio * 100).round()}' : '—',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              height: 4,
              color: const Color(0x22FFFFFF),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ratio <= 0 ? 0.02 : ratio,
                child: Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF2DD4BF)])),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${storages.where((e) => e.isUp).length} 个正常', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
              const Spacer(),
              Text(
                '${storages.where((e) => !e.isUp).length} 个异常',
                style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopTopBar extends ConsumerWidget {
  final VoidCallback onUpload;
  const _DesktopTopBar({required this.onUpload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final files = ref.watch(filesProvider);
    final segments = segmentsOf(files.path);

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.ol.hairline))),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => ref.read(filesProvider.notifier).goUp(),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: p.isDark ? const Color(0xFF14243A) : const Color(0xFFF4F8FC), borderRadius: BorderRadius.circular(6)),
              child: Center(child: OlIcon('chev-l', size: 12, color: p.ink3)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => ref.read(filesProvider.notifier).open('/'),
                    child: Text('全部文件', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink4)),
                  ),
                  for (var i = 0; i < segments.length; i++) ...[
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: OlIcon('chev-r', size: 12, color: Color(0xFFB2C1CF))),
                    GestureDetector(
                      onTap: i == segments.length - 1
                          ? null
                          : () => ref.read(filesProvider.notifier).open('/${segments.take(i + 1).join('/')}'),
                      child: Text(
                        segments[i],
                        style: TextStyle(
                          fontSize: i == segments.length - 1 ? 12.5 : 11.5,
                          fontWeight: i == segments.length - 1 ? FontWeight.w800 : FontWeight.w600,
                          color: i == segments.length - 1 ? p.ink : p.ink4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => context.push('/search'),
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
                  OlIcon('search', size: 13, color: p.ink4),
                  const SizedBox(width: 6),
                  Text('搜索当前目录', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: p.ink4)),
                  const Spacer(),
                  const OlKbd('Ctrl K'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          OlIconButton(
            icon: 'refresh',
            squared: true,
            tooltip: '刷新 (F5)',
            onTap: () => ref.read(filesProvider.notifier).refresh(),
          ),
          const SizedBox(width: 6),
          OlPrimaryButton(label: '上传', icon: 'upload', onTap: onUpload),
        ],
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  final List<FileItem> visible;
  final FileKind? filter;
  final ValueChanged<FileKind?> onFilter;

  const _Toolbar({required this.visible, required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final files = ref.watch(filesProvider);
    final selectedCount = files.selected.length;
    final allSelected = files.items.isNotEmpty && files.selected.length == files.items.length;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.ol.divider))),
      child: Row(
        children: [
          OlCheckbox(
            value: allSelected,
            onChanged: (_) {
              if (allSelected) {
                ref.read(filesProvider.notifier).clearSelection();
              } else {
                ref.read(filesProvider.notifier).selectAll();
              }
            },
          ),
          const SizedBox(width: 9),
          Text(
            selectedCount > 0 ? '${visible.length} 个项目 · 已选 $selectedCount 项' : '${visible.length} 个项目',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink4),
          ),
          if (selectedCount > 0) ...[
            const SizedBox(width: 10),
            _MiniAction(icon: 'download', label: '下载', onTap: () async {
              for (final item in files.selectedItems.where((e) => !e.isDir)) {
                await downloadItem(context, ref, item);
              }
            }),
            _MiniAction(icon: 'trash', label: '删除', danger: true, onTap: () => deleteItems(context, ref, files.selectedItems)),
            _MiniAction(icon: 'x', label: '取消', onTap: () => ref.read(filesProvider.notifier).clearSelection()),
          ],
          const Spacer(),
          OlSeg<bool>(
            items: const [
              OlSegItem(true, '列表', icon: 'list'),
              OlSegItem(false, '网格', icon: 'grid'),
            ],
            value: !files.grid,
            onChanged: (v) {
              if (v == files.grid) ref.read(filesProvider.notifier).toggleGrid();
            },
          ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            tooltip: '排序',
            color: p.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.line)),
            onSelected: (value) async {
              final desc = value.endsWith('_desc');
              final key = value.replaceAll('_desc', '').replaceAll('_asc', '');
              await ref.read(filesProvider.notifier).setSort(key, desc: desc);
            },
            itemBuilder: (context) => [
              _menuItem(context, 'name_asc', '名称 A → Z', files.orderBy == 'name' && !files.desc),
              _menuItem(context, 'name_desc', '名称 Z → A', files.orderBy == 'name' && files.desc),
              _menuItem(context, 'size_desc', '大小 从大到小', files.orderBy == 'size' && files.desc),
              _menuItem(context, 'size_asc', '大小 从小到大', files.orderBy == 'size' && !files.desc),
              _menuItem(context, 'modified_desc', '修改时间 最新', files.orderBy == 'modified' && files.desc),
              _menuItem(context, 'modified_asc', '修改时间 最早', files.orderBy == 'modified' && !files.desc),
            ],
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              child: OlIcon('sort', size: 15, color: p.ink3),
            ),
          ),
          PopupMenuButton<FileKind?>(
            tooltip: '筛选',
            color: p.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.line)),
            onSelected: onFilter,
            itemBuilder: (context) => [
              _menuItem(context, null, '全部类型', filter == null),
              _menuItem(context, FileKind.folder, '文件夹', filter == FileKind.folder),
              _menuItem(context, FileKind.video, '视频', filter == FileKind.video),
              _menuItem(context, FileKind.image, '图片', filter == FileKind.image),
              _menuItem(context, FileKind.text, '文档', filter == FileKind.text),
              _menuItem(context, FileKind.audio, '音频', filter == FileKind.audio),
              _menuItem(context, FileKind.archive, '压缩包', filter == FileKind.archive),
            ],
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              child: OlIcon('filter', size: 15, color: filter == null ? p.ink3 : OlTokens.sky600),
            ),
          ),
          OlIconButton(
            icon: 'folder-plus',
            tooltip: '新建文件夹 (Ctrl+Shift+N)',
            onTap: () => createFolder(context, ref),
          ),
          OlIconButton(
            icon: 'cloud-dl',
            tooltip: '离线下载',
            onTap: () => offlineDownload(context, ref),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<T> _menuItem<T>(BuildContext context, T value, String label, bool active) {
    final p = context.ol;
    return PopupMenuItem<T>(
      value: value,
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: active ? OlTokens.sky600 : p.ink2)),
          ),
          if (active) const OlIcon('check', size: 12, color: OlTokens.sky600),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _MiniAction({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFD92D4B) : context.ol.ink2;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            OlIcon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

class _TableBody extends ConsumerWidget {
  final List<FileItem> items;
  final FilesState files;
  final ScrollController controller;

  const _TableBody({required this.items, required this.files, required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return Column(
      children: [
        Container(
          height: 28,
          color: p.tableHeadBg,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const SizedBox(width: 30),
              Expanded(child: Text('名称', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: p.th))),
              SizedBox(width: 74, child: Text('大小', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: p.th))),
              SizedBox(width: 108, child: Text('修改时间', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: p.th))),
              const SizedBox(width: 34),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: controller,
            itemCount: items.length,
            itemBuilder: (context, index) => _TableRow(item: items[index], files: files),
          ),
        ),
      ],
    );
  }
}

class _TableRow extends ConsumerStatefulWidget {
  final FileItem item;
  final FilesState files;

  const _TableRow({required this.item, required this.files});

  @override
  ConsumerState<_TableRow> createState() => _TableRowState();
}

class _TableRowState extends ConsumerState<_TableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final item = widget.item;
    final selected = widget.files.selected.contains(item.name);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
          final notifier = ref.read(filesProvider.notifier);
          if (ctrl) {
            notifier.toggleSelect(item.name);
          } else {
            notifier.clearSelection();
            notifier.toggleSelect(item.name);
          }
        },
        onDoubleTap: () => openItem(context, ref, item),
        onSecondaryTapDown: (details) => showItemMenu(context, ref, item, details.globalPosition),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? p.rowSel : (_hover ? p.rowHover : Colors.transparent),
            border: Border(bottom: BorderSide(color: p.hairline)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: OlCheckbox(
                  value: selected,
                  onChanged: (_) => ref.read(filesProvider.notifier).toggleSelect(item.name),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    FileGlyph(item: item),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.isDark ? const Color(0xFFDCE9F4) : const Color(0xFF17293D)),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 74,
                child: Text(item.isDir ? '—' : formatBytes(item.size), style: TextStyle(fontSize: 11, color: p.ink3)),
              ),
              SizedBox(
                width: 108,
                child: Text(formatDate(item.modified), style: TextStyle(fontSize: 11, color: p.ink3)),
              ),
              SizedBox(
                width: 34,
                child: GestureDetector(
                  onTapDown: (details) => showItemMenu(context, ref, item, details.globalPosition),
                  child: Center(
                    child: OlIcon('more', size: 13, color: selected ? OlTokens.sky600 : const Color(0xFFC2CFDB)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridBody extends ConsumerWidget {
  final List<FileItem> items;
  final FilesState files;

  const _GridBody({required this.items, required this.files});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 168, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.22),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = files.selected.contains(item.name);
        return InkWell(
          onTap: () {
            ref.read(filesProvider.notifier).clearSelection();
            ref.read(filesProvider.notifier).toggleSelect(item.name);
          },
          onDoubleTap: () => openItem(context, ref, item),
          onSecondaryTapDown: (details) => showItemMenu(context, ref, item, details.globalPosition),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? p.rowSel : (p.isDark ? const Color(0xFF0F1D2C) : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? OlTokens.sky : p.line2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FileGlyph(item: item, size: 36, radius: 10, iconSize: 18),
                const Spacer(),
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, height: 1.35, fontWeight: FontWeight.w700, color: p.ink),
                ),
                const SizedBox(height: 3),
                Text(item.isDir ? '文件夹' : formatBytes(item.size), style: TextStyle(fontSize: 9, color: p.ink4)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DetailPanel extends ConsumerWidget {
  final FileItem item;
  final VoidCallback onClose;

  const _DetailPanel({required this.item, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final files = ref.watch(filesProvider);
    final kind = kindOf(item.name, item.isDir);
    final siblings = files.items.where((e) => e.name != item.name).take(4).toList();
    final isMedia = kind == FileKind.video || kind == FileKind.image;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(left: BorderSide(color: p.line2)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('详情', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.th)),
                const Spacer(),
                OlIconButton(icon: 'x', size: 20, iconSize: 13, onTap: onClose),
              ],
            ),
            const SizedBox(height: 8),
            if (isMedia)
              OlMediaThumb(
                height: 112,
                title: baseName(item.name).toUpperCase(),
                subtitle: kind == FileKind.video ? 'MEDIA · RANGE STREAM' : 'IMAGE PREVIEW',
                tag: extensionOf(item.name).toUpperCase(),
              )
            else
              Container(
                height: 112,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF5F9FC), Color(0xFFEAF2F9)]),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: p.line2),
                ),
                child: Center(
                  child: FileGlyph(item: item, size: 56, radius: 16, iconSize: 26),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              item.name,
              style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w800, color: p.isDark ? const Color(0xFFDCE9F4) : const Color(0xFF17293D)),
            ),
            const SizedBox(height: 3),
            Text(
              item.isDir ? '文件夹' : '${formatBytes(item.size)} · ${extensionOf(item.name).toUpperCase()}',
              style: TextStyle(fontSize: 10, color: p.ink4),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (isMedia)
                  Expanded(
                    child: _DetailButton(
                      icon: 'play',
                      label: '播放',
                      primary: true,
                      onTap: () => openItem(context, ref, item),
                    ),
                  )
                else
                  Expanded(
                    child: _DetailButton(
                      icon: 'external',
                      label: '打开',
                      primary: true,
                      onTap: () => openItem(context, ref, item),
                    ),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: _DetailButton(
                    icon: 'download',
                    label: '下载',
                    onTap: () => downloadItem(context, ref, item),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _DetailButton(
                    icon: 'share',
                    label: '分享',
                    onTap: () => shareItem(context, ref, item),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _DetailButton(icon: 'more', label: '更多', onTap: () {
                    final box = context.findRenderObject() as RenderBox?;
                    final position = box == null ? Offset.zero : box.localToGlobal(const Offset(10, 10));
                    showItemMenu(context, ref, item, position);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: p.isDark ? const Color(0xFF0F1D2C) : const Color(0xFFF7FAFD),
                border: Border.all(color: p.line2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _MetaRow(label: '位置', value: files.path),
                  _MetaRow(label: '存储', value: files.provider ?? '—'),
                  _MetaRow(label: '修改时间', value: formatDateTime(item.modified)),
                  if (item.hashInfo != null) _MetaRow(label: '哈希', value: item.hashInfo!, mono: true),
                ],
              ),
            ),
            if (siblings.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('同目录', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.th)),
              const SizedBox(height: 4),
              for (final sibling in siblings)
                InkWell(
                  onTap: () {
                    ref.read(filesProvider.notifier).clearSelection();
                    ref.read(filesProvider.notifier).toggleSelect(sibling.name);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                    child: Row(
                      children: [
                        FileGlyph(item: sibling, size: 22, radius: 6, iconSize: 11),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(sibling.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: p.ink2)),
                        ),
                        Text(sibling.isDir ? '—' : formatBytes(sibling.size, digits: 0), style: TextStyle(fontSize: 9, color: p.ink4)),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _DetailButton({required this.icon, required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          decoration: BoxDecoration(
            gradient: primary ? OlTokens.gradientPrimary : null,
            color: primary ? null : p.card,
            border: Border.all(color: primary ? Colors.transparent : (p.isDark ? const Color(0xFF1E3044) : const Color(0xFFE6EDF5))),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OlIcon(icon, size: 12, color: primary ? Colors.white : p.ink3),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: primary ? Colors.white : p.ink2)),
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
  final bool mono;

  const _MetaRow({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
              style: TextStyle(
                fontSize: mono ? 9 : 10,
                fontWeight: FontWeight.w700,
                fontFamily: mono ? 'monospace' : null,
                color: p.isDark ? const Color(0xFFC7D8E6) : const Color(0xFF22364B),
              ),
            ),
          ),
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
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: p.surfaceAlt, border: Border(top: BorderSide(color: p.line2))),
      child: Row(
        children: [
          OlDot(color: session.signedIn ? OlTokens.ok : OlTokens.warn, size: 5),
          const SizedBox(width: 5),
          Text(
            session.signedIn ? '已连接 · 延迟 ${session.latencyMs ?? '—'} ms' : '未连接',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: p.ink4),
          ),
          const SizedBox(width: 12),
          Text(
            files.provider == null ? '—' : '${files.provider} · ${files.items.length} 项已加载',
            style: TextStyle(fontSize: 9.5, color: p.ink4),
          ),
          const Spacer(),
          if (!files.canWrite)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('只读目录', style: TextStyle(fontSize: 9.5, color: OlTokens.warn)),
            ),
          Text(session.profile?.version ?? session.site?.version ?? 'API v4', style: TextStyle(fontSize: 9.5, color: p.ink4)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends ConsumerWidget {
  final String message;
  final bool offline;

  const _ErrorBanner({required this.message, this.offline = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6F7),
        border: Border.all(color: const Color(0xFFFFDCE2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const OlIcon('alert', size: 14, color: Color(0xFFD92D4B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              offline ? '$message · 正在显示本地缓存' : message,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB42A45)),
            ),
          ),
          GestureDetector(
            onTap: () => ref.read(filesProvider.notifier).refresh(),
            child: const Text('重试', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF0A93C4))),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => context.push('/settings?tab=diagnostics'),
            child: const Text('诊断', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF7C8FA3))),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFE9FBF5), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFFCFF1E8))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          OlDot(size: 5, color: OlTokens.teal600),
          SizedBox(width: 6),
          Text('离线可用 · 写操作已禁用', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF0B7A63))),
        ],
      ),
    );
  }
}

class _SkeletonTable extends StatelessWidget {
  final bool grid;
  const _SkeletonTable({this.grid = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Column(
      children: [
        Container(height: 28, color: p.tableHeadBg),
        for (var i = 0; i < 7; i++)
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
            child: Row(
              children: [
                const OlSkeleton(width: 13, height: 13, radius: 4),
                const SizedBox(width: 12),
                const OlSkeleton(width: 24, height: 24, radius: 7),
                const SizedBox(width: 9),
                Expanded(child: OlSkeleton(width: 120 + (i % 4) * 42, height: 9)),
                OlSkeleton(width: 46, height: 9),
                const SizedBox(width: 24),
                OlSkeleton(width: 68, height: 9),
              ],
            ),
          ),
      ],
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Row(
        children: const [
          OlSkeleton(width: 36, height: 36, radius: 10),
          SizedBox(width: 10),
          Expanded(child: OlSkeleton(height: 10)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- mobile

class _MobileHeader extends ConsumerWidget {
  final String path;
  const _MobileHeader({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final profile = ref.watch(sessionProvider).profile;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          if (path != '/')
            GestureDetector(
              onTap: () => ref.read(filesProvider.notifier).goUp(),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: OlIcon('chev-l', size: 18, color: p.ink3),
              ),
            ),
          GestureDetector(
            onTap: () => context.push('/servers'),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: p.isDark ? const Color(0xFF12202F) : const Color(0xFFF1F8FC),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: p.isDark ? const Color(0xFF1C2E43) : const Color(0xFFE3EFF7)),
              ),
              child: Row(
                children: [
                  const OlDot(size: 6),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      profile?.displayHost ?? '未连接',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.isDark ? const Color(0xFFC7D8E6) : const Color(0xFF3E5268)),
                    ),
                  ),
                  const SizedBox(width: 3),
                  OlIcon('chev-d', size: 11, color: p.ink4),
                ],
              ),
            ),
          ),
          const Spacer(),
          _CircleButton(icon: 'search', onTap: () => context.push('/search')),
          const SizedBox(width: 8),
          _CircleButton(
            icon: 'more-v',
            onTap: () async {
              final size = MediaQuery.sizeOf(context);
              final position = Offset(size.width / 2 - 40, 90);
              await showOlMenu(context, position: position, items: [
                OlMenuItem('新建文件夹', 'folder-plus', () => createFolder(context, ref)),
                OlMenuItem('上传文件', 'upload', () => pickAndUpload(context, ref)),
                OlMenuItem('离线下载', 'cloud-dl', () => offlineDownload(context, ref)),
                OlMenuItem('刷新', 'refresh', () => ref.read(filesProvider.notifier).refresh()),
                OlMenuItem('服务器管理', 'server', () => context.push('/servers')),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: p.isDark ? const Color(0xFF12202F) : const Color(0xFFF4F8FC),
          shape: BoxShape.circle,
          border: Border.all(color: p.isDark ? const Color(0xFF1C2E43) : const Color(0xFFE9F0F7)),
        ),
        child: Center(child: OlIcon(icon, size: 16, color: p.isDark ? const Color(0xFF93A9BD) : const Color(0xFF5E7288))),
      ),
    );
  }
}

class _SortChip extends ConsumerWidget {
  const _SortChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(filesProvider);
    final label = switch (files.orderBy) {
      'size' => '按大小',
      'modified' => '修改时间',
      _ => '名称',
    };
    return GestureDetector(
      onTapDown: (details) async {
        await showOlMenu(context, position: details.globalPosition, items: [
          OlMenuItem('名称 A → Z', 'sort', () => ref.read(filesProvider.notifier).setSort('name', desc: false)),
          OlMenuItem('名称 Z → A', 'sort', () => ref.read(filesProvider.notifier).setSort('name', desc: true)),
          OlMenuItem('大小 从大到小', 'sort', () => ref.read(filesProvider.notifier).setSort('size', desc: true)),
          OlMenuItem('修改时间 最新', 'sort', () => ref.read(filesProvider.notifier).setSort('modified', desc: true)),
        ]);
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Text('$label${files.desc ? ' ↓' : ' ↑'}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF0A93C4))),
            const OlIcon('chev-d', size: 10, color: Color(0xFF0A93C4)),
          ],
        ),
      ),
    );
  }
}

class _MobileStorageRow extends ConsumerWidget {
  const _MobileStorageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storages = ref.watch(storagesProvider);
    final mounts = storages.valueOrNull ?? const <StorageMount>[];
    if (mounts.isEmpty) return const SizedBox.shrink();
    final gradients = const [
      [Color(0xFF0E3A52), Color(0xFF0C6470)],
      [Color(0xFF3B2C6E), Color(0xFF5B4BB7)],
      [Color(0xFF6A3E12), Color(0xFFA8641B)],
    ];
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: mounts.length,
        itemBuilder: (context, index) {
          final mount = mounts[index];
          final ratio = mount.usageRatio;
          final gradient = gradients[index % gradients.length];
          return Container(
            width: 152,
            height: 96,
            margin: const EdgeInsets.only(right: 10, top: 2),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const OlIcon('cloud', size: 12, color: Color(0xB8FFFFFF)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        baseName(mount.mountPath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xB8FFFFFF)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  mount.totalSpace == null ? '—' : formatBytes(mount.totalSpace, digits: 1),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Colors.white),
                ),
                const Spacer(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    height: 3,
                    color: const Color(0x38FFFFFF),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (ratio ?? (mount.isUp ? 0.05 : 0.02)).clamp(0.02, 1.0).toDouble(),
                      child: Container(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  ratio == null ? (mount.isUp ? '正常 · ${mount.driver}' : '异常 · ${mount.driver}') : '已用 ${(ratio * 100).round()}% · ${mount.driver}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8, color: Color(0x9EFFFFFF)),
                ),
              ],
            ),
          );
        },
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
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.isDark ? const Color(0xFF142435) : const Color(0xFFF4F8FB)))),
        child: Row(
          children: [
            FileGlyph(item: item, size: 36, radius: 10, iconSize: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: -0.1, color: p.isDark ? const Color(0xFFDCE9F4) : const Color(0xFF1B2F43)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.isDir ? '文件夹 · ${formatDate(item.modified)}' : '${formatBytes(item.size)} · ${formatDate(item.modified)}',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: p.ink4),
                  ),
                ],
              ),
            ),
            OlIcon(item.isDir ? 'chev-r' : 'more-v', size: 14, color: const Color(0xFFC2CFDB)),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _SheetAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: p.isDark ? const Color(0xFF12202F) : const Color(0xFFF2F8FC), borderRadius: BorderRadius.circular(14)),
              child: Center(child: OlIcon(icon, size: 19, color: p.isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0A93C4))),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.ink2)),
          ],
        ),
      ),
    );
  }
}

class _MobileError extends StatelessWidget {
  final String message;
  const _MobileError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFFFF6F7), border: Border.all(color: const Color(0xFFFFDCE2)), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const OlIcon('alert', size: 14, color: Color(0xFFD92D4B)),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 11, color: Color(0xFFB42A45), fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
