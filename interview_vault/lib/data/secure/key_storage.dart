import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API Key 唯一存放处（AGENTS 安全红线）：
/// - 底层 flutter_secure_storage → Android Keystore / iOS Keychain
/// - 绝不写入 SQLite、日志、异常堆栈
/// - 用户可随时删除（delete/deleteActive）
class KeyStorage {
  KeyStorage([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static String _keyFor(String provider) => 'apikey.$provider';

  Future<void> write(String provider, String apiKey) =>
      _storage.write(key: _keyFor(provider), value: apiKey);

  Future<String?> read(String provider) => _storage.read(key: _keyFor(provider));

  Future<void> delete(String provider) => _storage.delete(key: _keyFor(provider));

  Future<bool> has(String provider) =>
      _storage.containsKey(key: _keyFor(provider));
}
