import 'package:flutter_test/flutter_test.dart';
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
}
