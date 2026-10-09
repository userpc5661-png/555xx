import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/services/session_credentials.dart';

void main() {
  test('account details drop tokens and passwords, also nested', () {
    final clean = SessionCredentials.withoutSecrets({
      'id': 7,
      'name': 'أحمد',
      'api_token': 'abc',
      'password': 'x',
      'phone': '0500000000',
      'hub': {'name': 'Dammam', 'jwtToken': 'y'},
    });
    expect(clean.keys, containsAll(['id', 'name', 'phone', 'hub']));
    expect(clean.containsKey('api_token'), isFalse);
    expect(clean.containsKey('password'), isFalse);
    expect((clean['hub'] as Map).containsKey('jwtToken'), isFalse);
    expect((clean['hub'] as Map)['name'], 'Dammam');
  });

  test('a saved session keeps the name and account details', () {
    final session = SessionCredentials.fromSavedSession(jsonEncode({
      'v': 2,
      'bearer': 't',
      'ids': {'id': 7},
      'name': 'أحمد',
      'profile': {'id': 7, 'name': 'أحمد'},
    }));
    expect(session.driverName, 'أحمد');
    expect(session.profile['id'], 7);
    expect(SessionCredentials.fromSavedSession('old-token').profile, isEmpty);
  });
}
