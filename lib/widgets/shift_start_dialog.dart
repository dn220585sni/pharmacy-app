import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/money.dart';
import '../services/api_config.dart';
import '../services/fiscal_log.dart';
import '../services/shift_service.dart';

/// Діалог «Початок зміни» — показується одразу після логіну фармацевта.
/// Службове внесення (розмінна монета) відкриває зміну. Поки на мок-даних.
Future<void> showShiftStartDialog(
  BuildContext context, {
  required String pharmacist,
  required Money carryover,
  bool prevZPending = false,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ShiftStartDialog(
      pharmacist: pharmacist,
      carryover: carryover,
      prevZPending: prevZPending,
    ),
  );
}

class _ShiftStartDialog extends StatefulWidget {
  final String pharmacist;
  final Money carryover;
  final bool prevZPending;
  const _ShiftStartDialog({
    required this.pharmacist,
    required this.carryover,
    required this.prevZPending,
  });

  @override
  State<_ShiftStartDialog> createState() => _ShiftStartDialogState();
}

class _ShiftStartDialogState extends State<_ShiftStartDialog> {
  late final TextEditingController _depositCtr;
  bool _starting = false;

  static const _blue = Color(0xFF1E7DC8);
  static const _grey = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    // ⚠️ Поле НЕ передзаповнюємо.
    //
    // Раніше сюди підставлявся `cash_in_box` з останнього Z — і касиру
    // лишалось натиснути «Почати зміну». Але це готівка в касі на момент Z,
    // тобто вчорашнє внесення + денна виручка − інкасація, а не розмінна
    // монета. Виміряно 31.08 по журналу: 10 825,30 → продаж готівкою 35,00 →
    // наступна пропозиція 10 860,30. Число росло само, а `startShift` робить
    // на нього ФІСКАЛЬНЕ службове внесення в ПРРО — і роздутий `cash_in_box`
    // завтра ставав новою пропозицією. Замкнене коло.
    //
    // Поки не з'ясовано правильне джерело (порожній `SumZZvit` — питання до
    // Каті), суму вводить касир: він єдиний, хто фізично перерахував касу.
    _depositCtr = TextEditingController();
    _depositCtr.addListener(_onDepositChanged);
  }

  void _onDepositChanged() => setState(() {});

  @override
  void dispose() {
    _depositCtr.removeListener(_onDepositChanged);
    _depositCtr.dispose();
    super.dispose();
  }

  /// Порожнє поле — не «нуль», а «касир ще не ввів». Свідомий 0 дозволений.
  bool get _canStart => _depositCtr.text.trim().isNotEmpty;

  Future<void> _closeWithoutShift() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Продовжити без зміни?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: const Text(
          'Ви впевнені, що хочете продовжити роботу без відкриття зміни?',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: _grey),
            child: const Text('Так, продовжити'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _start() async {
    final deposit = Money.parse(_depositCtr.text);
    // Збираємо реальні значення розмінної: за тиждень буде видно, наскільки
    // касири розходяться з `cash_in_box`, і чи можна взагалі на нього спиратись.
    FiscalLog.log('Старт зміни: касир ввів ${deposit.format()}; '
        'довідка (готівка в касі на момент Z) ${widget.carryover.format()}; '
        'різниця ${(deposit - widget.carryover).format()}');
    setState(() => _starting = true);
    final ok = await ShiftService.startShift(deposit);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _starting = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Не вдалося відкрити зміну. Спробуйте ще раз.'),
      backgroundColor: Color(0xFFDC2626),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

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
                  const Icon(Icons.login_rounded, color: _blue, size: 22),
                  const SizedBox(width: 10),
                  const Text('Початок зміни',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: _starting ? null : _closeWithoutShift,
                    icon: const Icon(Icons.close, size: 20, color: _grey),
                    tooltip: 'Продовжити без відкриття зміни',
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _infoRow(Icons.person_outline, widget.pharmacist),
              const SizedBox(height: 6),
              _infoRow(Icons.point_of_sale_outlined,
                  'Каса №${ApiConfig.ekkKodKli}'),
              const SizedBox(height: 6),
              _infoRow(Icons.calendar_today_outlined, date),
              const SizedBox(height: 14),

              if (widget.prevZPending) ...[
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFB45309), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Зміну за вчора не закрито. Під час старту буде '
                          'сформовано Z-звіт за минулий день.',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFFB45309),
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              const Text('Сума службового внесення (розмінна монета)',
                  style: TextStyle(fontSize: 12.5, color: _grey)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _depositCtr,
                      autofocus: true,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d ,.]')),
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('₴', style: TextStyle(fontSize: 16, color: _grey)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.carryover.isPositive
                    ? 'Для довідки: готівка в касі на момент останнього '
                        'Z-звіту — ${widget.carryover.format()} ₴. Це НЕ '
                        'розмінна монета: сума включає денну виручку, якщо '
                        'інкасацію не робили. Введіть те, що фактично '
                        'закладаєте в касу.'
                    : 'Введіть суму розмінної монети, яку фактично закладаєте '
                        'в касу.',
                style: const TextStyle(
                    fontSize: 11.5, color: Color(0xFF6B7280), height: 1.35),
              ),
              const SizedBox(height: 18),

              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: (_starting || !_canStart) ? null : _start,
                  icon: _starting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(_starting ? 'Відкриття зміни…' : 'Почати зміну'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 15, color: _grey),
          const SizedBox(width: 7),
          Text(text, style: const TextStyle(fontSize: 13, color: _grey)),
        ],
      );
}
