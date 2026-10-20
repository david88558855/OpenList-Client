import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key/value store.
///
/// v1.0.20 起 Windows 走**真正的便携存储**：
///   - 权威文件：`<主程序目录>/userdata/prefs.json`（相对 exe 解析，
///     整个目录拷走/搬走，配置跟着走）；
///   - 所有读写都在内存 Map 上完成，写操作合并后 250ms 落盘（tmp → rename 原子写），
///     进程退出前 `flush()` 保证最后一次写入不丢；
///   - 主程序目录不可写（例如装在 Program Files）时退到
///     `%LOCALAPPDATA%/OpenListClient/userdata/prefs.json`。
///
/// 其它平台（Android）仍然用 SharedPreferences，行为不变。
///
/// 兼容：老版本把数据放在系统用户目录（SharedPreferences）。首次以新版本启动时，
/// 会把旧存储里 prefs.json 尚未覆盖的键**合并**进来，再写回便携文件——
/// 用户升级后不会丢服务器列表、收藏、浏览位置等。
///
/// 键名沿用固定约定：ol_servers_index / ol_active_server_id / ol_srv_<id>_* /
/// ol_prefs / ol_transfers。密钥（密码 / Token）永远不进这个文件，只在系统安全存储。
class Prefs {
  final Map<String, Object?> _data;
  final File? _file;
  final SharedPreferences? _sp;
  Timer? _flushTimer;
  bool _dirty = false;

  /// 落盘互斥：同一时刻只允许一路写 `.tmp`（见 `_flushNow`）。
  bool _flushing = false;
  bool _pending = false;

  /// 迁移完成标记：写在便携文件里，避免每次启动都被旧 SharedPreferences 覆盖。
  static const _migratedKey = 'ol_portable_migrated';

  Prefs._file(this._data, this._file) : _sp = null;
  Prefs._sp(this._sp)
      : _data = <String, Object?>{},
        _file = null;

  /// 便携存储是否生效（Windows 且拿到了可写路径）。
  bool get isPortable => _file != null;

  /// 数据文件位置，设置页展示用。
  String get storagePath => _file?.path ?? '系统存储（SharedPreferences）';

