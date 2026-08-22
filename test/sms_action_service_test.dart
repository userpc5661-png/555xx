import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/models/task_item.dart';
import 'package:sls_assistant_pro/services/sms_action_service.dart';

void main() {
  test('SMS message uses store, real AWB and driver WhatsApp link', () {
    final task = TaskItem.fromJson({
      'order_awb': 'SLS-REAL-123',
      'reference_no': 'DISPLAY-9',
      'merchant': {'name': 'متجر الاختبار'},
      'customer_name': 'أحمد',
      'customer_phone': '0501234567',
    });

    final message = SmsActionService.buildMessage(task, '0551234567');
    expect(message, contains('متجر الاختبار'));
    expect(message, contains('SLS-REAL-123'));
    expect(message, contains('https://wa.me/966551234567'));
    expect(message, contains('عنوانك الوطني'));
  });
}
