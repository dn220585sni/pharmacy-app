import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/money.dart';
import '../services/api_config.dart';
import '../services/shift_service.dart';

/// Діалог «Початок зміни» — показується одразу після логіну фармацевта.
/// Службове внесення (розмінна монета) відкриває зміну. Поки на мок-даних.
Future<void> showShiftStartDialog(
  BuildContext context, {
  required String pharmacist,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ShiftStartDialog(pharmacist: pharmacist),
  );
}

class _ShiftStartDialog extends StatefulWidget {
  final String pharmacist;
  const _ShiftStartDialog({required this.pharmacist});

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
    _depositCtr =
        TextEditingController(text: ShiftService.state.carryover.format());
  }

  @override
  void dispose() {
    _depositCtr.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final deposit = Money.parse(_depositCtr.text);
    setState(() => _starting = true);
    await ShiftService.startShift(deposit);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final st = ShiftService.state;
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

              if (st.prevZPending) ...[
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
              const Text(
                'Запропоновано із залишку попереднього дня — звірте з виносом '
                'останнього Z-звіту.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF9CA3AF)),
              ),
              const SizedBox(height: 18),

              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _starting ? null : _start,
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