  static Future<Prefs> load() async {
    if (!Platform.isWindows) {
      final sp = await SharedPreferences.getInstance();
      return Prefs._sp(sp);
    }
    final file = _portablePath();
    if (file == null) {
      // 程序目录与 LOCALAPPDATA 都不可写（极端情况）：退回系统存储，
      // 至少不让数据只停留在内存里。
      debugPrint('prefs: no writable portable dir, falling back to shared_preferences');
      final sp = await SharedPreferences.getInstance();
      return Prefs._sp(sp);
    }
    final data = <String, Object?>{};
    var dirty = false;

    if (file != null && file.existsSync()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          decoded.forEach((k, v) => data[k.toString()] = v);
        }
      } catch (error) {
        // 文件损坏：备份现场，随后由迁移补回
        try {
          await file.rename('${file.path}.bak');
        } catch (_) {}
        debugPrint('prefs: portable file corrupt, backed up ($error)');
      }
    }

    // 一次性迁移：老版本把数据放在系统用户目录（SharedPreferences）。
    // SharedPreferences 是旧版的权威存储，每次写入都 await 过，所以它不会比
    // prefs.json 镜像旧 —— 首次迁移以它为准覆盖文件。
    // 迁移完成写入标记，之后永远只认便携文件（否则每次启动都会被旧数据覆盖）。
    if (data[_migratedKey] != true) {
      try {
        final sp = await SharedPreferences.getInstance();
        for (final key in sp.getKeys()) {
          final value = sp.get(key);
          if (value != null) data[key] = value;
        }
        data[_migratedKey] = true;
        dirty = true;
      } catch (error) {
        debugPrint('prefs: migrate from shared_preferences failed ($error)');
      }
    }

    final prefs = Prefs._file(data, file);
    if (dirty) await prefs._flushNow(force: true);
    return prefs;
  }

  /// `<主程序目录>/userdata/prefs.json`，不可写时退到 LOCALAPPDATA。
  ///
  /// 用 `Platform.resolvedExecutable` 的父目录解析——不依赖当前工作目录，
  /// 从快捷方式、任务栏、命令行任意方式启动都指向同一个位置。
  static File? _portablePath() {
    final sep = Platform.pathSeparator;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final dir = Directory('${exeDir.path}${sep}userdata');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}${sep}prefs.json');
    } catch (error) {
      debugPrint('prefs: exe dir not writable, falling back ($error)');
    }
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      final dir = Directory('$local${sep}OpenListClient${sep}userdata');
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return File('${dir.path}${sep}prefs.json');
      } catch (error) {
        debugPrint('prefs: LOCALAPPDATA not writable ($error)');
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ 读写

  Object? _read(String key) {
    final sp = _sp;
    if (sp != null) return sp.get(key);
    return _data[key];
  }

  Future<void> _write(String key, Object? value) async {
    final sp = _sp;
    if (sp != null) {
      if (value is String) {
        await sp.setString(key, value);
      } else if (value is bool) {
        await sp.setBool(key, value);
      } else if (value is int) {
        await sp.setInt(key, value);
      } else if (value is double) {
        await sp.setDouble(key, value);
      } else if (value is List) {
        await sp.setStringList(key, value.map((e) => '$e').toList());
      }
      return;
    }
    _data[key] = value;
    _schedule();
  }

  Future<void> _remove(String key) async {
    final sp = _sp;
    if (sp != null) {
      await sp.remove(key);
      return;
    }
    _data.remove(key);
    _schedule();
  }

  String? getString(String key) {
    final value = _read(key);
    return value is String ? value : null;
  }

  bool getBool(String key, {bool fallback = false}) {
    final value = _read(key);
    return value is bool ? value : fallback;
  }

  int getInt(String key, {int fallback = 0}) {
    final value = _read(key);
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  double getDouble(String key, {double fallback = 0}) {
    final value = _read(key);
    if (value is num) return value.toDouble();
    return fallback;
  }

  Future<void> setString(String key, String value) => _write(key, value);
  Future<void> setBool(String key, bool value) => _write(key, value);
  Future<void> setInt(String key, int value) => _write(key, value);
  Future<void> setDouble(String key, double value) => _write(key, value);
  Future<void> remove(String key) => _remove(key);

  List<dynamic> getJsonList(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } catch (_) {
      return const [];
    }
    return const [];
  }

  Future<void> setJsonList(String key, List<dynamic> value) => setString(key, jsonEncode(value));

  Map<String, dynamic> getJsonMap(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const {};
    }
    return const {};
  }

  Future<void> setJsonMap(String key, Map<String, dynamic> value) => setString(key, jsonEncode(value));

  // ------------------------------------------------------------------ 落盘

  void _schedule() {
    if (_file == null) return;
    _dirty = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 250), () {
      _flushNow();
    });
  }

  /// 立即落盘（退出前调用，保证最后一次写入不丢）。
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flushNow(force: true);
  }

  /// 落盘。
  ///
  /// 两条硬约束（审查发现的问题，v1.0.21）：
  ///   1. **互斥**：定时器回调与 `flush()` 可能同时进来，两路写同一个 `.tmp`
  ///      会产出半截 JSON。这里用 `_flushing` + `_pending` 串行化，同一时刻只有一路在写。
  ///   2. **可回滚的原子替换**：旧文件先改名成 `.bak` 再让 `.tmp` 就位（不是先删后改名），
  ///      替换失败还能把 `.bak` 还原回去，避免"目标已删、新文件没就位"导致的配置全丢。
  Future<void> _flushNow({bool force = false}) async {
    final file = _file;
    if (file == null) return;
    if (!_dirty && !force) return;
    if (_flushing) {
      _pending = true;
      return;
    }
    _flushing = true;
    _dirty = false;
    final bak = File('${file.path}.bak');
    try {
      final map = <String, dynamic>{};
      _data.forEach((key, value) {
        if (value is String || value is num || value is bool || value is List || value is Map) {
          map[key] = value;
        }
      });
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(map), flush: true);

      if (file.existsSync()) {
        try {
          if (bak.existsSync()) bak.deleteSync();
          file.renameSync(bak.path);
        } catch (error) {
          debugPrint('prefs: rotate to .bak failed ($error)');
        }
      }
      try {
        await tmp.rename(file.path);
      } catch (error) {
        // 替换失败：把备份还原，宁可留着旧数据也不要丢
        try {
          if (!file.existsSync() && bak.existsSync()) bak.renameSync(file.path);
        } catch (_) {}
        rethrow;
      }
    } catch (error) {
      // 落盘失败保留脏标记，下次写入或退出时再试
      _dirty = true;
      debugPrint('prefs: flush failed ($error)');
    } finally {
      _flushing = false;
      if (_pending) {
        _pending = false;
        unawaited(_flushNow());
      }
    }
  }
}
