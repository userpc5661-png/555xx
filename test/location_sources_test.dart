import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/services/location_correction_service.dart';
import 'package:sls_assistant_pro/utils/location_sources.dart';

void main() {
  test('finds paired fields, combined values and maps links', () {
    final sources = LocationSources.find({
      'delivery_location_lat': '24.7136',
      'delivery_location_lng': 46.6753,
      'delivery_lat_long': '24.8000, 46.7000',
      'collection_location': {'lat': 24.6, 'lng': 46.5},
      'notes': 'موقعي https://www.google.com/maps?q=24.9,46.8 شكرا',
      'short': 'https://maps.app.goo.gl/AbCd123',
      'cod_amount': '125.50, 3',
    });

    final paths = sources.map((s) => s.path).toList();
    expect(paths, contains('delivery_location_lat / delivery_location_lng'));
    expect(paths, contains('delivery_lat_long'));
    expect(paths, contains('collection_location.lat / lng'));
    expect(paths, contains('notes'));
    expect(paths, contains('short'));
    expect(paths, isNot(contains('cod_amount')));

    final link = sources.firstWhere((s) => s.path == 'short');
    expect(link.isLinkOnly, isTrue);
    final notes = sources.firstWhere((s) => s.path == 'notes');
    expect(notes.location!.latitude, 24.9);
  });

  test('ignores zero coordinates', () {
    expect(
      LocationSources.find({'lat': 0, 'lng': 0}),
      isEmpty,
    );
  });

  test('distance is roughly right', () {
    final d = LocationSources.distanceMeters(
      const CorrectedLocation(24.7136, 46.6753),
      const CorrectedLocation(24.7236, 46.6753),
    );
    expect(d, closeTo(1112, 5));
  });
}
