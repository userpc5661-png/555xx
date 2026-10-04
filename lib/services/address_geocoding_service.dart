import 'package:geocoding/geocoding.dart';

import '../utils/national_address_utils.dart';
import 'location_correction_service.dart';

/// Finds a location for an address written on the shipment label (the
/// National Address short code like EHAC4301, or the full address) using
/// the phone's own geocoder: Google on Android, Apple on iOS. No API key.
class AddressGeocodingService {
  AddressGeocodingService._();

  /// Queries to try, most precise first.
  static List<String> queriesFor(String input) {
    final text = input.trim();
    if (text.isEmpty) return const [];
    final short = NationalAddressUtils.normalize(text);
    if (NationalAddressUtils.isValidShortAddress(short)) {
      return ['$short, Saudi Arabia', short];
    }
    return [
      text.contains('السعودية') || text.toLowerCase().contains('saudi')
          ? text
          : '$text, السعودية',
      text,
    ];
  }

  /// Rough bounding box of Saudi Arabia, to reject a match in another
  /// country with a similar name.
  static bool isInSaudiArabia(double lat, double lng) =>
      lat >= 16 && lat <= 32.5 && lng >= 34.4 && lng <= 55.8;

  static Future<CorrectedLocation?> locate(String input) async {
    final geocoding = Geocoding();
    for (final query in queriesFor(input)) {
      try {
        final results = await geocoding.locationFromAddress(query);
        for (final result in results) {
          if (isInSaudiArabia(result.latitude, result.longitude)) {
            return CorrectedLocation(result.latitude, result.longitude);
          }
        }
      } catch (_) {
        // No result for this query (the platform throws); try the next one.
      }
    }
    return null;
  }
}
