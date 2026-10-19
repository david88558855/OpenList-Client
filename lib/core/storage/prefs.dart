import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key/value store using the key names fixed by the handoff spec:
/// ol_servers_index / ol_active_server_id / ol_srv_<id>_* / ol_prefs.
///
/// Windows 便携版约定（设计稿 08 · 本地存储键）：
///   - `<exe>/userdata/prefs.json` 是偏好的一份镜像，原子写（tmp → rename）；
///   - 解压到新机器后本地没有偏好时，用这份 JSON 回填，做到「解压即用」；
///   - 密钥永远不写入 prefs.json（Token 只在系统安全存储里）。
class Prefs {
  final SharedPreferences _sp;
  final File? _portableFile;
  Timer? _mirrorTimer;

  Prefs._(this._sp, this._portableFile);

  static Future<Prefs> load() async {
    final sp = await SharedPreferences.getInstance();
    final prefs = Prefs._(sp, _portablePath());
    await prefs._restorePortable();
    return prefs;
  }

  static File? _portablePath() {
    if (!Platform.isWindows) return null;
    try {
      final dir = File(Platform.resolvedExecutable).parent;
      final sep = Platform.pathSeparator;
      return File('${dir.path}${sep}userdata${sep}prefs.json');
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ portable json

  /// 新机器首次启动：本地偏好为空时从 userdata/prefs.json 回填。
  Future<void> _restorePortable() async {
    final file = _portableFile;
    if (file == null || !file.existsSync()) return;
    if (_sp.getKeys().isNotEmpty) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is String) {
          await _sp.setString(key, value);
        } else if (value is bool) {
          await _sp.setBool(key, value);
        } else if (value is int) {
          await _sp.setInt(key, value);
        } else if (value is double) {
          await _sp.setDouble(key, value);
        } else if (value is List) {
          await _sp.setStringList(key, value.map((e) => e.toString()).toList());
        }
      }
    } catch (error) {
      debugPrint('prefs: portable restore skipped ($error)');
    }
  }

  void _scheduleMirror() {
    if (_portableFile == null) return;
    _mirrorTimer?.cancel();
    _mirrorTimer = Timer(const Duration(milliseconds: 250), () {
      _mirrorNow();
    });
  }

  /// 立即落盘（退出前调用，保证最后一次设置不丢）。
  Future<void> flush() async {
    _mirrorTimer?.cancel();
    _mirrorTimer = null;
    await _mirrorNow();
  }

  Future<void> _mirrorNow() async {
    final file = _portableFile;
    if (file == null) return;
    try {
      final map = <String, dynamic>{};
      for (final key in _sp.getKeys()) {
        final value = _sp.get(key);
        if (value is String || value is bool || value is int || value is double) {
          map[key] = value;
        } else if (value is List<String>) {
          map[key] = value;
        }
      }
      final dir = file.parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(map), flush: true);
      if (file.existsSync()) file.deleteSync();
      await tmp.rename(file.path);
    } catch (error) {
      debugPrint('prefs: portable mirror failed ($error)');
    }
  }

  // ------------------------------------------------------------------ reading

  String? getString(String key) => _sp.getString(key);
  bool getBool(String key, {bool fallback = false}) => _sp.getBool(key) ?? fallback;
  int getInt(String key, {int fallback = 0}) => _sp.getInt(key) ?? fallback;
  double getDouble(String key, {double fallback = 0}) => _sp.getDouble(key) ?? fallback;

  // ------------------------------------------------------------------ writing

  Future<void> setString(String key, String value) async {
    await _sp.setString(key, value);
    _scheduleMirror();
  }

  Future<void> setBool(String key, bool value) async {
    await _sp.setBool(key, value);
    _scheduleMirror();
  }

  Future<void> setInt(String key, int value) async {
    await _sp.setInt(key, value);
    _scheduleMirror();
  }

  Future<void> setDouble(String key, double value) async {
    await _sp.setDouble(key, value);
    _scheduleMirror();
  }

  Future<void> remove(String key) async {
    await _sp.remove(key);
    _scheduleMirror();
  }

  List<dynamic> getJsonList(String key) {
    final raw = _sp.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } catch (_) {
      return const [];
    }
    return const [];
  }

  Future<void> setJsonList(String key, List<dynamic> value) =>
      setString(key, jsonEncode(value));

  Map<String, dynamic> getJsonMap(String key) {
    final raw = _sp.getString(key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const {};
    }
    return const {};
  }

  Future<void> setJsonMap(String key, Map<String, dynamic> value) =>
      setString(key, jsonEncode(value));
}
