import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/utils/phone_prefix_formatter.dart';

String _apply(String oldText, String newText) => PhonePrefixFormatter()
    .formatEditUpdate(
      TextEditingValue(text: oldText),
      TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length)),
    )
    .text;

void main() {
  group('телефон +380', () {
    test('9 цифр приймаються', () {
      expect(_apply('+380 67123456', '+380 671234567'), '+380 671234567');
    });
    test('10-та цифра не дописується', () {
      expect(_apply('+380 671234567', '+380 6712345678'), '+380 671234567');
    });
    test('залишок штрихкоду (Катя 09.10) не потрапляє в поле', () {
      expect(_apply('+380 ', '+380 64798057843'), '+380 ');
    });
    test('вставка з нулем або з 380', () {
      expect(_apply('+380 ', '+380 0671234567'), '+380 671234567');
      expect(_apply('', '+380671234567'), '+380 671234567');
    });
  });
}
