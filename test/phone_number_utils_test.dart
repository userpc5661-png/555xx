import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/utils/phone_number_utils.dart';

void main() {
  group('PhoneNumberUtils', () {
    const expectedCall = '+966501234567';
    const expectedWhatsApp = '966501234567';

    for (final input in const [
      '0501234567',
      '501234567',
      '966501234567',
      '+966501234567',
      '00966501234567',
      '05 012 345 67',
      '+966-50-123-4567',
      '+966 050 123 4567',
      '٠٥٠١٢٣٤٥٦٧',
    ]) {
      test('normalizes $input', () {
        expect(PhoneNumberUtils.normalizeSaudiMobile(input), expectedCall);
        expect(PhoneNumberUtils.whatsappDigits(input), expectedWhatsApp);
      });
    }

    test('uses the first valid number when multiple values are returned', () {
      expect(
        PhoneNumberUtils.normalizeSaudiMobile(
          '0501234567 / 0559876543',
        ),
        expectedCall,
      );
    });

    test('does not accept invalid or non-mobile values', () {
      expect(PhoneNumberUtils.normalizeSaudiMobile('0112345678'), isNull);
      expect(PhoneNumberUtils.normalizeSaudiMobile('123'), isNull);
      expect(PhoneNumberUtils.normalizeSaudiMobile(''), isNull);
    });
  });
}
