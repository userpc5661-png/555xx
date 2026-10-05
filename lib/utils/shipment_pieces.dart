import 'latin_digits_formatter.dart';

/// The pieces of a multi-piece shipment: one AWB, a label per piece with
/// its own code (AWB-1, AWB-2…, `sub_tracking_numbers` in /tasks and
/// orders/awb). Delivery is allowed only once every piece was scanned on
/// this device; nothing about the pieces is sent to SLS.
class ShipmentPieces {
  ShipmentPieces._();

  // awb -> piece codes scanned (kept while the app runs).
  static final Map<String, Set<String>> _scanned = {};

  static String normalize(String value) => LatinDigitsFormatter.convert(value)
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), '');

  /// The piece codes of the shipment, or empty for a single piece.
  static List<String> of(Map<String, dynamic> raw, String awb) {
    final maps = [
      raw,
      for (final key in const ['order', 'shipment', 'data'])
        if (raw[key] is Map) Map<String, dynamic>.from(raw[key] as Map),
    ];
    for (final map in maps) {
      final list = map['sub_tracking_numbers'];
      if (list is List) {
        final codes = <String>[
          for (final item in list)
            if (item is Map && item['sub_tracking_number'] != null)
              normalize('${item['sub_tracking_number']}')
            else if (item is String)
              normalize(item),
        ].where((code) => code.isNotEmpty).toSet().toList();
        if (codes.length > 1) return codes;
      }
    }
    for (final map in maps) {
      final quantity = int.tryParse('${map['quantity'] ?? ''}'.trim());
      final base = normalize(awb);
      if (quantity != null && quantity > 1 && base.isNotEmpty) {
        return [for (var i = 1; i <= quantity; i++) '$base-$i'];
      }
    }
    return const [];
  }

  /// The piece [code] names, or null when it is not one of [pieces].
  static String? match(String code, List<String> pieces) {
    final value = normalize(code);
    return pieces.contains(value) ? value : null;
  }

  static Set<String> scanned(String awb) =>
      Set.unmodifiable(_scanned[normalize(awb)] ?? const <String>{});

  static void markScanned(String awb, String piece) =>
      (_scanned[normalize(awb)] ??= <String>{}).add(normalize(piece));

  static void reset(String awb) => _scanned.remove(normalize(awb));

  static List<String> missing(String awb, List<String> pieces) {
    final done = scanned(awb);
    return [for (final piece in pieces) if (!done.contains(piece)) piece];
  }
}
