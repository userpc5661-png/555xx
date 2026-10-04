import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/utils/status_verification.dart';

void main() {
  test('matches when the server reports the sent status code', () {
    expect(
      StatusVerification.matches(
        {'order_awb': 'A1', 'status_code': 7},
        sentStatusId: 7,
        delivered: false,
      ),
      isTrue,
    );
    expect(
      StatusVerification.matches(
        {'order': {'order_status_code': '12'}},
        sentStatusId: 12,
        delivered: false,
      ),
      isTrue,
    );
  });

  test('does not match while the old status is still there', () {
    expect(
      StatusVerification.matches(
        {'status_code': 3, 'status_label': 'Out for delivery'},
        sentStatusId: 7,
        delivered: false,
      ),
      isFalse,
    );
  });

  test('delivered is confirmed by a delivered label', () {
    expect(
      StatusVerification.matches(
        {'status_code': 99, 'status_label': 'Delivered'},
        sentStatusId: 7,
        delivered: true,
      ),
      isTrue,
    );
    expect(
      StatusVerification.matches(
        {'status_code': 3, 'status_label': 'Out for delivery'},
        sentStatusId: 7,
        delivered: true,
      ),
      isFalse,
    );
  });

  test('a "Not Delivered" label is never taken as delivered', () {
    expect(
      StatusVerification.matches(
        {'status_code': 4, 'status_label': 'Not Delivered'},
        sentStatusId: 7,
        delivered: true,
      ),
      isFalse,
    );
  });
}
