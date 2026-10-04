import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/models/task_item.dart';
import 'package:sls_assistant_pro/services/location_correction_service.dart';

void main() {
  group('LocationCorrectionService.parse', () {
    test('parses plain coordinates', () async {
      final value = await LocationCorrectionService.parse('24.7136, 46.6753');
      expect(value, isNotNull);
      expect(value!.latitude, 24.7136);
      expect(value.longitude, 46.6753);
    });

    test('parses Google Maps at coordinates', () async {
      final value = await LocationCorrectionService.parse(
        'https://www.google.com/maps/place/Riyadh/@24.7136,46.6753,17z',
      );
      expect(value, isNotNull);
      expect(value!.latitude, 24.7136);
      expect(value.longitude, 46.6753);
    });

    test('parses Google Maps data coordinates', () async {
      final value = await LocationCorrectionService.parse(
        'https://www.google.com/maps/place/test/data=!3d24.7136!4d46.6753',
      );
      expect(value, isNotNull);
      expect(value!.latitude, 24.7136);
      expect(value.longitude, 46.6753);
    });

    test('parses Apple Maps and Waze ll links', () async {
      final apple = await LocationCorrectionService.parse(
        'https://maps.apple.com/?ll=24.7136,46.6753',
      );
      final waze = await LocationCorrectionService.parse(
        'https://www.waze.com/ul?ll=24.7136%2C46.6753&navigate=yes',
      );
      expect(apple?.latitude, 24.7136);
      expect(apple?.longitude, 46.6753);
      expect(waze?.latitude, 24.7136);
      expect(waze?.longitude, 46.6753);
    });

    test('rejects invalid coordinates', () async {
      expect(await LocationCorrectionService.parse('999, 999'), isNull);
    });

    test('does not throw for malformed copied links', () async {
      expect(
        await LocationCorrectionService.parse('copied-location-%'),
        isNull,
      );
    });
  });

  group('LocationCorrectionService local changes', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    final task = TaskItem.fromJson({
      'order_id': 7,
      'order_awb': 'SLS-777',
      'delivery_location_lat': '24.7',
      'delivery_location_lng': '46.6',
    });

    test('save notifies listeners with the new location', () async {
      final events = <LocationCorrectionChange?>[];
      void listener() => events.add(LocationCorrectionService.changes.value);
      LocationCorrectionService.changes.addListener(listener);
      addTearDown(
        () => LocationCorrectionService.changes.removeListener(listener),
      );

      await LocationCorrectionService.save(
        task,
        const CorrectedLocation(24.8, 46.7),
      );
      await LocationCorrectionService.restore(task);

      expect(events, hasLength(2));
      expect(events[0]!.shipmentKey, 'SLS-777');
      expect(events[0]!.location!.latitude, 24.8);
      expect(events[1]!.shipmentKey, 'SLS-777');
      expect(events[1]!.location, isNull);
    });

    test('effective location prefers the local correction', () async {
      await LocationCorrectionService.save(
        task,
        const CorrectedLocation(24.8, 46.7),
      );
      final effective = await LocationCorrectionService.effectiveLocation(task);
      expect(effective!.latitude, 24.8);
      expect(effective.longitude, 46.7);

      await LocationCorrectionService.restore(task);
      final original = await LocationCorrectionService.effectiveLocation(task);
      expect(original!.latitude, 24.7);
    });
  });
}
