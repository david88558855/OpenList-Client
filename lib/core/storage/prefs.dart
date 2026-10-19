import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Key/value store using the key names fixed by the handoff spec:
/// ol_servers_index / ol_active_server_id / ol_srv_<id>_* / ol_prefs.
class Prefs {
  final SharedPreferences _sp;

  Prefs(this._sp);

  static Future<Prefs> load() async => Prefs(await SharedPreferences.getInstance());

  String? getString(String key) => _sp.getString(key);
  Future<void> setString(String key, String value) => _sp.setString(key, value);
  bool getBool(String key, {bool fallback = false}) => _sp.getBool(key) ?? fallback;
  Future<void> setBool(String key, bool value) => _sp.setBool(key, value);
  int getInt(String key, {int fallback = 0}) => _sp.getInt(key) ?? fallback;
  Future<void> setInt(String key, int value) => _sp.setInt(key, value);
  double getDouble(String key, {double fallback = 0}) => _sp.getDouble(key) ?? fallback;
  Future<void> setDouble(String key, double value) => _sp.setDouble(key, value);
  Future<void> remove(String key) => _sp.remove(key);

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
      _sp.setString(key, jsonEncode(value));

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
      _sp.setString(key, jsonEncode(value));
}
