import 'package:flutter/material.dart';

/// Що робити після невдалого сканування.
enum ScanFailedAction {
  /// Спробувати сканувати ту саму упаковку ще раз.
  retry,

  /// Ввести код вручну (той самий диспатч, що й сканер).
  manual,

  /// Прибрати позицію з кошика — те, що в руках, не відповідає кошику.
  removeItem,
}

/// Попап при невдалому скані під час звірки товару.
///
/// Сканування обовʼязкове для кожного продажу, тож касир не може просто
/// проігнорувати збій — потрібне свідоме рішення. Три виходи:
/// пересканувати, ввести код вручну або прибрати позицію з кошика.
///
/// [itemName] — назва незвіреної позиції, якщо вона одна: тоді «Видалити
/// позицію» однозначне. Коли незвірених кілька, кнопку видалення не
/// показуємо — інакше незрозуміло, що саме зникне з кошика.
Future<ScanFailedAction?> showScanFailedDialog({
  required BuildContext context,
  required String reason,
  String? itemName,
}) {
  return showDialog<ScanFailedAction>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      title: const Row(
        children: [
          Icon(Icons.qr_code_scanner_rounded,
              color: Color(0xFFB45309), size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Товар не розпізнано',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reason,
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 12),
          const Text(
            'Подивіться уважно, чи те ви скануєте: штрихкод має бути на тій '
            'самій упаковці, що й у кошику.',
            style: TextStyle(fontSize: 14, height: 1.35),
          ),
          if (itemName != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F8),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'Очікуємо: $itemName',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        if (itemName != null)
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ScanFailedAction.removeItem),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            child: const Text('Видалити позицію'),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ScanFailedAction.manual),
          child: const Text('Ввести вручну'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ScanFailedAction.retry),
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1E7DC8)),
          child: const Text('Сканувати ще раз'),
        ),
      ],
    ),
  );
}
