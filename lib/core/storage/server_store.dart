import '../models/server_profile.dart';
import 'prefs.dart';

/// Persists the server index, the active instance and every per-server key.
/// Nothing here is ever sent to a server: the whole file is local-only.
class ServerStore {
  static const keyIndex = 'ol_servers_index';
  static const keyActive = 'ol_active_server_id';
  static const keyPrefs = 'ol_prefs';

  final Prefs prefs;

  ServerStore(this.prefs);

  List<ServerProfile> loadServers() {
    final raw = prefs.getJsonList(keyIndex);
    final out = <ServerProfile>[];
    for (final e in raw) {
      if (e is Map) {
        final p = ServerProfile.fromJson(Map<String, dynamic>.from(e));
        if (p.id.isNotEmpty && p.baseUrl.isNotEmpty) out.add(p);
      }
    }
    out.sort((a, b) => (b.lastUsed ?? DateTime(1970)).compareTo(a.lastUsed ?? DateTime(1970)));
    return out;
  }

  Future<void> saveServers(List<ServerProfile> servers) async {
    await prefs.setJsonList(keyIndex, servers.map((e) => e.toJson()).toList());
  }

  String? loadActiveId() {
    final id = prefs.getString(keyActive);
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> saveActiveId(String? id) async {
    if (id == null || id.isEmpty) {
      await prefs.remove(keyActive);
    } else {
      await prefs.setString(keyActive, id);
    }
  }

  // ------------------------------------------------------- per-server data

  Future<void> saveBrowse(String id, String path, String orderBy, bool desc) async {
    await prefs.setJsonMap('ol_srv_${id}_browse', {
      'path': path,
      'order_by': orderBy,
      'order_direction': desc ? 'desc' : 'asc',
      'saved_at': DateTime.now().toIso8601String(),
    });
  }

  Map<String, dynamic> readBrowse(String id) => prefs.getJsonMap('ol_srv_${id}_browse');

  Future<void> saveDownloadDir(String id, String dir) =>
      prefs.setString('ol_srv_${id}_download', dir);

  String? readDownloadDir(String id) => prefs.getString('ol_srv_${id}_download');

  Future<void> clearDownloadDir(String id) => prefs.remove('ol_srv_${id}_download');

  Future<void> saveFavorites(String id, List<Map<String, dynamic>> items) =>
      prefs.setJsonList('ol_srv_${id}_favorites', items);

  List<Map<String, dynamic>> readFavorites(String id) {
    final raw = prefs.getJsonList('ol_srv_${id}_favorites');
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> saveRecent(String id, List<Map<String, dynamic>> items) =>
      prefs.setJsonList('ol_srv_${id}_recent', items);

  List<Map<String, dynamic>> readRecent(String id) {
    final raw = prefs.getJsonList('ol_srv_${id}_recent');
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> saveResume(String id, String path, int seconds) async {
    final all = prefs.getJsonMap('ol_srv_${id}_resume');
    all[path] = seconds;
    final keys = all.keys.toList();
    if (keys.length > 300) {
      for (final k in keys.take(keys.length - 300)) {
        all.remove(k);
      }
    }
    await prefs.setJsonMap('ol_srv_${id}_resume', all);
  }

  int readResume(String id, String path) {
    final all = prefs.getJsonMap('ol_srv_${id}_resume');
    final v = all[path];
    return v is num ? v.toInt() : 0;
  }

  /// Offline list cache: survives a dropped connection so the last directory
  /// stays readable (W2 四态 / 离线).
  Future<void> cacheListing(String id, String path, List<Map<String, dynamic>> items) async {
    final map = <String, dynamic>{'items': items, 'at': DateTime.now().toIso8601String()};
    await prefs.setJsonMap('ol_srv_${id}_cache|$path', map);
  }

  Map<String, dynamic> readCachedListing(String id, String path) =>
      prefs.getJsonMap('ol_srv_${id}_cache|$path');
}
