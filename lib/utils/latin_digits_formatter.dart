import 'package:flutter/services.dart';

/// Converts Arabic-Indic (٠-٩) and Eastern Arabic-Indic (۰-۹) digits to
/// English digits as the user types, keeping the cursor where it was.
class LatinDigitsFormatter extends TextInputFormatter {
  const LatinDigitsFormatter();

  static String convert(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.write(rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.write(rune - 0x06F0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final converted = convert(newValue.text);
    if (converted == newValue.text) return newValue;
    // Each Arabic digit is one UTF-16 unit, like its English digit, so the
    // selection offsets stay valid.
    return newValue.copyWith(text: converted);
  }
}
