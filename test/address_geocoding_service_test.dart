import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/services/address_geocoding_service.dart';
import 'package:sls_assistant_pro/utils/national_address_utils.dart';

void main() {
  test('short address queries are normalized', () {
    expect(
      AddressGeocodingService.queriesFor(' ehac ٤٣٠١ '),
      ['EHAC4301, Saudi Arabia', 'EHAC4301'],
    );
  });

  test('full address gets the country added once', () {
    expect(
      AddressGeocodingService.queriesFor('الدمام، حي ضاحية الملك فهد، 4301'),
      ['الدمام، حي ضاحية الملك فهد، 4301, السعودية', 'الدمام، حي ضاحية الملك فهد، 4301'],
    );
    expect(AddressGeocodingService.queriesFor('  '), isEmpty);
  });

  test('Saudi bounding box', () {
    expect(AddressGeocodingService.isInSaudiArabia(26.4, 50.1), isTrue);
    expect(AddressGeocodingService.isInSaudiArabia(40.7, -74.0), isFalse);
  });

  test('customer short address skips the sender/merchant address', () {
    final raw = {
      'collection_location': {'address1': 'RNMA7272 الرياض'},
      'merchant': {'national_address': 'RNMA7272'},
      'delivery_location_address1': 'الدمام EHAC4301',
    };
    expect(NationalAddressUtils.customerShortAddress(raw), 'EHAC4301');
  });
}
