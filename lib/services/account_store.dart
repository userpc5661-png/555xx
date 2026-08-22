import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedAccount {
  final String id;
  final String email;
  final String password;
  const SavedAccount({required this.id, required this.email, required this.password});
}

class AccountStore {
  static const _storage = FlutterSecureStorage();
  static const _accountsKey = 'saved_accounts_v1';
  static const _activeKey = 'active_account_id';
  static String currentAccountId = 'default';

  static String idFor(String email) => base64Url
      .encode(utf8.encode(email.trim().toLowerCase()))
      .replaceAll('=', '');

  Future<List<SavedAccount>> readAccounts() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return SavedAccount(
          id: (m['id'] ?? '').toString(),
          email: (m['email'] ?? '').toString(),
          password: (m['password'] ?? '').toString(),
        );
      }).where((e) => e.id.isNotEmpty && e.email.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCredentials(String email, String password) async {
    final accounts = (await readAccounts()).toList();
    final id = idFor(email);
    accounts.removeWhere((a) => a.id == id);
    accounts.insert(0, SavedAccount(id: id, email: email.trim(), password: password));
    await _storage.write(
      key: _accountsKey,
      value: jsonEncode(accounts.map((a) => {
        'id': a.id,
        'email': a.email,
        'password': a.password,
      }).toList()),
    );
    await setActive(id);
  }

  Future<void> setActive(String id) async {
    currentAccountId = id.isEmpty ? 'default' : id;
    await _storage.write(key: _activeKey, value: currentAccountId);
  }

  Future<String> restoreActive() async {
    final id = await _storage.read(key: _activeKey);
    currentAccountId = (id == null || id.isEmpty) ? 'default' : id;
    return currentAccountId;
  }
}
