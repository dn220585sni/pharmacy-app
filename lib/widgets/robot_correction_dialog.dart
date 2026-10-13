import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/drug.dart';
import '../services/drug_service.dart';
import '../services/robot_service.dart';

/// Коригування кількості товару в комірці робота (Ctrl+R або права кнопка
/// миші на рядку). Як у старій програмі (Google-док «Редагування кількості
/// товару в комірці робота»): список комірок, швидкі «E9 −1 / E9 +1» для однієї
/// упаковки, або комірка + кількість → «Збільшити» / «Зменшити».
///
/// Комірки — з поля `robot` GetSKUprice за s-кодом («E9,G4»).
/// Коригування — `ModifyOstRobot` (oper=add/minus), Катя 13.10.
Future<void> showRobotCorrectionDialog({
  required BuildContext context,
  required Drug drug,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RobotCorrectionDialog(drug: drug),
  );
}

/// s-код партії рядка (srv_{skod}); для u-кодів / ЄДК — порожньо.
String _skodOf(Drug d) {
  if (d.id.startsWith('srv_u_') || !d.id.startsWith('srv_')) return '';
  return d.skuCode ?? d.id.substring(4);
}

/// «E9,G4» / «E9; G4» → [E9, G4].
List<String> parseRobotCells(String? raw) => (raw ?? '')
    .split(RegExp(r'[,;\s]+'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

class _RobotCorrectionDialog extends StatefulWidget {
  final Drug drug;
  const _RobotCorrectionDialog({required this.drug});

  @override
  State<_RobotCorrectionDialog> createState() => _RobotCorrectionDialogState();
}

class _RobotCorrectionDialogState extends State<_RobotCorrectionDialog> {
  final _qtyController = TextEditingController();
  final _qtyFocus = FocusNode();
  List<String> _cells = const [];
  String? _cell;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCells();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCells() async {
    final skod = _skodOf(widget.drug);
    if (skod.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Для цього рядка немає партії (s-коду) — коригувати нічого';
      });
      return;
    }
    final r = await DrugService.getStockAndPrices(skod);
    if (!mounted) return;
    final cells = parseRobotCells(r.robot);
    setState(() {
      _loading = false;
      _cells = cells;
      _cell = cells.isNotEmpty ? cells.first : null;
      if (!r.found) {
        _error = 'Не вдалося отримати комірки: ${r.error ?? "сервер не відповів"}';
      } else if (cells.isEmpty) {
        _error = 'Товару немає в комірках робота';
      }
    });
    if (cells.isNotEmpty) _qtyFocus.requestFocus();
  }

  bool _busy = false;

  Future<void> _apply(String cell, int delta) async {
    if (_busy) return;
    final skod = _skodOf(widget.drug);
    setState(() => _busy = true);
    final r = await RobotService.modifyCell(skod: skod, cell: cell, delta: delta);
    if (!mounted) return;
    setState(() => _busy = false);
    final what = '$cell ${delta > 0 ? "+" : "−"}${delta.abs()} уп.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok
            ? 'Комірку відкориговано: $what'
            : 'Коригування $what не виконано'
                '${r.message.isNotEmpty ? ": ${r.message}" : ""}'),
        backgroundColor:
            r.ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
    if (r.ok) _qtyController.clear();
  }
  void _applyTyped(int sign) {
    final cell = _cell;
    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    if (cell == null) return;
    if (qty <= 0) {
      _qtyFocus.requestFocus();
      return;
    }
    _apply(cell, sign * qty);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.drug;
    const grey = Color(0xFF6B7280);
    return AlertDialog(
      title: const Text('Коригування кількості в роботі',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.displayName,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            if (d.manufacturer.isNotEmpty)
              Text(d.manufacturer,
                  style: const TextStyle(fontSize: 12.5, color: grey)),
            if (_cells.isNotEmpty)
              Text('Комірки: ${_cells.join(", ")}',
                  style: const TextStyle(fontSize: 12.5, color: grey)),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ))
            else if (_error != null)
              Text(_error!,
                  style: const TextStyle(fontSize: 13, color: grey))
            else ...[
              // Ручне коригування: комірка + кількість упаковок.
              Row(
                children: [
                  const Text('Комірка', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _cell,
                    isDense: true,
                    items: [
                      for (final c in _cells)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _cell = v),
                  ),
                  const SizedBox(width: 16),
                  const Text('Кількість', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: _qtyController,
                      focusNode: _qtyFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'уп.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A)),
                    onPressed: _busy ? null : () => _applyTyped(1),
                    child: const Text('Збільшити'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626)),
                    onPressed: _busy ? null : () => _applyTyped(-1),
                    child: const Text('Зменшити'),
                  ),
                ],
              ),
              const Divider(height: 24),
              // Швидко на 1 упаковку — без введення кількості.
              const Text('На 1 упаковку',
                  style: TextStyle(fontSize: 12.5, color: grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in _cells) ...[
                    OutlinedButton(
                        onPressed: _busy ? null : () => _apply(c, -1),
                        child: Text('$c −1')),
                    OutlinedButton(
                        onPressed: _busy ? null : () => _apply(c, 1),
                        child: Text('$c +1')),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрити'),
        ),
      ],
    );
  }
}
