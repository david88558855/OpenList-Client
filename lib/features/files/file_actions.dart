import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/file_widgets.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../settings/download_dir.dart';

String _basename(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? path : parts.last;
}

Future<void> pickAndUpload(BuildContext context, WidgetRef ref) async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: true);
  if (result == null) return;
  final paths = result.files.map((e) => e.path).whereType<String>().toList();
  if (paths.isEmpty) return;
  await uploadPaths(context, ref, paths);
}

Future<void> uploadPaths(BuildContext context, WidgetRef ref, List<String> paths) async {
  final dir = ref.read(filesProvider).path;
  if (!ref.read(filesProvider).canWrite) {
    olToast(context, '当前目录没有写入权限', error: true);
    return;
  }
  final transfers = ref.read(transfersProvider.notifier);
  var queued = 0;
  for (final path in paths) {
    final error = await transfers.enqueueUpload(localPath: path, remoteDir: dir, name: _basename(path));
    if (error == null) queued++;
  }
  if (queued > 0) {
    olToast(context, '已加入上传队列 · $queued 个文件');
  }
}

Future<void> createFolder(BuildContext context, WidgetRef ref) async {
  final dir = ref.read(filesProvider).path;
  final name = await olPrompt(
    context,
    title: '新建文件夹',
    message: '将在「${dir == '/' ? '根目录' : dir}」下创建',
    hint: '文件夹名称',
    icon: 'folder-plus',
    confirm: '创建',
  );
  if (name == null || name.trim().isEmpty) return;
  final target = joinPath(dir, name.trim());
  final error = await ref.read(filesProvider.notifier).mutate((api) => api.mkdir(target));
  if (error != null && context.mounted) {
    olToast(context, error, error: true);
  } else if (context.mounted) {
    olToast(context, '已创建 ${name.trim()}');
  }
}

Future<void> renameItem(BuildContext context, WidgetRef ref, FileItem item) async {
  final dir = ref.read(filesProvider).path;
  final name = await olPrompt(
    context,
    title: '重命名',
    hint: '新名称',
    initial: item.name,
    icon: 'edit',
    confirm: '重命名',
  );
  if (name == null || name.trim().isEmpty || name.trim() == item.name) return;
  final source = joinPath(dir, item.name);
  final error = await ref.read(filesProvider.notifier).mutate((api) => api.rename(source, name.trim()));
  if (error != null && context.mounted) {
    olToast(context, error, error: true);
  } else if (context.mounted) {
    olToast(context, '已重命名');
  }
}

Future<void> deleteItems(BuildContext context, WidgetRef ref, List<FileItem> items) async {
  if (items.isEmpty) return;
  final dir = ref.read(filesProvider).path;
  final confirmed = await olConfirm(
    context,
    title: items.length == 1 ? '删除「${items.first.name}」' : '删除 ${items.length} 个项目',
    message: '删除后无法从客户端恢复（服务端回收站策略取决于存储驱动）。',
    confirm: '删除',
    danger: true,
  );
  if (!confirmed) return;
  final error = await ref.read(filesProvider.notifier).mutate((api) => api.remove(dir, items.map((e) => e.name).toList()));
  if (!context.mounted) return;
  if (error != null) {
    olToast(context, error, error: true);
  } else {
    olToast(context, '已删除 ${items.length} 个项目');
    ref.read(filesProvider.notifier).clearSelection();
  }
}

