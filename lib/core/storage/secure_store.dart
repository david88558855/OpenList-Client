import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens and passwords never touch prefs, logs or crash reports.
/// Windows → Credential Manager, Android → Keystore-backed storage.
class SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    wOptions: WindowsOptions(),
  );

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Keychain failures must not break browsing; the session simply won't
      // survive a restart.
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // ignore
    }
  }

  Future<bool> has(String key) async => (await read(key))?.isNotEmpty == true;
}
