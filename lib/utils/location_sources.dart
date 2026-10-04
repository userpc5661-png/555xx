import 'dart:math' as math;

import '../services/location_correction_service.dart';

/// One place in the shipment's server data that describes a location.
class LocationSource {
  /// Where it was found, e.g. "delivery_location_lat / delivery_location_lng".
  final String path;

  /// Null for a maps link that has no coordinates in it (e.g. a short
  /// maps.app.goo.gl link); it must be opened or resolved first.
  final CorrectedLocation? location;

  /// The original text for links and combined values.
  final String? rawText;

  const LocationSource({required this.path, this.location, this.rawText});

  bool get isLinkOnly => location == null;
}

/// Lists every location the server sent for a shipment, so the driver can
/// see them side by side and pick the right one.
class LocationSources {
  LocationSources._();

  static final _latSuffix = RegExp(r'(latitude|lat)$');
  static final _lngSuffix = RegExp(r'(longitude|long|lng|lon)$');
  static final _locationishKey = RegExp(
    r'(lat|lng|lon|coord|location|map|gps|geo|link|url|position|point|pin)',
  );
  static final _mapsLink = RegExp(
    r'https?://(?:[a-z0-9-]+\.)*(?:google\.[a-z.]+|goo\.gl|maps\.app\.goo\.gl|apple\.com|waze\.com)/\S*',
    caseSensitive: false,
  );

  static String _norm(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static bool _valid(double lat, double lng) =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180 &&
      !(lat == 0 && lng == 0);

  static List<LocationSource> find(Map<String, dynamic> raw) {
    final results = <LocationSource>[];
    final seen = <String>{};

    void add(LocationSource source) {
      final loc = source.location;
      final id = loc == null
          ? 'link:${source.rawText}'
          : '${source.path}|${loc.latitude.toStringAsFixed(6)},${loc.longitude.toStringAsFixed(6)}';
      if (seen.add(id)) results.add(source);
    }

    void walk(Object? node, String path) {
      if (node is Map) {
        // Pair "<prefix>lat" with "<prefix>lng" inside the same object.
        final lats = <String, MapEntry<String, double>>{};
        final lngs = <String, MapEntry<String, double>>{};
        for (final entry in node.entries) {
          final key = entry.key.toString();
          final norm = _norm(key);
          if (norm.contains('latlong') || norm.contains('latlng')) continue;
          final value = _number(entry.value);
          if (value == null) continue;
          if (_latSuffix.hasMatch(norm)) {
            lats[norm.replaceFirst(_latSuffix, '')] = MapEntry(key, value);
          } else if (_lngSuffix.hasMatch(norm)) {
            lngs[norm.replaceFirst(_lngSuffix, '')] = MapEntry(key, value);
          }
        }
        for (final prefix in lats.keys) {
          final lat = lats[prefix]!;
          final lng = lngs[prefix];
          if (lng == null || !_valid(lat.value, lng.value)) continue;
          add(LocationSource(
            path: '$path${lat.key} / ${lng.key}',
            location: CorrectedLocation(lat.value, lng.value),
          ));
        }
        for (final entry in node.entries) {
          final key = entry.key.toString();
          final value = entry.value;
          if (value is String) {
            _fromText(key, value, '$path$key', add);
          } else {
            walk(value, '$path$key.');
          }
        }
      } else if (node is List) {
        for (var i = 0; i < node.length; i++) {
          walk(node[i], '$path$i.');
        }
      }
    }

    walk(raw, '');
    return results;
  }

  static void _fromText(
    String key,
    String value,
    String path,
    void Function(LocationSource) add,
  ) {
    final text = value.trim();
    if (text.isEmpty) return;
    for (final match in _mapsLink.allMatches(text)) {
      final link = match.group(0)!;
      add(LocationSource(
        path: path,
        location: LocationCorrectionService.extractFromText(link),
        rawText: link,
      ));
    }
    // Plain "lat, lng" only in fields whose name says it is a location,
    // so amounts or phone numbers are never mistaken for coordinates.
    if (!_locationishKey.hasMatch(_norm(key)) || _mapsLink.hasMatch(text)) {
      return;
    }
    final location = LocationCorrectionService.extractFromText(text);
    if (location != null) {
      add(LocationSource(path: path, location: location, rawText: text));
    }
  }

  /// Great-circle distance in metres.
  static double distanceMeters(CorrectedLocation a, CorrectedLocation b) {
    const earth = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLng = rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.latitude)) *
            math.cos(rad(b.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * earth * math.asin(math.sqrt(h));
  }
}
