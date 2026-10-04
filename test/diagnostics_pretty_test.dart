import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/services/developer_diagnostics_service.dart';

void main() {
  test('plain-text JSON responses are decoded and indented', () {
    final text = DeveloperDiagnosticsService.pretty('{"success":true,"tasks":[1]}');
    expect(text, contains('"success": true'));
    expect(text, contains('\n'));
  });

  test('tokens stay masked', () {
    final text = DeveloperDiagnosticsService.pretty({
      'api_token': 'secret',
      'nested': {'Authorization': 'Bearer x'},
      'ok': 1,
    });
    expect(text, isNot(contains('secret')));
    expect(text, isNot(contains('Bearer x')));
    expect(text, contains('"ok": 1'));
  });

  test('non-JSON text is returned as is', () {
    expect(DeveloperDiagnosticsService.pretty('Not Found'), 'Not Found');
    expect(DeveloperDiagnosticsService.pretty(null), '<empty>');
  });
}
