import 'package:flutter/material.dart';
import '../models/cash_expense.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CallbackRequestDialog — dialog for requesting a callback to a customer.
// Extracted from ExpensesPanel to reduce file size.
// ─────────────────────────────────────────────────────────────────────────────

class CallbackRequestDialog extends StatefulWidget {
  final CashExpense expense;
  const CallbackRequestDialog({super.key, required this.expense});

  @override
  State<CallbackRequestDialog> createState() =>
      _CallbackRequestDialogState();
}

class _CallbackRequestDialogState extends State<CallbackRequestDialog> {
  final _reasonController = TextEditingController();
  final _reasonFocusNode = FocusNode();
  bool _sending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reasonFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _reasonFocusNode.dispose();
    super.dispose();
  }

  void _send() async {
    if (_reasonController.text.trim().isEmpty) return;
    setState(() => _sending = true);
    // Simulate sending
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = true;
    });
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    // Pre-filled info
    const pharmacyAddress = 'Новокузнецька, 27';
    final pharmacist = e.pharmacist;
    final receiptNum = e.receiptNumber;

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
              // Header
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
                    child: const Icon(Icons.phone_callback_outlined,
                        size: 18, color: Color(0xFF1E7DC8)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Запит на дзвінок клієнту від аптеки',
                      style: TextStyle(
                        color: Color(0xFF1C1C2E),
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

              // Pre-filled info chips
              _DialogInfoRow(
                icon: Icons.storefront_outlined,
                label: 'Аптека',
                value: pharmacyAddress,
              ),
              const SizedBox(height: 8),
              _DialogInfoRow(
                icon: Icons.person_outline_rounded,
                label: 'Фармацевт',
                value: pharmacist,
              ),
              const SizedBox(height: 8),
              _DialogInfoRow(
                icon: Icons.receipt_outlined,
                label: '№ чеку',
                value: receiptNum,
              ),
              const SizedBox(height: 16),

              // Reason textarea
              const Text(
                'Причина дзвінка',
                style: TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                focusNode: _reasonFocusNode,
                maxLines: 4,
                style:
                    const TextStyle(fontSize: 13, color: Color(0xFF1C1C2E)),
                decoration: InputDecoration(
                  hintText:
                      'Опишіть, навіщо потрібно зв\'язатись з клієнтом...',
                  hintStyle: const TextStyle(
                      fontSize: 13, color: Color(0xFF9CA3AF)),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFF1E7DC8)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Buttons
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
                      onTap: _sending || _sent ? null : _send,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 38,
                        decoration: BoxDecoration(
                          color: _sent
                              ? const Color(0xFF059669)
                              : const Color(0xFF1E7DC8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : _sent
                                ? const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_rounded,
                                          size: 15, color: Colors.white),
                                      SizedBox(width: 6),
                                      Text(
                                        'Надіслано',
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
                                      Icon(Icons.send_rounded,
                                          size: 14, color: Colors.white),
                                      SizedBox(width: 6),
                                      Text(
                                        'Надіслати запит',
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Info row used in CallbackRequestDialog.
class _DialogInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DialogInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF9CA3AF)),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF1C1C2E),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
