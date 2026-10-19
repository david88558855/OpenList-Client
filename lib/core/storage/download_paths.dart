import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/server_profile.dart';
import 'server_store.dart';

/// 下载落盘路径的唯一来源（v2.5）。
///
/// 规则：
///   - Android：公共「下载」目录 `/storage/emulated/0/Download/OpenList`；
///     开启「按实例隔离」时再拼服务器显示名
///     `/storage/emulated/0/Download/OpenList/<服务器名>`。
///   - Windows / macOS / Linux：系统下载目录下的 `OpenList`，隔离开启时再拼服务器名。
///   - 用户在设置里显式选过目录时，显式目录优先。
String safePathSegment(String value) {
  final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return sanitized.isEmpty ? 'item' : sanitized;
}

/// Android 的公共下载根目录（不含 OpenList 子目录）。
///
/// 不用 `getDownloadsDirectory()`：在 Android 上它返回的是
/// `/storage/emulated/0/Android/data/<pkg>/files/Download`（应用私有），
/// 文件管理器看不到。这里从 `getExternalStorageDirectory()` 的路径里截出存储根，
/// 兼容多用户 / 可移动存储（`/storage/emulated/<userId>`、`/storage/XXXX-XXXX`）。
Future<String> androidPublicDownloadRoot() async {
  String? external;
  try {
    external = (await getExternalStorageDirectory())?.path;
  } catch (_) {
    external = null;
  }
  final path = external ?? '';
  final cut = path.indexOf('/Android/');
  final storageRoot = cut > 0 ? path.substring(0, cut) : '/storage/emulated/0';
  return '$storageRoot/Download';
}

/// 系统默认下载根目录：Android 为公共 Download，桌面为系统下载文件夹。
Future<String> defaultDownloadBase() async {
  if (Platform.isAndroid) return androidPublicDownloadRoot();
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null && downloads.path.isNotEmpty) return downloads.path;
  } catch (_) {
    // 某些 Linux 桌面没有 XDG 下载目录，退回文档目录
  }
  final fallback = await getApplicationDocumentsDirectory();
  return fallback.path;
}

/// 当前生效的下载目录（显式选择 > 默认 + OpenList [+ 服务器名]）。
Future<String> resolveDownloadDirFor(ServerStore store, ServerProfile profile) async {
  final saved = store.readDownloadDir(profile.id);
  if (saved != null && saved.isNotEmpty) return saved;
  final base = await defaultDownloadBase();
  final sep = Platform.pathSeparator;
  return profile.isolatedDownload
      ? '$base${sep}OpenList${sep}${safePathSegment(profile.name)}'
      : '$base${sep}OpenList';
}

/// 解析并确保目录存在；Android 未授予「所有文件访问权限」时退回应用私有目录，
/// 避免整个下载任务因为一个 mkdir 失败而直接报错。
Future<String> ensureDownloadDirFor(ServerStore store, ServerProfile profile) async {
  final dir = await resolveDownloadDirFor(store, profile);
  try {
    await Directory(dir).create(recursive: true);
    return dir;
  } catch (error) {
    debugPrint('download: 无法创建 $dir（$error），退回应用私有目录');
    final fallback = await getApplicationDocumentsDirectory();
    final alt = '${fallback.path}${Platform.pathSeparator}OpenList';
    await Directory(alt).create(recursive: true);
    return alt;
  }
}
