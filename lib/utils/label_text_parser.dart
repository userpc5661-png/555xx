/// What could be read from a photo of a shipment label.
class LabelScan {
  /// Short National Addresses found (e.g. EHAC4301), most frequent first.
  /// A label usually has two: the sender's (From) and the customer's (To).
  final List<String> shortAddresses;

  /// Long digit runs that may be the shipment number (AWB).
  final List<String> awbCandidates;

  final String rawText;

  /// How many times each short address was read. The customer's address
  /// is printed twice on the label, so a correct read is usually seen twice.
  final Map<String, int> counts;

  const LabelScan({
    required this.shortAddresses,
    required this.awbCandidates,
    required this.rawText,
    this.counts = const {},
  });
}

/// The customer's short address read from one label photo.
class LabelRead {
  final String value;

  /// Times it was read in this photo (after merging one-character misreads
  /// of the server's address).
  final int seen;

  /// Trustworthy on its own: both prints agree, or it is the server's own
  /// address for this customer. Otherwise a second read must agree.
  final bool confirmed;

  const LabelRead(this.value, {required this.seen, required this.confirmed});
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
    return LabelScan(
      shortAddresses: shorts,
      awbCandidates: awbs,
      rawText: text,
      counts: Map.unmodifiable(counts),
    );
  }

  /// Number of positions where two short addresses differ (same length).
  static int distance(String a, String b) {
    if (a.length != b.length) return 99;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) diff++;
    }
    return diff;
  }

  /// The customer's address among [scan]'s: drops the sender's
  /// ([senderShort], from the server's collection_location_na_short).
  /// Returns null when it is still ambiguous, so the driver chooses.
  static String? customerShort(
    LabelScan scan, {
    String? senderShort,
    String? serverCustomerShort,
  }) =>
      customerRead(
        scan,
        senderShort: senderShort,
        serverCustomerShort: serverCustomerShort,
      )?.value;

  /// Like [customerShort], with how sure the read is. OCR sometimes reads
  /// one wrong letter or digit (8/3, 1/7, C/G…):
  /// - a read one character away from the sender's is the sender misread;
  /// - a read seen once and one character away from the server's customer
  ///   address is that address misread (when both prints say it, the
  ///   label wins).
  static LabelRead? customerRead(
    LabelScan scan, {
    String? senderShort,
    String? serverCustomerShort,
  }) {
    final counts = <String, int>{};
    for (final value in scan.shortAddresses) {
      final n = scan.counts[value] ?? 1;
      if (senderShort != null && distance(value, senderShort) <= 1) continue;
      var key = value;
      if (serverCustomerShort != null &&
          n == 1 &&
          distance(value, serverCustomerShort) == 1) {
        key = serverCustomerShort;
      }
      counts[key] = (counts[key] ?? 0) + n;
    }
    final candidates = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    String? chosen;
    if (candidates.length == 1) {
      chosen = candidates.first;
    } else if (candidates.isNotEmpty && serverCustomerShort != null) {
      // The server's customer address may be a wrong default, but it is in
      // the right region (first letter, e.g. E = Eastern); the sender is
      // usually elsewhere (R = Riyadh).
      final region = serverCustomerShort[0];
      final sameRegion =
          candidates.where((value) => value.startsWith(region)).toList();
      if (sameRegion.length == 1) chosen = sameRegion.first;
    }
    if (chosen == null) return null;
    final seen = counts[chosen]!;
    return LabelRead(
      chosen,
      seen: seen,
      confirmed: seen >= 2 || chosen == serverCustomerShort,
    );
  }
}
