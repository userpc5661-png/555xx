import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/utils/latin_digits_formatter.dart';

void main() {
  test('converts Arabic digits to English digits', () {
    expect(LatinDigitsFormatter.convert('١٢٣٤'), '1234');
    expect(LatinDigitsFormatter.convert('۵۶۷۸'), '5678');
    expect(LatinDigitsFormatter.convert('12٣4'), '1234');
  });

  test('formatter keeps the cursor position', () {
    const formatter = LatinDigitsFormatter();
    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '١٢',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    expect(result.text, '12');
    expect(result.selection.baseOffset, 2);
  });
}
