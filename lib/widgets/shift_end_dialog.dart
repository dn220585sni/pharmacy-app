import 'package:flutter/material.dart';
import '../models/shift_state.dart';
import '../services/shift_service.dart';

/// Вибір користувача в попапі завершення зміни.
enum ShiftEndChoice {
  /// Так — закрити зміну (Z-звіт) і вийти.
  closeShift,

  /// Ні — лише вийти без Z-звіту (напр. перезапуск програми).
  justExit,

  /// Скасувати — лишитись у програмі.
  cancel,
}

/// Попап «Завершення зміни» — показується при спробі закрити програму
/// (хрестик), якщо зміна відкрита.
Future<ShiftEndChoice> showShiftEndDialog(BuildContext context) async {
  final choice = await showDialog<ShiftEndChoice>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _ShiftEndDialog(),
  );
  return choice ?? ShiftEndChoice.cancel;
}

class _ShiftEndDialog extends StatelessWidget {
  const _ShiftEndDialog();

  static const _grey = Color(0xFF6B7280);

  String _fmtDuration(Duration? d) {
    if (d == null) return '—';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '$h год ${m.toString().padLeft(2, '0')} хв';
  }

  @override
  Widget build(BuildContext context) {
    final ShiftState st = ShiftService.state;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.logout_rounded,
                      color: Color(0xFF1E7DC8), size: 22),
                  const SizedBox(width: 10),
                  const Text('Завершення зміни',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Ви закінчуєте робочу зміну?',
                style: const TextStyle(fontSize: 13.5, color: _grey),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  _metric('Чеків', '${st.checksCount}'),
                  const SizedBox(width: 10),
                  _metric('Готівка в касі', st.cashInBox.format()),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _metric('Безготівка', st.cashlessTotal.format()),
                  const SizedBox(width: 10),
                  _metric('Тривалість', _fmtDuration(st.duration)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('До інкасації',
                        style: TextStyle(fontSize: 13, color: _grey)),
                    const Spacer(),
                    Text('${st.cashInBox.format()} ₴',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(ShiftEndChoice.closeShift),
                  icon: const Icon(Icons.description_outlined, size: 19),
                  label: const Text('Так, закрити зміну (Z-звіт)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(ShiftEndChoice.justExit),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _grey,
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Ні, лише вийти'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(ShiftEndChoice.cancel),
                      child: const Text('Скасувати'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 12, color: _grey)),
              const SizedBox(height: 3),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}
