/// Saudi National Address "short address": 4 Latin letters + 4 digits,
/// e.g. RRRD2929. This is what the official SLS driver app asks for.
class NationalAddressUtils {
  NationalAddressUtils._();

  static final RegExp _shortAddress = RegExp(r'^[A-Z]{4}[0-9]{4}$');
  static final RegExp _shortAddressInText = RegExp(
    r'(?<![A-Za-z])([A-Za-z]{4})[\s-]*([0-9]{4})(?![0-9])',
  );

  /// Turns what the driver typed into the canonical form: upper case,
  /// Latin digits, no spaces or dashes ("rrrd ٢٩٢٩" -> "RRRD2929").
  static String normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.trim().runes) {
      final char = String.fromCharCode(rune);
      // Arabic-Indic (٠-٩) and Eastern Arabic-Indic (۰-۹) digits.
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.write(rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.write(rune - 0x06F0);
      } else if (char == ' ' || char == '-' || char == '_' || rune == 0x00A0) {
        continue;
      } else {
        buffer.write(char.toUpperCase());
      }
    }
    return buffer.toString();
  }

  static bool isValidShortAddress(String normalized) =>
      _shortAddress.hasMatch(normalized);

  /// Every short address that appears anywhere in the shipment's server
  /// data, normalized. Used to refuse sending the customer's current address
  /// again, like the official app does.
  static Set<String> shortAddressesIn(
    Object? data, {
    bool skipSenderFields = false,
  }) {
    final found = <String>{};
    void walk(Object? node) {
      if (node is Map) {
        for (final entry in node.entries) {
          if (skipSenderFields && _isSenderKey(entry.key.toString())) {
            continue;
          }
          walk(entry.value);
        }
      } else if (node is Iterable) {
        node.forEach(walk);
      } else if (node is String) {
        for (final match in _shortAddressInText.allMatches(node)) {
          found.add('${match.group(1)!.toUpperCase()}${match.group(2)}');
        }
      }
    }

    walk(data);
    return found;
  }

  static final _senderKey = RegExp(
    r'(collection|pickup|merchant|store|sender|shipper|seller|origin|from|requested)',
  );

  static bool _isSenderKey(String key) => _senderKey.hasMatch(
    key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
  );

  /// The customer's short address from the shipment data, ignoring the
  /// merchant/sender address that is also printed on the label.
  static String? customerShortAddress(Map<String, dynamic> raw) {
    // SLS sends it explicitly as delivery_location_na_short.
    for (final source in [raw, raw['order']]) {
      if (source is! Map) continue;
      final value = source['delivery_location_na_short'];
      if (value is String) {
        final normalized = normalize(value);
        if (isValidShortAddress(normalized)) return normalized;
      }
    }
    final found = shortAddressesIn(raw, skipSenderFields: true);
    return found.isEmpty ? null : found.first;
  }
}