Future<void> moveOrCopyItems(BuildContext context, WidgetRef ref, List<FileItem> items, {required bool move}) async {
  if (items.isEmpty) return;
  final dir = ref.read(filesProvider).path;
  final target = await showDialog<String>(
    context: context,
    barrierColor: const Color(0x59091424),
    builder: (_) => _DirPickerDialog(title: move ? '移动到…' : '复制到…', initialPath: dir),
  );
  if (target == null) return;
  if (target == dir) {
    if (context.mounted) olToast(context, '目标目录与当前目录相同', error: true);
    return;
  }
  // 目录不能移动到自身或自己的子目录（服务端会失败，或产生环）。
  for (final item in items) {
    if (!item.isDir) continue;
    final itemPath = joinPath(dir, item.name);
    if (target == itemPath || target.startsWith('$itemPath/')) {
      if (context.mounted) olToast(context, '不能把「${item.name}」移动到它自己的子目录', error: true);
      return;
    }
  }
  final names = items.map((e) => e.name).toList();
  final error = await ref.read(filesProvider.notifier).mutate(
        (api) => move ? api.move(dir, target, names) : api.copy(dir, target, names),
      );
  if (!context.mounted) return;
  if (error != null) {
    olToast(context, error, error: true);
  } else {
    olToast(context, move ? '已移动 ${names.length} 个项目' : '已复制 ${names.length} 个项目');
    ref.read(filesProvider.notifier).clearSelection();
  }
}

/// 本次进程内只提示一次「公共目录未授权」，避免每次下载都弹。
bool _storageHintShown = false;

Future<void> downloadItem(BuildContext context, WidgetRef ref, FileItem item) async {
  // v2.5：默认下载目录改到公共 Download 目录，未授权时会在 ensureDownloadDirFor
  // 里退回应用私有目录——这里显式说明一次，避免用户找不到文件。
  if (Platform.isAndroid && !_storageHintShown) {
    final granted = await StorageAccess.hasAllFiles();
    if (!granted) {
      _storageHintShown = true;
      if (context.mounted) {
        olToast(context, '未授予「所有文件访问权限」，本次保存到应用私有目录；可在 设置 → 下载目录 授权后改用公共 Download 目录');
      }
    }
  }
  final error = await ref.read(transfersProvider.notifier).enqueueDownload(item, ref.read(filesProvider).path);
  if (!context.mounted) return;
  if (error != null) {
    olToast(context, error, error: true);
  } else {
    olToast(context, '已开始下载 ${item.name}');
  }
}

Future<void> shareItem(BuildContext context, WidgetRef ref, FileItem item) async {
  final session = ref.read(sessionProvider);
  final api = session.api;
  if (api == null) return;
  final path = item.parent ?? joinPath(ref.read(filesProvider).path, item.name);
  final result = await showDialog<ShareRequest>(
    context: context,
    barrierColor: const Color(0x59091424),
    builder: (_) => _ShareDialog(name: item.name),
  );
  if (result == null) return;
  try {
    final share = await api.createShare(path: path, expireDays: result.expireDays, password: result.password);
    if (!context.mounted) return;
    if (share == null) {
      olToast(context, '服务端未返回分享信息', error: true);
      return;
    }
    final link = share.link != null && share.link!.startsWith('http')
        ? share.link!
        : '${session.profile?.baseUrl ?? ''}/s/${share.id}';
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x59091424),
      builder: (_) => _ShareResultDialog(link: link, password: result.password, expireDays: result.expireDays),
    );
  } on ApiException catch (e) {
    if (context.mounted) olToast(context, e.friendly, error: true);
  }
}

Future<void> offlineDownload(BuildContext context, WidgetRef ref) async {
  final dir = ref.read(filesProvider).path;
  final urls = await olPrompt(
    context,
    title: '离线下载',
    message: '每行一个链接，保存到「${dir == '/' ? '根目录' : dir}」。需要服务端已配置 Aria2 / qBittorrent。',
    hint: 'https://example.com/file.iso',
    icon: 'cloud-dl',
    confirm: '添加任务',
    maxLines: 4,
  );
  if (urls == null) return;
  final list = urls.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (list.isEmpty) return;
  final error = await ref.read(filesProvider.notifier).mutate(
        (api) => api.addOfflineDownload(urls: list, path: dir),
        refreshAfter: false,
      );
  if (!context.mounted) return;
  if (error != null) {
    olToast(context, error, error: true);
  } else {
    olToast(context, '已提交 ${list.length} 个离线任务');
    ref.read(transfersProvider.notifier).loadServerTasks();
  }
}

