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
  static Set<String> shortAddressesIn(Object? data) {
    final found = <String>{};
    void walk(Object? node) {
      if (node is Map) {
        node.values.forEach(walk);
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
}
