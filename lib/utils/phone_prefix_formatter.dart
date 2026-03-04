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
      final afterCode =
          allDigits.startsWith('380') ? allDigits.substring(3) : allDigits;
      final result = prefix + afterCode;
      return TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: result.length),
      );
    }
    final afterPrefix = text.substring(prefix.length);
    final cleanAfter = afterPrefix.replaceAll(RegExp(r'\D'), '');
    final result = prefix + cleanAfter;
    final cursor =
        newValue.selection.end.clamp(prefix.length, result.length).toInt();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}
