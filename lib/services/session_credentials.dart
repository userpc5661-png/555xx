import 'dart:convert';

class SessionCredentials {
  final String apiToken;
  final String cookie;

  const SessionCredentials({required this.apiToken, required this.cookie});

  factory SessionCredentials.fromSavedSession(String savedSession) {
    final value = savedSession.trim();
    if (value.startsWith('{')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return SessionCredentials(
            apiToken: (decoded['bearer'] ?? '').toString(),
            cookie: (decoded['cookie'] ?? '').toString(),
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
