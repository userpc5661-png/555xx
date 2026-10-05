import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/utils/shipment_pieces.dart';

void main() {
  // Shape from /tasks for a real 5-piece shipment.
  final task = {
    'type': 'delivery',
    'order': {
      'order_id': '41026119481822',
      'quantity': 5,
      'sub_tracking_numbers': [
        for (var i = 1; i <= 5; i++)
          {'order_id': 41026119481822, 'sub_tracking_number': '41026119481822-$i'},
      ],
    },
  };

  test('reads the pieces from sub_tracking_numbers', () {
    expect(ShipmentPieces.of(task, '41026119481822'), [
      for (var i = 1; i <= 5; i++) '41026119481822-$i',
    ]);
  });

  test('falls back to the quantity', () {
    expect(
      ShipmentPieces.of({'order': {'quantity': 3}}, '410'),
      ['410-1', '410-2', '410-3'],
    );
  });

  test('single piece needs no piece scan', () {
    expect(ShipmentPieces.of({'order': {'quantity': 1}}, '410'), isEmpty);
    expect(ShipmentPieces.of({'quantity': '1'}, '410'), isEmpty);
  });

  test('delivery is blocked until every piece is scanned', () {
    const awb = '41026119481822';
    final pieces = ShipmentPieces.of(task, awb);
    ShipmentPieces.reset(awb);
    expect(ShipmentPieces.match(awb, pieces), isNull);
    expect(ShipmentPieces.match('99-1', pieces), isNull);
    for (var i = 1; i <= 4; i++) {
      ShipmentPieces.markScanned(awb, ShipmentPieces.match('$awb-$i', pieces)!);
    }
    ShipmentPieces.markScanned(awb, '$awb-4'); // scanned twice
    expect(ShipmentPieces.missing(awb, pieces), ['$awb-5']);
    // Arabic digits typed by hand.
    final typed = ShipmentPieces.match('٤١٠٢٦١١٩٤٨١٨٢٢-٥', pieces);
    expect(typed, '$awb-5');
    ShipmentPieces.markScanned(awb, typed!);
    expect(ShipmentPieces.missing(awb, pieces), isEmpty);
  });
}
