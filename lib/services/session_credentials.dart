import 'dart:convert';

class SessionCredentials {
  final String apiToken;
  final String cookie;
  final Map<String, dynamic> ids;

  /// The driver's name from the login reply; empty for sessions saved
  /// before it was kept.
  final String driverName;

  /// The account details from the login reply, without tokens or
  /// passwords; empty for sessions saved before they were kept.
  final Map<String, dynamic> profile;

  const SessionCredentials({
    required this.apiToken,
    required this.cookie,
    this.ids = const {},
    this.driverName = '',
    this.profile = const {},
  });

  static bool _isSecret(String key) {
    final k = key.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return k.contains('token') ||
        k.contains('password') ||
        k.contains('secret') ||
        k.contains('cookie') ||
        k.contains('jwt') ||
        k.contains('otp') ||
        k == 'pin';
  }

  /// [map] with every token, password and similar field removed, also in
  /// nested objects.
  static Map<String, dynamic> withoutSecrets(Map<String, dynamic> map) {
    Object? clean(Object? value) {
      if (value is Map) {
        return {
          for (final entry in value.entries)
            if (!_isSecret('${entry.key}'))
              '${entry.key}': clean(entry.value),
        };
      }
      if (value is List) return [for (final item in value) clean(item)];
      return value;
    }

    return Map<String, dynamic>.from(clean(map) as Map);
  }

  factory SessionCredentials.fromSavedSession(String savedSession) {
    final value = savedSession.trim();
    if (value.startsWith('{')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return SessionCredentials(
            apiToken: (decoded['bearer'] ?? '').toString(),
            cookie: (decoded['cookie'] ?? '').toString(),
            ids: decoded['ids'] is Map
                ? Map<String, dynamic>.from(decoded['ids'] as Map)
                : const {},
            driverName: (decoded['name'] ?? '').toString().trim(),
            profile: decoded['profile'] is Map
                ? Map<String, dynamic>.from(decoded['profile'] as Map)
                : const {},
          );
        }
      } catch (_) {
        // Fall through to compatibility formats used by older builds.
      }
    }
    if (value.startsWith('bearer:')) {
      return SessionCredentials(
        apiToken: value.substring('bearer:'.length),
        cookie: '',
      );
    }
    if (value.startsWith('cookie:')) {
      return SessionCredentials(
        apiToken: '',
        cookie: value.substring('cookie:'.length),
      );
    }
    return SessionCredentials(apiToken: value, cookie: '');
  }
}