Future<String?> signedUrl(WidgetRef ref, FileItem item) async {
  final api = ref.read(sessionProvider).api;
  if (api == null) return null;
  var sign = item.sign;
  final path = item.parent ?? joinPath(ref.read(filesProvider).path, item.name);
  if (sign == null || sign.isEmpty) {
    try {
      final info = await api.get(path);
      sign = info.sign;
    } on ApiException catch (_) {
      return null;
    }
  }
  return api.downloadUrl(path, sign: sign);
}

Future<void> openItem(BuildContext context, WidgetRef ref, FileItem item) async {
  final files = ref.read(filesProvider.notifier);
  final dir = ref.read(filesProvider).path;
  if (item.isDir) {
    await files.open(joinPath(dir, item.name));
    return;
  }
  final kind = kindOf(item.name, false);
  if (kind == FileKind.video || kind == FileKind.audio) {
    final path = item.parent ?? joinPath(dir, item.name);
    context.push('/player?path=${Uri.encodeComponent(path)}&name=${Uri.encodeComponent(item.name)}');
    return;
  }
  await previewItem(context, ref, item);
}

Future<void> previewItem(BuildContext context, WidgetRef ref, FileItem item) async {
  final kind = kindOf(item.name, false);
  final url = await signedUrl(ref, item);
  if (!context.mounted) return;
  if (url == null) {
    olToast(context, '无法获取预览直链', error: true);
    return;
  }
  await showDialog<void>(
    context: context,
    barrierColor: const Color(0x8C07111D),
    builder: (dialogContext) {
      final p = dialogContext.ol;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(28),
        child: Container(
          width: 720,
          constraints: const BoxConstraints(maxHeight: 620),
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
                child: Row(
                  children: [
                    FileGlyph(item: item, size: 24, radius: 7, iconSize: 13),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink)),
                    ),
                    Text(formatBytes(item.size), style: TextStyle(fontSize: 10, color: p.ink4)),
                    const SizedBox(width: 10),
                    OlIconButton(icon: 'x', onTap: () => Navigator.of(dialogContext).pop()),
                  ],
                ),
              ),
              Flexible(
                child: _PreviewBody(kind: kind, url: url, item: item),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PreviewBody extends StatefulWidget {
  final FileKind kind;
  final String url;
  final FileItem item;

  const _PreviewBody({required this.kind, required this.url, required this.item});

  @override
  State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody> {
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.kind != FileKind.image && widget.kind != FileKind.video) {
      _loadText();
    }
  }

  Future<void> _loadText() async {
    try {
      final response = await Dio().get<List<int>>(
        widget.url,
        options: Options(responseType: ResponseType.bytes, validateStatus: (s) => s != null && s < 400),
      );
      final bytes = response.data ?? const <int>[];
      final slice = bytes.length > 200000 ? bytes.sublist(0, 200000) : bytes;
      setState(() {
        _text = utf8.decode(slice, allowMalformed: true);
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取文件内容，可能不是文本文件');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    if (widget.kind == FileKind.image) {
      return Container(
        color: const Color(0xFF0B1622),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text('图片加载失败', style: TextStyle(fontSize: 12, color: p.ink3)),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, style: TextStyle(fontSize: 12, color: p.ink3)),
      );
    }
    if (_text == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: p.surfaceAlt,
      child: SingleChildScrollView(
        child: SelectableText(
          _text!.isEmpty ? '（空文件）' : _text!,
          style: TextStyle(fontSize: 11.5, height: 1.7, fontFamily: 'monospace', color: p.ink2),
        ),
      ),
    );
  }
}


/// Row “more” menu + right-click menu share the same entries.
/// 媒体类文件的「打开」动作（v2.4）。
///
/// 之前只有视频 / 音频有入口，图片只能靠双击预览；现在点击即弹菜单，
/// 所以图片也要给一个显式的预览项，否则点开菜单没有任何"能看"的动作。
OlMenuItem? _openAction(BuildContext context, WidgetRef ref, FileItem item) {
  if (item.isDir) return null;
  switch (kindOf(item.name, false)) {
    case FileKind.video:
    case FileKind.audio:
      return OlMenuItem('播放', 'play', () => openItem(context, ref, item));
    case FileKind.image:
      return OlMenuItem('预览', 'image', () => openItem(context, ref, item));
    case FileKind.text:
    case FileKind.code:
      return OlMenuItem('预览', 'file-text', () => openItem(context, ref, item));
    default:
      return null;
  }
}

Future<void> showItemMenu(
  BuildContext context,
  WidgetRef ref,
  FileItem item,
  Offset position, {
  List<FileItem>? selection,
}) async {
  final files = ref.read(filesProvider);
  final profile = ref.read(sessionProvider).profile;
  final path = item.parent ?? joinPath(files.path, item.name);
  final isFavorite = profile != null && ref.read(favoritesProvider).any((e) => e.serverId == profile.id && e.path == path);
  final targets = (selection != null && selection.length > 1) ? selection : [item];

  final openAction = _openAction(context, ref, item);
  final entries = <OlMenuItem>[
    if (openAction != null) openAction,
    if (!item.isDir) OlMenuItem('下载', 'download', () => downloadItem(context, ref, item)),
    OlMenuItem('分享', 'share', () => shareItem(context, ref, item)),
    OlMenuItem(
      isFavorite ? '取消收藏' : '收藏',
      'star',
      () async {
        if (profile == null) return;
        await ref.read(favoritesProvider.notifier).toggle(profile.id, item, files.path);
        if (context.mounted) olToast(context, isFavorite ? '已取消收藏' : '已加入收藏');
      },
    ),
    OlMenuItem('重命名', 'edit', () => renameItem(context, ref, item)),
    OlMenuItem('移动到…', 'move', () => moveOrCopyItems(context, ref, targets, move: true)),
    OlMenuItem('复制到…', 'copy', () => moveOrCopyItems(context, ref, targets, move: false)),
    OlMenuItem('删除', 'trash', () => deleteItems(context, ref, targets), danger: true),
  ];

  // A7：Android 用底部操作面板；Windows 用右键浮层。动作集合完全一致。
  if (Platform.isAndroid || context.isNarrow) {
    final quick = <OlMenuItem>[
      if (openAction != null) openAction,
      if (!item.isDir) OlMenuItem('下载', 'download', () => downloadItem(context, ref, item)),
      OlMenuItem('分享', 'share', () => shareItem(context, ref, item)),
      OlMenuItem(
        isFavorite ? '取消收藏' : '收藏',
        'star',
        () async {
          if (profile == null) return;
          await ref.read(favoritesProvider.notifier).toggle(profile.id, item, files.path);
          if (context.mounted) olToast(context, isFavorite ? '已取消收藏' : '已加入收藏');
        },
      ),
    ];
    final quickLabels = quick.map((e) => e.label).toSet();
    await showOlActionSheet(
      context,
      count: targets.length,
      title: item.name,
      subtitle: item.isDir ? '文件夹' : '${formatBytes(item.size)} · ${formatDate(item.modified)}',
      leading: FileGlyph(item: item, size: 38, radius: 10, iconSize: 18),
      quick: quick,
      items: entries.where((e) => !quickLabels.contains(e.label)).toList(),
    );
    return;
  }

  await showOlMenu(context, position: position, items: entries);
}

class ShareRequest {
  final int expireDays;
  final String? password;
  const ShareRequest(this.expireDays, this.password);
}

class _ShareDialog extends StatefulWidget {
  final String name;
  const _ShareDialog({required this.name});

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  int _days = 0;
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: const Color(0xFFEAF8FE), borderRadius: BorderRadius.circular(9)),
                  child: const Center(child: OlIcon('share', size: 14, color: OlTokens.sky700)),
                ),
                const SizedBox(width: 9),
                Expanded(child: Text('创建分享 · ${widget.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink))),
              ],
            ),
            const SizedBox(height: 14),
            Text('有效期', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.ink3)),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              children: [
                for (final option in const [0, 1, 7, 30])
                  OlChip(
                    label: option == 0 ? '永久' : '$option 天',
                    selected: _days == option,
                    onTap: () => setState(() => _days = option),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('提取码（可选）', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.ink3)),
            const SizedBox(height: 7),
            OlField(controller: _password, icon: 'key', hint: '留空则无需提取码'),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text('取消', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink3)),
                  ),
                ),
                const SizedBox(width: 6),
                OlPrimaryButton(
                  label: '创建分享',
                  onTap: () => Navigator.of(context).pop(ShareRequest(_days, _password.text.trim().isEmpty ? null : _password.text.trim())),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareResultDialog extends StatelessWidget {
  final String link;
  final String? password;
  final int expireDays;

  const _ShareResultDialog({required this.link, this.password, required this.expireDays});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const OlIcon('check', size: 15, color: OlTokens.ok),
                const SizedBox(width: 8),
                Text('分享已创建', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
                const Spacer(),
                Text(expireDays == 0 ? '永久有效' : '$expireDays 天后过期', style: TextStyle(fontSize: 9.5, color: p.ink4)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line2)),
              child: SelectableText(link, style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: p.ink2)),
            ),
            if (password != null) ...[
              const SizedBox(height: 8),
              Text('提取码：$password', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink2)),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OlGhostButton(label: '关闭', onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 8),
                OlPrimaryButton(
                  label: '复制链接',
                  icon: 'copy',
                  onTap: () async {
                    await copyToClipboard(link);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      olToast(context, '链接已复制');
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Server-side directory picker used by move / copy (POST /api/fs/dirs).
class _DirPickerDialog extends ConsumerStatefulWidget {
  final String title;
  final String initialPath;

  const _DirPickerDialog({required this.title, required this.initialPath});

  @override
  ConsumerState<_DirPickerDialog> createState() => _DirPickerDialogState();
}

class _DirPickerDialogState extends ConsumerState<_DirPickerDialog> {
  late String _path = widget.initialPath;
  List<DirNode> _dirs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(sessionProvider).api;
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _dirs = const [];
    });
    try {
      final dirs = await api.dirs(path: _path);
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.friendly;
      });
    }
  }

  Future<void> _enter(String path) async {
    _path = path;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        height: 480,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                OlIcon('move', size: 15, color: OlTokens.sky700),
                const SizedBox(width: 8),
                Text(widget.title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
                const Spacer(),
                OlIconButton(icon: 'x', onTap: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.line2)),
              child: Row(
                children: [
                  OlIcon('folder', size: 12, color: p.ink3),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: p.ink2))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? Center(child: Text(_error!, style: TextStyle(fontSize: 11.5, color: const Color(0xFFD92D4B))))
                      : ListView(
                          children: [
                            if (_path != '/')
                              InkWell(
                                onTap: () => _enter(parentOf(_path)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                                  child: Row(
                                    children: [
                                      OlIcon('chev-u', size: 13, color: p.ink3),
                                      const SizedBox(width: 8),
                                      Text('返回上级', style: TextStyle(fontSize: 11.5, color: p.ink3)),
                                    ],
                                  ),
                                ),
                              ),
                            for (final dir in _dirs)
                              InkWell(
                                onTap: () => _enter(dir.path),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                                  child: Row(
                                    children: [
                                      const OlIcon('folder', size: 14, color: OlTokens.sky600),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(dir.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.ink))),
                                      OlIcon('chev-r', size: 12, color: p.ink4),
                                    ],
                                  ),
                                ),
                              ),
                            if (_dirs.isEmpty && _path != '/')
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text('该目录下没有子文件夹', style: TextStyle(fontSize: 11, color: p.ink4)),
                              ),
                          ],
                        ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('目标：$_path', style: TextStyle(fontSize: 9.5, color: p.ink4)),
                const Spacer(),
                OlGhostButton(label: '取消', onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 8),
                OlPrimaryButton(label: '选择此目录', onTap: () => Navigator.of(context).pop(_path)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
