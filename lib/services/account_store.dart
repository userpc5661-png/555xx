import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedAccount {
  final String id;
  final String email;
  final String password;
  const SavedAccount({required this.id, required this.email, required this.password});
}

/// The last sign-in of a saved account on this phone.
class AccountLogin {
  final String name;
  final DateTime at;
  final bool ok;
  final String? error;
  const AccountLogin({
    required this.name,
    required this.at,
    required this.ok,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'at': at.toIso8601String(),
        'ok': ok,
        'error': error,
      };

  factory AccountLogin.fromJson(Map<String, dynamic> json) => AccountLogin(
        name: (json['name'] ?? '').toString(),
        at: DateTime.tryParse('${json['at']}') ?? DateTime.now(),
        ok: json['ok'] == true,
        error: json['error']?.toString(),
      );
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

  static const _loginsKey = 'account_logins_v1';

  /// Last sign-in per account id.
  Future<Map<String, AccountLogin>> readLogins() async {
    try {
      final raw = await _storage.read(key: _loginsKey);
      if (raw == null || raw.isEmpty) return {};
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return {
        for (final entry in map.entries)
          if (entry.value is Map)
            entry.key: AccountLogin.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  /// Records a sign-in attempt for [email]. A failed attempt keeps the name
  /// from the last successful one.
  Future<void> recordLogin(
    String email, {
    required bool ok,
    String name = '',
    String? error,
  }) async {
    final id = idFor(email);
    final all = await readLogins();
    all[id] = AccountLogin(
      name: name.isNotEmpty ? name : (all[id]?.name ?? ''),
      at: DateTime.now(),
      ok: ok,
      error: ok ? null : error,
    );
    await _storage.write(
      key: _loginsKey,
      value: jsonEncode({
        for (final entry in all.entries) entry.key: entry.value.toJson(),
      }),
    );
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
