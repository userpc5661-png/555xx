import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/services/shipment_outcome_tracker.dart';

void main() {
  test('real delivered order is delivered at actual_delivery_at', () {
    final outcome = ShipmentOutcome.classify({
      'status': 'Completed',
      'status_code': 3,
      'status_label': 'Shipment delivered',
      'actual_delivery_at': '2026-10-04 21:17:10',
      'updated_at': '2026-10-04T18:17:10.000000Z',
    });
    expect(outcome!.kind, ShipmentOutcomeKind.delivered);
    expect(outcome.at.day, 4);
    expect(outcome.at.hour, 21);
  });

  test('real cancelled return is closed', () {
    final outcome = ShipmentOutcome.classify({
      'status': 'Cancelled',
      'status_code': 4,
      'status_label': 'Order Canceled by Mohammed Arajuddin',
      'actual_delivery_at': '2026-09-30 16:03:18',
      'updated_at': '2026-10-03T13:35:47.000000Z',
    });
    expect(outcome!.kind, ShipmentOutcomeKind.closed);
  });

  test('in transit is still in progress', () {
    expect(
      ShipmentOutcome.classify({
        'status': 'In Transit',
        'status_code': 2,
        'status_label': 'In Transit',
      }),
      isNull,
    );
  });

  test('"Not delivered" is never counted as delivered', () {
    final outcome = ShipmentOutcome.classify({
      'status': 'Failed',
      'status_label': 'Not Delivered - customer absent',
    });
    expect(outcome?.kind, ShipmentOutcomeKind.closed);
  });
}
