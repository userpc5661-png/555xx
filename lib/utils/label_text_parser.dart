/// What could be read from a photo of a shipment label.
class LabelScan {
  /// Short National Addresses found (e.g. EHAC4301), most frequent first.
  /// A label usually has two: the sender's (From) and the customer's (To).
  final List<String> shortAddresses;

  /// Long digit runs that may be the shipment number (AWB).
  final List<String> awbCandidates;

  final String rawText;

  const LabelScan({
    required this.shortAddresses,
    required this.awbCandidates,
    required this.rawText,
  });
}

/// Parses text recognized from a label photo. Pure Dart, so it is tested
/// without a camera.
class LabelTextParser {
  LabelTextParser._();

  static const _toLetter = {'0': 'O', '1': 'I', '5': 'S', '8': 'B', '2': 'Z', '6': 'G'};
  static const _toDigit = {
    'O': '0', 'Q': '0', 'D': '0', 'I': '1', 'L': '1', 'T': '7',
    'S': '5', 'B': '8', 'Z': '2', 'G': '6',
  };

  // 4 letter-ish + optional space/dash + 4 digit-ish characters, as a whole
  // word. OCR often confuses O/0, I/1, S/5, B/8.
  static final _shortAddress = RegExp(
    r'(?<![A-Z0-9])([A-Z0-9]{4})[\s\-]?([0-9OQDILTSBZG]{4})(?![A-Z0-9])',
  );

  static String? _fixShort(String letters, String digits) {
    final l = letters.split('').map((c) => _toLetter[c] ?? c).join();
    final d = digits.split('').map((c) => _toDigit[c] ?? c).join();
    final value = '$l$d';
    if (!RegExp(r'^[A-Z]{4}[0-9]{4}$').hasMatch(value)) return null;
    // Real letters must dominate the first half, or "29092618" style
    // numbers would be read as addresses.
    final realLetters = letters.split('').where((c) => RegExp(r'[A-Z]').hasMatch(c)).length;
    return realLetters >= 3 ? value : null;
  }

  static LabelScan parse(String text) {
    final upper = text.toUpperCase();
    final counts = <String, int>{};
    for (final match in _shortAddress.allMatches(upper)) {
      final value = _fixShort(match.group(1)!, match.group(2)!);
      if (value == null) continue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    final shorts = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    // AWBs are printed under the barcode with spaces between digits.
    final awbs = <String>[];
    for (final line in text.split('\n')) {
      final collapsed = line.replaceAllMapped(
        RegExp(r'(?<=\d)[\s.]+(?=\d)'),
        (_) => '',
      );
      for (final m in RegExp(r'\d{11,16}').allMatches(collapsed)) {
        if (!awbs.contains(m.group(0))) awbs.add(m.group(0)!);
      }
    }
    return LabelScan(shortAddresses: shorts, awbCandidates: awbs, rawText: text);
  }

  /// The customer's address among [scan]'s: drops the sender's
  /// ([senderShort], from the server's collection_location_na_short).
  /// Returns null when it is still ambiguous, so the driver chooses.
  static String? customerShort(
    LabelScan scan, {
    String? senderShort,
    String? serverCustomerShort,
  }) {
    final candidates = scan.shortAddresses
        .where((value) => value != senderShort)
        .toList();
    if (candidates.length == 1) return candidates.first;
    if (candidates.isEmpty || serverCustomerShort == null) return null;
    // The server's customer address may be a wrong default, but it is in
    // the right region (first letter, e.g. E = Eastern); the sender is
    // usually elsewhere (R = Riyadh).
    final region = serverCustomerShort[0];
    final sameRegion =
        candidates.where((value) => value.startsWith(region)).toList();
    return sameRegion.length == 1 ? sameRegion.first : null;
  }
}
