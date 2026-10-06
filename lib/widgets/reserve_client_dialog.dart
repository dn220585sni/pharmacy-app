import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/money.dart';
import '../utils/reserve_label.dart';

/// Хто клієнт резерву: прізвище (≥3 літери) + телефон — обидва обов'язкові
/// (як у Єврофармі: за ними резерв шукають, коли клієнт прийде).
/// Повертає підпис «ПРІЗВИЩЕ 0XXXXXXXXX» або `null`, якщо скасовано.
/// Стиль — як у «Запит на дзвінок» (callback_request_dialog.dart).
Future<String?> showReserveClientDialog({
  required BuildContext context,
  required int itemCount,
  required double total,
  String? initialPhone,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReserveClientDialog(
      itemCount: itemCount,
      total: total,
      initialPhone: initialPhone,
    ),
  );
}

class _ReserveClientDialog extends StatefulWidget {
  const _ReserveClientDialog({
    required this.itemCount,
    required this.total,
    this.initialPhone,
  });

  final int itemCount;
  final double total;
  final String? initialPhone;

  @override
  State<_ReserveClientDialog> createState() => _ReserveClientDialogState();
}

class _ReserveClientDialogState extends State<_ReserveClientDialog> {
  static const _blue = Color(0xFF1E7DC8);
  static const _ink = Color(0xFF1C1C2E);
  static const _muted = Color(0xFF6B7280);
  static const _red = Color(0xFFDC2626);

  final _surnameCtr = TextEditingController();
  late final TextEditingController _phoneCtr;
  final _surnameFocus = FocusNode();
  final _phoneFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final p = widget.initialPhone;
    _phoneCtr = TextEditingController(
        text: p == null ? '' : (normalizeReservePhone(p) ?? ''));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _surnameFocus.requestFocus());
  }

  @override
  void dispose() {
    _surnameCtr.dispose();
    _phoneCtr.dispose();
    _surnameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  bool get _surnameOk => isValidReserveSurname(_surnameCtr.text);
  String? get _phone => normalizeReservePhone(_phoneCtr.text);
  bool get _canSave => _surnameOk && _phone != null;

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(buildReserveLabel(_surnameCtr.text, _phone!));
  }

  @override
  Widget build(BuildContext context) {
    final surnameError = _surnameCtr.text.isNotEmpty && !_surnameOk
        ? 'Не менше 3 літер'
        : null;
    final phoneError = _phoneCtr.text.isNotEmpty && _phone == null
        ? 'Номер у форматі 0XX XXX XX XX'
        : null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Заголовок ───────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.inventory_2_outlined,
                        size: 18, color: _blue),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Зберегти резерв',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close_rounded,
                        size: 20, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Що резервуємо ───────────────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_basket_outlined,
                        size: 14, color: Color(0xFF9CA3AF)),
                    const SizedBox(width: 8),
                    const Text(
                      'Кошик:',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.itemCount} поз. · '
                        '${widget.total.asMoney} ₴',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Поля ────────────────────────────────────────────────────
              _label('Прізвище покупця'),
              const SizedBox(height: 6),
              _field(
                controller: _surnameCtr,
                focusNode: _surnameFocus,
                hint: 'Не менше 3 літер',
                icon: Icons.person_outline_rounded,
                error: surnameError,
                capitalization: TextCapitalization.characters,
                onSubmitted: (_) => _phone == null
                    ? _phoneFocus.requestFocus()
                    : _save(),
              ),
              const SizedBox(height: 12),
              _label('Телефон'),
              const SizedBox(height: 6),
              _field(
                controller: _phoneCtr,
                focusNode: _phoneFocus,
                hint: '0XX XXX XX XX',
                icon: Icons.phone_outlined,
                error: phoneError,
                keyboardType: TextInputType.phone,
                formatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d+ ()-]')),
                ],
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 10),
              const Text(
                'Без оплати й без чека. За прізвищем або телефоном резерв '
                'знайдуть у «Витратах по касі» і проведуть кнопкою «Відкрити '
                'в касі».',
                style: TextStyle(color: _muted, fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 16),

              // ── Кнопки ──────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F5F8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Скасувати',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MouseRegion(
                      cursor: _canSave
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      child: GestureDetector(
                        onTap: _canSave ? _save : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 38,
                          decoration: BoxDecoration(
                            color: _canSave
                                ? _blue
                                : const Color(0xFFF4F5F8),
                            borderRadius: BorderRadius.circular(8),
                            border: _canSave
                                ? null
                                : Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 14,
                                  color: _canSave
                                      ? Colors.white
                                      : const Color(0xFFB0B7C3)),
                              const SizedBox(width: 6),
                              Text(
                                'Зберегти резерв',
                                style: TextStyle(
                                  color: _canSave
                                      ? Colors.white
                                      : const Color(0xFFB0B7C3),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF374151),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onSubmitted,
    String? error,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    List<TextInputFormatter>? formatters,
  }) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c),
        );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      inputFormatters: formatters,
      onChanged: (_) => setState(() {}),
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 13, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB0B7C3)),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 10, right: 6),
          child: Icon(icon, size: 16, color: const Color(0xFF9CA3AF)),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        errorText: error,
        errorStyle: const TextStyle(fontSize: 11, color: _red),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        border: border(const Color(0xFFE5E7EB)),
        enabledBorder: border(const Color(0xFFE5E7EB)),
        focusedBorder: border(_blue),
        errorBorder: border(const Color(0xFFFCA5A5)),
        focusedErrorBorder: border(_red),
      ),
    );
  }
}
