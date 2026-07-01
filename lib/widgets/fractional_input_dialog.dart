import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Результат ручного введення дробу: [blisters] з [total] у пакуванні.
class FractionalInput {
  final int blisters;
  final int total;
  const FractionalInput(this.blisters, this.total);
}

/// Попап ручного введення дробової кількості (F6).
/// Два поля, розділені «/»: к-сть блістерів / усього блістерів в упаковці.
/// [drugName] — назва товару, [totalPerPackage] — передзаповнення дільника
/// (з `unitsPerPackage`, якщо відоме).
Future<FractionalInput?> showFractionalInputDialog(
  BuildContext context, {
  required String drugName,
  int? totalPerPackage,
  bool totalEditable = false,
}) {
  return showDialog<FractionalInput>(
    context: context,
    builder: (_) => _FractionalInputDialog(
      drugName: drugName,
      totalPerPackage: totalPerPackage,
      totalEditable: totalEditable,
    ),
  );
}

class _FractionalInputDialog extends StatefulWidget {
  final String drugName;
  final int? totalPerPackage;
  final bool totalEditable;
  const _FractionalInputDialog({
    required this.drugName,
    this.totalPerPackage,
    this.totalEditable = false,
  });

  @override
  State<_FractionalInputDialog> createState() => _FractionalInputDialogState();
}

class _FractionalInputDialogState extends State<_FractionalInputDialog> {
  static const _blue = Color(0xFF1E7DC8);
  static const _grey = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);

  final _blistersCtr = TextEditingController();
  late final _totalCtr =
      TextEditingController(text: widget.totalPerPackage?.toString() ?? '');
  final _blistersFocus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _blistersFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _blistersCtr.dispose();
    _totalCtr.dispose();
    _blistersFocus.dispose();
    super.dispose();
  }

  void _confirm() {
    final blisters = int.tryParse(_blistersCtr.text.trim());
    final total = int.tryParse(_totalCtr.text.trim());
    if (total == null || total < 2) {
      setState(() => _error = 'Вкажіть к-сть блістерів в упаковці (≥ 2)');
      return;
    }
    if (blisters == null || blisters < 1) {
      setState(() => _error = 'Вкажіть к-сть блістерів для продажу');
      return;
    }
    if (blisters > total) {
      setState(() => _error = 'Не більше ніж $total (уся упаковка)');
      return;
    }
    Navigator.of(context).pop(FractionalInput(blisters, total));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.straighten_rounded, color: _blue, size: 20),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text('Дробова кількість',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.drugName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: _grey)),
              const SizedBox(height: 16),
              // Поля: блістерів / усього
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _numField(_blistersCtr, _blistersFocus, 'блістерів')),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('/',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w300,
                            color: _grey)),
                  ),
                  Expanded(
                      child: _numField(_totalCtr, null, 'в упаковці',
                          readOnly: !widget.totalEditable)),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFDC2626))),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _actionButton(
                    label: 'Скасувати',
                    icon: Icons.close_rounded,
                    primary: false,
                    onTap: () => Navigator.of(context).pop(),
                    hotkey: 'Esc',
                  ),
                  const SizedBox(width: 6),
                  _actionButton(
                    label: 'Додати',
                    icon: Icons.check_rounded,
                    primary: true,
                    onTap: _confirm,
                    hotkey: 'Enter',
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// Кнопка у стилі головного екрана (як «Ок / Enter» біля поля телефону).
  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool primary,
    required VoidCallback onTap,
    String? hotkey,
  }) {
    final Color bg = primary ? _blue : const Color(0xFFF4F5F8);
    final Color fg = primary ? Colors.white : _grey;
    final Color borderColor = primary ? _blue : _border;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 10.5, fontWeight: FontWeight.w600)),
            if (hotkey != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: primary
                      ? const Color(0x33FFFFFF)
                      : const Color(0x0F000000),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(hotkey,
                    style: TextStyle(
                        color: fg,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, FocusNode? focus, String label,
      {bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: _grey)),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          focusNode: focus,
          autofocus: false,
          readOnly: readOnly,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: readOnly ? _grey : null),
          onSubmitted: (_) => _confirm(),
          decoration: InputDecoration(
            isDense: true,
            filled: readOnly,
            fillColor: readOnly ? const Color(0xFFF3F4F6) : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _blue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
