// Extracted from expenses_panel.dart — Return Flow Dialog
// Full return flow with item checkboxes, category, SMS verification.

import 'package:flutter/material.dart';
import '../models/cash_expense.dart';

// ═════════════════════════════════════════════════════════════════════════════
// RETURN FLOW DIALOG
// ═════════════════════════════════════════════════════════════════════════════

/// Return categories for the return flow.
const _returnCategories = [
  'Помилка при продажу',
  'Клієнт передумав',
  'Дефект / пошкодження',
  'Невідповідність опису',
  'Алергічна реакція',
  'Інше',
];

/// Dialog: full return flow with item checkboxes, category, SMS verification.
class ReturnFlowDialog extends StatefulWidget {
  final CashExpense expense;
  const ReturnFlowDialog({super.key, required this.expense});

  @override
  State<ReturnFlowDialog> createState() => _ReturnFlowDialogState();
}

class _ReturnFlowDialogState extends State<ReturnFlowDialog> {
  late List<bool> _checked;
  String? _selectedCategory;
  final _smsController = TextEditingController();
  final _smsFocusNode = FocusNode();
  bool _smsSent = false;
  bool _smsSending = false;
  bool _smsVerified = false;
  bool _smsVerifying = false;
  bool _returning = false;
  bool _returned = false;

  List<ExpenseItem> get _realItems =>
      widget.expense.items.where((i) => i.sku.isNotEmpty).toList();

  bool get _hasChecked => _checked.any((c) => c);

  bool get _canSubmit =>
      _hasChecked &&
      _selectedCategory != null &&
      _smsVerified &&
      !_returning &&
      !_returned;

  @override
  void initState() {
    super.initState();
    // All items pre-checked
    _checked = List.filled(_realItems.length, true);
  }

  @override
  void dispose() {
    _smsController.dispose();
    _smsFocusNode.dispose();
    super.dispose();
  }

  void _sendSms() async {
    setState(() => _smsSending = true);
    // Simulate SMS send
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _smsSending = false;
      _smsSent = true;
    });
    _smsFocusNode.requestFocus();
  }

  void _verifySms() async {
    final code = _smsController.text.trim();
    if (code.length != 4) return;
    setState(() => _smsVerifying = true);
    // Simulate verification
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _smsVerifying = false;
      _smsVerified = true;
    });
  }

  void _submitReturn() async {
    if (!_canSubmit) return;
    setState(() => _returning = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _returning = false;
      _returned = true;
    });
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.assignment_return_outlined,
                        size: 18, color: Color(0xFFEF4444)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Повернення товару',
                          style: TextStyle(
                            color: Color(0xFF1C1C2E),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Чек №${widget.expense.receiptNumber}',
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close_rounded,
                        size: 20, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
            const Divider(
                height: 20, thickness: 1, color: Color(0xFFE5E7EB)),

            // ── Scrollable content ──
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                shrinkWrap: true,
                children: [
                  // Items with checkboxes
                  const Text(
                    'Товари для повернення',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._buildItemCheckboxes(),
                  const SizedBox(height: 16),

                  // Return category
                  const Text(
                    'Причина повернення',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCategorySelector(),
                  const SizedBox(height: 16),

                  // SMS verification
                  const Text(
                    'Підтвердження SMS-кодом',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSmsSection(),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ── Footer buttons ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                border:
                    Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F5F8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFE5E7EB)),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Скасувати',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _canSubmit ? _submitReturn : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 40,
                        decoration: BoxDecoration(
                          color: _returned
                              ? const Color(0xFF059669)
                              : _canSubmit
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: _returning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : _returned
                                ? const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_rounded,
                                          size: 15, color: Colors.white),
                                      SizedBox(width: 6),
                                      Text(
                                        'Повернено',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                          Icons
                                              .assignment_return_outlined,
                                          size: 14,
                                          color: Colors.white),
                                      SizedBox(width: 6),
                                      Text(
                                        'Повернути товар',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildItemCheckboxes() {
    final items = _realItems;
    return List.generate(items.length, (i) {
      final item = items[i];
      final totalStr = item.total.toStringAsFixed(2).replaceAll('.', ',');
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: _checked[i]
              ? const Color(0xFFF0FDF4)
              : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _checked[i]
                ? const Color(0xFFBBF7D0)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _checked[i] = !_checked[i]),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _checked[i],
                    onChanged: (v) =>
                        setState(() => _checked[i] = v ?? false),
                    activeColor: const Color(0xFF059669),
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          color: _checked[i]
                              ? const Color(0xFF1C1C2E)
                              : const Color(0xFF9CA3AF),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.manufacturer != null)
                        Text(
                          '${item.manufacturer} · ${item.quantity} шт.',
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$totalStr ₴',
                  style: TextStyle(
                    color: _checked[i]
                        ? const Color(0xFF1C1C2E)
                        : const Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildCategorySelector() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          hint: const Text(
            'Оберіть причину повернення',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF)),
          ),
          icon: const Icon(Icons.expand_more_rounded,
              size: 18, color: Color(0xFF9CA3AF)),
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF1C1C2E),
            fontWeight: FontWeight.w500,
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(10),
          onChanged: (v) => setState(() => _selectedCategory = v),
          items: _returnCategories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildSmsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SMS code row
        Row(
          children: [
            // Code input
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _smsController,
                  focusNode: _smsFocusNode,
                  enabled: _smsSent && !_smsVerified,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C2E),
                    letterSpacing: 6,
                  ),
                  textAlign: TextAlign.center,
                  onChanged: (v) {
                    setState(() {}); // Update UI
                    if (v.length == 4) _verifySms();
                  },
                  decoration: InputDecoration(
                    hintText: '• • • •',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFFD1D5DB),
                      letterSpacing: 6,
                    ),
                    counterText: '',
                    filled: true,
                    fillColor: _smsVerified
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFF9FAFB),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _smsVerified
                            ? const Color(0xFF059669)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFF1E7DC8)),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    suffixIcon: _smsVerified
                        ? const Icon(Icons.check_circle_rounded,
                            size: 18, color: Color(0xFF059669))
                        : _smsVerifying
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF1E7DC8),
                                  ),
                                ),
                              )
                            : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send SMS button
            GestureDetector(
              onTap: _smsSent || _smsSending ? null : _sendSms,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 36,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _smsSent
                      ? const Color(0xFFF4F5F8)
                      : const Color(0xFF1E7DC8),
                  borderRadius: BorderRadius.circular(8),
                  border: _smsSent
                      ? Border.all(color: const Color(0xFFE5E7EB))
                      : null,
                ),
                alignment: Alignment.center,
                child: _smsSending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _smsSent
                                ? Icons.check_rounded
                                : Icons.sms_outlined,
                            size: 14,
                            color: _smsSent
                                ? const Color(0xFF059669)
                                : Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _smsSent ? 'Надіслано' : 'Надіслати SMS',
                            style: TextStyle(
                              color: _smsSent
                                  ? const Color(0xFF6B7280)
                                  : Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
        if (!_smsSent)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Натисніть "Надіслати SMS" для отримання коду підтвердження',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10.5,
              ),
            ),
          ),
        if (_smsVerified)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(Icons.verified_rounded,
                    size: 13, color: Color(0xFF059669)),
                SizedBox(width: 4),
                Text(
                  'Код підтверджено',
                  style: TextStyle(
                    color: Color(0xFF059669),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
