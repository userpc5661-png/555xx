import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/utils/label_text_parser.dart';

void main() {
  // Text as ML Kit would read the real label photo shared by the driver.
  const label = '''
salasa
Dest. Hub DMM
Dest. City DMM
Zone D14
2 9 0 9 2 6 1 8 2 6 2 0 4 5 5
From National Address RNMA7272
To National Address EHAC4301
Al Ezz Oud
RNMA7272
EHAC4301
4301, 8563 32314
COD SAR 0
Order No. 5169317-24758678-1
''';

  test('reads both addresses and the AWB', () {
    final scan = LabelTextParser.parse(label);
    expect(scan.shortAddresses, containsAll(['RNMA7272', 'EHAC4301']));
    expect(scan.awbCandidates, contains('290926182620455'));
  });

  test('picks the customer address by dropping the sender', () {
    final scan = LabelTextParser.parse(label);
    expect(
      LabelTextParser.customerShort(scan, senderShort: 'RNMA7272'),
      'EHAC4301',
    );
    // Without the sender it is ambiguous: the driver chooses.
    expect(LabelTextParser.customerShort(scan), isNull);
  });

  test('fixes common OCR confusions', () {
    final scan = LabelTextParser.parse('To National Address EHAC43O1\nEHAC 4301');
    expect(scan.shortAddresses, ['EHAC4301']);
  });

  test('does not take plain numbers as addresses', () {
    final scan = LabelTextParser.parse('29092618 26204455\n5169317-24758678-1');
    expect(scan.shortAddresses, isEmpty);
  });
}
