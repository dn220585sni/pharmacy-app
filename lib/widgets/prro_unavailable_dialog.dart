import 'package:flutter/material.dart';

/// ПРРО недоступний у момент оплати — чек НЕ пробито.
///
/// Чому не плашка на 3 секунди і не черга з автопробиттям (як було до
/// 11.09.2026): накладна вже збережена в базі (`SaveSgVNakl`), але це не
/// означає, що клієнт заплатив, — він міг піти, поки ПРРО лежав. Тож
/// рішення «пробити чи ні» за фармацевтом: накладна лишається резервом, і
/// коли ПРРО запрацює, її проводять вручну з «Витрат по касі». Каса сама
/// нічого не пробиває.
///
/// Вікно модальне і закривається лише кнопкою: фармацевт має ПРОЧИТАТИ, що
/// чека немає, а не пропустити це між двома кліками.
Future<void> showPrroUnavailableDialog(
  BuildContext context, {
  required String numNakl,
  String? error,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: const Icon(Icons.receipt_long_outlined,
          color: Color(0xFFDC2626), size: 36),
      title: const Text('Чек НЕ пробито — ПРРО недоступний',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 13.5, height: 1.45),
          children: [
            const TextSpan(text: 'Накладну '),
            TextSpan(
                text: '№$numNakl',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(
              text: ' збережено як резерв, фіскального чека немає.\n\n'
                  'Коли ПРРО запрацює, знайдіть цю накладну у '
                  '«Витратах по касі» (Ctrl+E) і проведіть її звідти.\n'
                  'Каса сама нічого не пробиватиме.',
            ),
            if (error != null && error.isNotEmpty)
              TextSpan(
                text: '\n\n$error',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF6B7280)),
              ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Зрозуміло'),
        ),
      ],
    ),
  );
}
