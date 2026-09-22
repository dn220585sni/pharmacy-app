import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/internet_order.dart';
import '../../services/fiscal_log.dart';

/// «Уточнення замовлення» — захист від дублювання останніх 4 цифр номера
/// (ТЗ Юлії від 21.09.2026).
///
/// Показується, коли за 4 цифрами знайдено 2+ чинних замовлень. Повертає
/// повний номер обраного замовлення або null, якщо касир скасував.
Future<String?> showOrderDuplicateDialog(
  BuildContext context, {
  required String lastDigits,
  required List<InternetOrder> duplicates,
}) {
  FiscalLog.log('ІЗ DUPL_CLARIFY_SHOWN: «$lastDigits» → '
      '${duplicates.map((o) => o.reserveNumber).join(', ')}');
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _DuplicateDialog(lastDigits: lastDigits, duplicates: duplicates),
  );
}

class _DuplicateDialog extends StatefulWidget {
  final String lastDigits;
  final List<InternetOrder> duplicates;
  const _DuplicateDialog({required this.lastDigits, required this.duplicates});

  @override
  State<_DuplicateDialog> createState() => _DuplicateDialogState();
}

class _DuplicateDialogState extends State<_DuplicateDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _ok() {
    final full = _ctrl.text.trim();
    final found = widget.duplicates.any((o) => o.reserveNumber == full);
    if (found) {
      FiscalLog.log('ІЗ DUPL_CLARIFY_OK: «${widget.lastDigits}» → №$full');
      Navigator.pop(context, full);
      return;
    }
    setState(() {
      _error = 'Замовлення не знайдено. Введіть коректний номер';
      _ctrl.clear();
    });
    _focus.requestFocus();
  }

  void _cancel() {
    FiscalLog.log('ІЗ DUPL_CLARIFY_CANCEL: «${widget.lastDigits}»');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Уточнення замовлення',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C2E),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Знайдено кілька замовлень. Введіть повний номер інтернет '
                'замовлення для уточнення',
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: Color(0xFF374151)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 15, letterSpacing: 0.5),
                onSubmitted: (_) => _ok(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: 'Повний номер замовлення',
                  hintText: '…${widget.lastDigits}',
                  errorText: _error,
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1C1C2E),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Скасувати'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _ok,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E7DC8),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('ОК'),
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
}
