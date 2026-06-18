import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/cash_operation.dart';
import '../models/money.dart';
import '../services/cash_service.dart';

/// Діалог службових операцій каси — внесення / винесення (інкасація).
/// Напрям → причини (GetOperKassa) → сума → збереження (SaveSumDay).
Future<void> showCashOperationDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _CashOperationDialog(),
  );
}

class _CashOperationDialog extends StatefulWidget {
  const _CashOperationDialog();

  @override
  State<_CashOperationDialog> createState() => _CashOperationDialogState();
}

class _CashOperationDialogState extends State<_CashOperationDialog> {
  static const _blue = Color(0xFF1E7DC8);
  static const _grey = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);

  CashDirection _direction = CashDirection.cashIn;
  List<String> _reasons = const [];
  String? _reason;
  bool _loadingReasons = false;
  bool _saving = false;
  final _sumCtr = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadReasons();
  }

  @override
  void dispose() {
    _sumCtr.dispose();
    super.dispose();
  }

  Future<void> _loadReasons() async {
    setState(() {
      _loadingReasons = true;
      _reason = null;
      _reasons = const [];
    });
    final list = await CashService.getReasons(_direction);
    if (!mounted) return;
    setState(() {
      _reasons = list;
      _reason = list.isNotEmpty ? list.first : null;
      _loadingReasons = false;
    });
  }

  void _setDirection(CashDirection d) {
    if (d == _direction) return;
    setState(() => _direction = d);
    _loadReasons();
  }

  bool get _canSave =>
      !_saving && _reason != null && Money.parse(_sumCtr.text).isPositive;

  Future<void> _save() async {
    final sum = Money.parse(_sumCtr.text);
    if (_reason == null || !sum.isPositive) return;
    setState(() => _saving = true);
    final ok = await CashService.saveOperation(
      direction: _direction,
      reason: _reason!,
      sum: sum,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '${_direction.label}: ${sum.format()} ₴ — збережено'
          : 'Не вдалося зберегти операцію'),
      backgroundColor: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.savings_outlined, color: _blue, size: 22),
                  const SizedBox(width: 10),
                  const Text('Операція по касі',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              _directionToggle(),
              const SizedBox(height: 14),

              const Text('Причина',
                  style: TextStyle(fontSize: 12.5, color: _grey)),
              const SizedBox(height: 6),
              _reasonField(),
              const SizedBox(height: 14),

              const Text('Сума',
                  style: TextStyle(fontSize: 12.5, color: _grey)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sumCtr,
                      autofocus: true,
                      textAlign: TextAlign.right,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
              const SizedBox(height: 18),

              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _canSave ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(_saving ? 'Збереження…' : 'Зберегти'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor: const Color(0xFFB7CFE6),
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

  Widget _directionToggle() {
    Widget seg(CashDirection d, IconData icon) {
      final active = _direction == d;
      return Expanded(
        child: GestureDetector(
          onTap: () => _setDirection(d),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: active ? _blue : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16, color: active ? Colors.white : _grey),
                const SizedBox(width: 6),
                Text(d.label,
                    style: TextStyle(
                        fontSize: 13,
                        color: active ? Colors.white : _grey,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w400)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          seg(CashDirection.cashIn, Icons.arrow_downward_rounded),
          seg(CashDirection.cashOut, Icons.arrow_upward_rounded),
        ],
      ),
    );
  }

  Widget _reasonField() {
    if (_loadingReasons) {
      return Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: const Row(
          children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Завантаження причин…',
                style: TextStyle(fontSize: 12.5, color: _grey)),
          ],
        ),
      );
    }
    if (_reasons.isEmpty) {
      return const Text('Причини недоступні',
          style: TextStyle(fontSize: 12.5, color: Color(0xFFB45309)));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: DropdownButton<String>(
        value: _reason,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: _reasons
            .map((r) => DropdownMenuItem(
                  value: r,
                  child: Text(cashReasonUa(r),
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (v) => setState(() => _reason = v),
      ),
    );
  }
}
