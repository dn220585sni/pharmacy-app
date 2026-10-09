import 'package:flutter/services.dart';

/// Always keeps "+380 " prefix, only digits allowed after it.
class PhonePrefixFormatter extends TextInputFormatter {
  static const prefix = '+380 ';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;
    if (!text.startsWith(prefix)) {
      final allDigits = text.replaceAll(RegExp(r'\D'), '');
      final afterCode = _localPart(
          allDigits.startsWith('380') ? allDigits.substring(3) : allDigits);
      if (afterCode == null) return oldValue;
      final result = prefix + afterCode;
      return TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: result.length),
      );
    }
    final afterPrefix = text.substring(prefix.length);
    final cleanAfter =
        _localPart(afterPrefix.replaceAll(RegExp(r'\D'), ''));
    if (cleanAfter == null) return oldValue;
    final result = prefix + cleanAfter;
    final cursor =
        newValue.selection.end.clamp(prefix.length, result.length).toInt();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  /// Після +380 — рівно 9 цифр. Вставлене «0671234567» → «671234567».
  /// Більше 9 — не телефон (напр. залишок штрихкоду з обірваного скана,
  /// Катя 09.10: «+38064798057843»): null = зміну не приймаємо.
  static String? _localPart(String digits) {
    if (digits.length == 10 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    return digits.length <= 9 ? digits : null;
  }
}
