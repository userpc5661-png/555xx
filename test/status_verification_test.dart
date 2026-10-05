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

  group('not-delivered reasons (status code stays 2)', () {
    // Shapes from orders/awb in a real shift log.
    Map<String, dynamic> order(String label, String updatedAt) => {
          'success': true,
          'order': {
            'status': 'In Transit',
            'status_code': 2,
            'status_label': label,
            'updated_at': updatedAt,
            'customer': {'updated_at': '2026-10-05T19:09:22.000000Z'},
          },
        };
    final sentAt = DateTime.utc(2026, 10, 5, 19, 9, 20);

    test('"Out for delivery" is not taken as the new reason', () {
      expect(
        StatusVerification.matches(
          order('Out for delivery', '2026-10-05T09:12:14.000000Z'),
          sentStatusId: 2,
          delivered: false,
          sentStatusLabel: 'Consignee refused the shipment',
          sentAt: sentAt,
        ),
        isFalse,
      );
    });

    test('the new reason on the shipment confirms it', () {
      expect(
        StatusVerification.matches(
          order('Consignee refused the shipment', '2026-10-05T19:09:40.000000Z'),
          sentStatusId: 2,
          delivered: false,
          sentStatusLabel: 'Consignee refused the shipment',
          sentAt: sentAt,
        ),
        isTrue,
      );
    });

    test('the same reason left from an earlier update does not count', () {
      expect(
        StatusVerification.matches(
          order('Consignee is not answering', '2026-10-04T12:00:00.000000Z'),
          sentStatusId: 2,
          delivered: false,
          sentStatusLabel: 'Consignee is not answering',
          sentAt: sentAt,
        ),
        isFalse,
      );
    });

    test('label case and spaces do not matter', () {
      expect(
        StatusVerification.matches(
          order('consignee reschedule the delivery',
              '2026-10-05T19:09:40.000000Z'),
          sentStatusId: 2,
          delivered: false,
          sentStatusLabel: 'Consignee  reschedule the delivery ',
          sentAt: sentAt,
        ),
        isTrue,
      );
    });
  });

  test('delivered keeps working with the label passed', () {
    expect(
      StatusVerification.matches(
        {
          'order': {
            'status': 'Completed',
            'status_code': 3,
            'status_label': 'Shipment delivered',
          },
        },
        sentStatusId: '3',
        delivered: true,
        sentStatusLabel: 'Shipment delivered',
        sentAt: DateTime.now(),
      ),
      isTrue,
    );
  });
}
