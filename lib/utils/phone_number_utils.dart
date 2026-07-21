/// Utilities for normalizing Saudi mobile numbers returned by the SLS API.
///
/// The server can return a number in local or international form, with spaces,
/// punctuation, Arabic digits, or multiple values in one field. This class
/// produces one canonical representation for calls and WhatsApp.
class PhoneNumberUtils {
  PhoneNumberUtils._();

  static const String _countryCode = '966';

  /// Returns the first valid Saudi mobile as `+9665XXXXXXXX`.
  static String? normalizeSaudiMobile(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    final normalizedDigits = _toWesternDigits(input);

    // Try recognizable phone-shaped fragments first. This avoids accidentally
    // joining two numbers from fields such as "050... / 055...".
    final fragments = <String>[];
    final phonePattern = RegExp(
      r'(?:\+|00)?966(?:[\s\-().]*0)?[\s\-().]*5(?:[\s\-().]*\d){8}|(?:^|\D)0?5(?:[\s\-().]*\d){8}(?:$|\D)',
    );
    for (final match in phonePattern.allMatches(normalizedDigits)) {
      final value = match.group(0);
      if (value != null && value.trim().isNotEmpty) fragments.add(value);
    }

    // Common API separators. Spaces are intentionally not separators because
    // they are often used inside a single phone number.
    fragments.addAll(normalizedDigits.split(RegExp(r'[,;/|\n]+')));
    fragments.add(normalizedDigits);

    for (final fragment in fragments) {
      final canonicalDigits = _normalizeDigits(fragment);
      if (canonicalDigits != null) return '+$canonicalDigits';
    }
    return null;
  }

  /// Canonical digits for WhatsApp, e.g. `966501234567` (without `+`).
  static String? whatsappDigits(String? input) {
    final normalized = normalizeSaudiMobile(input);
    return normalized?.substring(1);
  }

  /// Canonical URI for a phone call.
  static Uri? callUri(String? input) {
    final normalized = normalizeSaudiMobile(input);
    return normalized == null ? null : Uri(scheme: 'tel', path: normalized);
  }

  /// Candidate WhatsApp URIs ordered from native app to web fallbacks.
  static List<Uri> whatsappUris(String? input) {
    final digits = whatsappDigits(input);
    if (digits == null) return const [];
    return <Uri>[
      Uri(
        scheme: 'whatsapp',
        host: 'send',
        queryParameters: <String, String>{'phone': digits},
      ),
      Uri.https('wa.me', '/$digits'),
      Uri.https(
        'api.whatsapp.com',
        '/send',
        <String, String>{'phone': digits},
      ),
    ];
  }

  static String _toWesternDigits(String value) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value;
    for (var index = 0; index < 10; index++) {
      result = result
          .replaceAll(arabic[index], '$index')
          .replaceAll(persian[index], '$index');
    }
    return result;
  }

  static String? _normalizeDigits(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    if (digits.startsWith('00')) digits = digits.substring(2);

    // Some backends return +96605XXXXXXXX. Drop only the trunk prefix after
    // the country code; never remove zeros from the subscriber number.
    if (digits.startsWith('${_countryCode}05') && digits.length == 13) {
      digits = '$_countryCode${digits.substring(4)}';
    } else if (digits.startsWith('05') && digits.length == 10) {
      digits = '$_countryCode${digits.substring(1)}';
    } else if (digits.startsWith('5') && digits.length == 9) {
      digits = '$_countryCode$digits';
    }

    final valid = RegExp(r'^9665\d{8}$').hasMatch(digits);
    return valid ? digits : null;
  }
}
