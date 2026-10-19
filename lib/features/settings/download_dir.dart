import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/models/server_profile.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';

/// Android 11+ 写入公共目录需要「所有文件访问权限」（MANAGE_EXTERNAL_STORAGE）。
/// 通过原生通道查询状态并跳转授权页，避免引入额外权限插件。
class StorageAccess {
  const StorageAccess._();

  static const MethodChannel _channel = MethodChannel('com.openlist.client/storage');

  static Future<bool> hasAllFiles() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> requestAllFiles() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestAllFilesAccess');
    } on PlatformException {
      // 用户直接返回，忽略
    } on MissingPluginException {
      // 宿主未实现通道（旧安装包），忽略
    }
  }
}

/// 系统默认下载根目录（不含 OpenList 子目录）。
Future<String> defaultDownloadBase() async {
  if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    final fallback = await getApplicationDocumentsDirectory();
    return (external ?? fallback).path;
  }
  final downloads = await getDownloadsDirectory();
  final fallback = await getApplicationDocumentsDirectory();
  return (downloads ?? fallback).path;
}

String _safeName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return sanitized.isEmpty ? 'item' : sanitized;
}

/// 当前生效的下载目录：用户显式选择的优先，否则按实例隔离规则推导。
Future<String> resolveDownloadDir(WidgetRef ref, ServerProfile profile) async {
  final saved = ref.read(serverStoreProvider).readDownloadDir(profile.id);
  if (saved != null && saved.isNotEmpty) return saved;
  final base = await defaultDownloadBase();
  final sep = Platform.pathSeparator;
  return profile.isolatedDownload ? '$base${sep}OpenList$sep${_safeName(profile.name)}' : '$base${sep}OpenList';
}

