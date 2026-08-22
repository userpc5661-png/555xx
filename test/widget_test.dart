import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/app.dart';

void main() {
  testWidgets('shows login when there is no saved session', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const SlsAssistantApp());
    await tester.pumpAndSettle();

    expect(find.text('SLS Assistant Pro'), findsOneWidget);
  });
}
