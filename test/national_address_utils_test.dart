import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/utils/national_address_utils.dart';

void main() {
  group('NationalAddressUtils.normalize', () {
    test('upper-cases and removes spaces and dashes', () {
      expect(NationalAddressUtils.normalize(' rrrd 2929 '), 'RRRD2929');
      expect(NationalAddressUtils.normalize('RRRD-2929'), 'RRRD2929');
    });

    test('converts Arabic-Indic digits', () {
      expect(NationalAddressUtils.normalize('RRRD٢٩٢٩'), 'RRRD2929');
      expect(NationalAddressUtils.normalize('RRRD۲۹۲۹'), 'RRRD2929');
    });
  });

  group('NationalAddressUtils.isValidShortAddress', () {
    test('accepts 4 letters + 4 digits', () {
      expect(NationalAddressUtils.isValidShortAddress('RRRD2929'), isTrue);
    });

    test('rejects other shapes', () {
      expect(NationalAddressUtils.isValidShortAddress('RRD2929'), isFalse);
      expect(NationalAddressUtils.isValidShortAddress('RRRD292'), isFalse);
      expect(NationalAddressUtils.isValidShortAddress('حي النرجس'), isFalse);
      expect(NationalAddressUtils.isValidShortAddress(''), isFalse);
    });
  });

  group('NationalAddressUtils.shortAddressesIn', () {
    test('finds short addresses in nested shipment data', () {
      final found = NationalAddressUtils.shortAddressesIn({
        'delivery_location_address1': 'Riyadh, rrrd 2929, King Road',
        'meta': {
          'list': ['ABCD-1234'],
        },
        'order_awb': 'SLS123456',
      });
      expect(found, {'RRRD2929', 'ABCD1234'});
    });
  });
}