/// 弹出下载目录面板：选择目录 / 恢复默认 / 安卓去授权。
Future<void> showDownloadDirSheet(BuildContext context, WidgetRef ref) async {
  final profile = ref.read(sessionProvider).profile;
  if (profile == null) {
    olToast(context, '请先登录服务器');
    return;
  }
  final path = await resolveDownloadDir(ref, profile);
  final authorized = await StorageAccess.hasAllFiles();
  if (!context.mounted) return;

  final action = await olSheet<String>(
    context,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: const Color(0xFFDEE7F0), borderRadius: BorderRadius.circular(2))),
        Row(
          children: [
            const OlIcon('download', size: 16, color: OlTokens.sky600),
            const SizedBox(width: 8),
            const Text('下载目录', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${profile.name} · 独立子目录', style: TextStyle(fontSize: 10, color: context.ol.ink4)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(color: context.ol.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.ol.line2)),
          child: Row(
            children: [
              OlIcon('folder', size: 13, color: context.ol.ink3),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: context.ol.ink2),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (Platform.isAndroid)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: authorized ? const Color(0xFFE9FBF5) : const Color(0xFFFFF8EC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: authorized ? const Color(0xFFCFF1E8) : const Color(0xFFFBE7C2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OlIcon('shield', size: 13, color: authorized ? OlTokens.teal600 : const Color(0xFFC98106)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    authorized
                        ? '已获得文件访问权限，可直接写入公共目录。'
                        : 'Android 11 起写入公共「下载」目录需要「所有文件访问权限」；也可选择一个文件夹（SAF），授权一次长期有效。',
                    style: TextStyle(fontSize: 10, height: 1.6, color: authorized ? const Color(0xFF0B7A63) : const Color(0xFF8A5B05)),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (Platform.isAndroid && !authorized)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OlGhostButton(
                    label: '去授权',
                    icon: 'shield',
                    onTap: () => Navigator.of(context).pop('auth'),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OlGhostButton(
                  label: '恢复默认',
                  onTap: () => Navigator.of(context).pop('reset'),
                ),
              ),
            ),
            Expanded(
              child: OlPrimaryButton(
                label: '选择目录',
                icon: 'folder',
                onTap: () => Navigator.of(context).pop('pick'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    ),
  );

  if (!context.mounted) return;
  switch (action) {
    case 'auth':
      await StorageAccess.requestAllFiles();
      if (context.mounted) olToast(context, '授权完成后重新打开本面板即可选择目录');
      break;
    case 'reset':
      await ref.read(serverStoreProvider).clearDownloadDir(profile.id);
      if (context.mounted) olToast(context, '已恢复默认下载目录');
      break;
    case 'pick':
      await _pick(context, ref, profile);
      break;
  }
}

Future<void> _pick(BuildContext context, WidgetRef ref, ServerProfile profile) async {
  if (Platform.isAndroid && !await StorageAccess.hasAllFiles()) {
    if (!context.mounted) return;
    final go = await olConfirm(
      context,
      title: '需要文件访问权限',
      message: 'Android 11 起，写入公共目录需要「所有文件访问权限」。可以先去授权后重试，或改用应用私有目录（无需授权）。',
      confirm: '去授权',
      icon: 'shield',
    );
    if (go) await StorageAccess.requestAllFiles();
    return;
  }
  final picked = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择下载目录');
  if (picked == null || picked.isEmpty) return;
  await ref.read(serverStoreProvider).saveDownloadDir(profile.id, picked);
  if (context.mounted) olToast(context, '下载目录已更新');
}

/// 设置页（移动）里的一行：下载目录 + 状态。
class DownloadDirTile extends ConsumerStatefulWidget {
  const DownloadDirTile({super.key});

  @override
  ConsumerState<DownloadDirTile> createState() => _DownloadDirTileState();
}

class _DownloadDirTileState extends ConsumerState<DownloadDirTile> {
  String? _path;
  bool _authorized = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = ref.read(sessionProvider).profile;
    if (profile == null) return;
    final path = await resolveDownloadDir(ref, profile);
    final ok = await StorageAccess.hasAllFiles();
    if (!mounted) return;
    setState(() {
      _path = path;
      _authorized = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final needsAuth = Platform.isAndroid && !_authorized;
    return InkWell(
      onTap: () async {
        await showDownloadDirSheet(context, ref);
        await _load();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        child: Row(
          children: [
            OlIcon('download', size: 16, color: needsAuth ? const Color(0xFFB47405) : p.ink3),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('下载目录', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink)),
                const SizedBox(height: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 208),
                  child: Text(
                    _path ?? '读取中…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: p.ink4),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (needsAuth)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFF6E5), borderRadius: BorderRadius.circular(4)),
                child: const Text('需授权', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFFB47405))),
              )
            else if (_path != null)
              Text('可用', style: TextStyle(fontSize: 9, color: p.ink4)),
            const SizedBox(width: 4),
            OlIcon('chev-r', size: 13, color: p.ink4),
          ],
        ),
      ),
    );
  }
}

/// 设置页（桌面）里的「下载目录」行。
class DownloadDirLine extends ConsumerStatefulWidget {
  const DownloadDirLine({super.key});

  @override
  ConsumerState<DownloadDirLine> createState() => _DownloadDirLineState();
}

class _DownloadDirLineState extends ConsumerState<DownloadDirLine> {
  String? _path;
  bool _authorized = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = ref.read(sessionProvider).profile;
    if (profile == null) return;
    final path = await resolveDownloadDir(ref, profile);
    final ok = await StorageAccess.hasAllFiles();
    if (!mounted) return;
    setState(() {
      _path = path;
      _authorized = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final needsAuth = Platform.isAndroid && !_authorized;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('下载目录', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink2)),
                    if (needsAuth) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFFFF6E5), borderRadius: BorderRadius.circular(4)),
                        child: const Text('需授权', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFFB47405))),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _path ?? '读取中…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: p.ink4, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          OlGhostButton(
            label: '更改',
            icon: 'folder',
            onTap: () async {
              await showDownloadDirSheet(context, ref);
              await _load();
            },
          ),
        ],
      ),
    );
  }
}
