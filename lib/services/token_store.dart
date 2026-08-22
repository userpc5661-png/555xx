import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'account_store.dart';

class TokenStore {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  Future<void> save(String token) =>
      _storage.write(key: _tokenKey, value: token);
  Future<String?> read() => _storage.read(key: _tokenKey);
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    // Keep the active account and its saved credentials on logout.
  }

  Future<void> restoreAccountScope() => AccountStore().restoreActive();
}
