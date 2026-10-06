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

  group('real labels sent by the driver', () {
    test('Trendyol: no sender address, customer in the To bar', () {
      final scan = LabelTextParser.parse('''
Dest. Hub DMM
Zone DMM14
3 1 0 2 6 0 6 5 6 1 3 9 1 5
From To National Address EHDB2875
Trendyol
Istanbul Street, near from Fetchr warehouse no7
fatin 'ali
EHDB2875
2875, 7156 ,32323
Order No. 9389473-24868227-1
''');
      expect(scan.shortAddresses, ['EHDB2875']);
      expect(scan.awbCandidates, contains('31026065613915'));
      expect(LabelTextParser.customerShort(scan), 'EHDB2875');
    });

    test('Hawa: sender RNMA7272, customer EHDA7265', () {
      final scan = LabelTextParser.parse('''
3 1 0 2 6 1 8 1 5 4 3 9 4 1
From National Address RNMA7272 To National Address EHDA7265
Hawa
RNMA7272
EHDA7265
7265, 6 ,32324
Order No. 5311534-24877302-1
''');
      expect(scan.shortAddresses, containsAll(['RNMA7272', 'EHDA7265']));
      expect(
        LabelTextParser.customerShort(scan, senderShort: 'RNMA7272'),
        'EHDA7265',
      );
    });

    test('Mashaer: broken body text, address read from the To bar', () {
      final scan = LabelTextParser.parse('''
3 1 0 2 6 1 9 3 0 1 7 3 5 1
From To National Address EHGB4320
Mashaer
2060 Al Hawazn S. 7067
EHGB/ 320
7320, 32333
ORD-130809-OR53378453JGX-24cc3315-3f8f-452c-8189-5bc459c75572
''');
      expect(scan.shortAddresses, ['EHGB4320']);
      expect(scan.awbCandidates, contains('31026193017351'));
    });

    test('Assaf: sender and customer', () {
      final scan = LabelTextParser.parse('''
3 1 0 2 6 1 8 2 9 2 9 2 8 1
From National Address RNMA7272 To National Address EHDG2289
Assaf RNMA7272
EHDG2289
Desc. 1* 1:LPS-125-SF-00069/
''');
      expect(scan.shortAddresses, containsAll(['RNMA7272', 'EHDG2289']));
      expect(scan.shortAddresses, hasLength(2));
    });
  });

  group('choosing without the sender from the server', () {
    test('prefers the region of the server customer address', () {
      final scan = LabelTextParser.parse('RNMA7272\nEHDA7265');
      expect(
        LabelTextParser.customerShort(scan, serverCustomerShort: 'EHDA6787'),
        'EHDA7265',
      );
    });
  });

  group('one wrong character', () {
    String labelWith(String to1, String to2, {String from = 'RNMA7272'}) => '''
From National Address $from
To National Address $to1
$from
$to2
''';

    test('both prints agree: confirmed', () {
      final read = LabelTextParser.customerRead(
        LabelTextParser.parse(labelWith('EHAC4301', 'EHAC4301')),
        senderShort: 'RNMA7272',
      )!;
      expect(read.value, 'EHAC4301');
      expect(read.confirmed, isTrue);
    });

    test('only one print read: not confirmed until a second read agrees', () {
      final read = LabelTextParser.customerRead(
        LabelTextParser.parse(labelWith('EHAC4381', 'EH#C43')),
        senderShort: 'RNMA7272',
      )!;
      expect(read.value, 'EHAC4381');
      expect(read.confirmed, isFalse);
    });

    test('a misread of the server address is that address', () {
      final read = LabelTextParser.customerRead(
        LabelTextParser.parse(labelWith('EHAC4381', 'EH#C43')),
        senderShort: 'RNMA7272',
        serverCustomerShort: 'EHAC4301',
      )!;
      expect(read.value, 'EHAC4301');
      expect(read.confirmed, isTrue);
    });

    test('both prints differ from the server by one: the label wins', () {
      final read = LabelTextParser.customerRead(
        LabelTextParser.parse(labelWith('EHAC4302', 'EHAC4302')),
        senderShort: 'RNMA7272',
        serverCustomerShort: 'EHAC4301',
      )!;
      expect(read.value, 'EHAC4302');
      expect(read.confirmed, isTrue);
    });

    test('a misread sender is not taken as the customer', () {
      final read = LabelTextParser.customerRead(
        LabelTextParser.parse(
          labelWith('EHAC4301', 'EHAC4301', from: 'RNMA7212'),
        ),
        senderShort: 'RNMA7272',
      )!;
      expect(read.value, 'EHAC4301');
    });

    test('a wrong default server address is not used', () {
      final read = LabelTextParser.customerRead(
        LabelTextParser.parse(labelWith('EHDG2289', 'EHDG2289')),
        senderShort: 'RNMA7272',
        serverCustomerShort: 'EHDA6787',
      )!;
      expect(read.value, 'EHDG2289');
      expect(read.confirmed, isTrue);
    });
  });
}
