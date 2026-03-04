import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cash amount input + computed change row + bonus transfer option.
class CashChangeSection extends StatelessWidget {
  const CashChangeSection({
    super.key,
    required this.cashController,
    required this.cashFocusNode,
    required this.finalTotal,
    required this.onChanged,
    this.transferChangeToBonus = false,
    this.onTransferChangeToBonusChanged,
    this.showBonusTransfer = false,
  });

  final TextEditingController cashController;
  final FocusNode cashFocusNode;
  final double finalTotal;
  final VoidCallback onChanged;

  /// Whether "transfer change to bonus" checkbox is checked.
  final bool transferChangeToBonus;

  /// Callback when the checkbox changes.
  final ValueChanged<bool>? onTransferChangeToBonusChanged;

  /// Whether to show the bonus transfer option (only when loyalty card is linked).
  final bool showBonusTransfer;

  /// Computed change amount (null when input is empty/invalid).
  double? get _changeAmount {
    final text =
        cashController.text.replaceAll(',', '.').replaceAll(' ', '');
    final cash = double.tryParse(text);
    if (cash == null) return null;
    return cash - finalTotal;
  }

  @override
  Widget build(BuildContext context) {
    final change = _changeAmount;
    final hasChange = change != null;
    final isPositive = hasChange && change >= 0;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Сума від клієнта:',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
                const Spacer(),
                SizedBox(
                  width: 100,
                  height: 32,
                  child: TextField(
                    controller: cashController,
                    focusNode: cashFocusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                    ],
                    onChanged: (_) => onChanged(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C2E),
                    ),
                    decoration: InputDecoration(
                      suffixText: '₴',
                      suffixStyle: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 13,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFF1E7DC8)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // ── Change row — always visible, empty until amount entered ───
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    hasChange
                        ? (isPositive
                            ? Icons.check_circle_outline_rounded
                            : Icons.warning_amber_rounded)
                        : Icons.swap_horiz_rounded,
                    size: 15,
                    color: hasChange
                        ? (isPositive
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444))
                        : const Color(0xFFB0B7C3),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'Решта:',
                    style:
                        TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    hasChange
                        ? '${change.toStringAsFixed(2).replaceAll('.', ',')} ₴'
                        : '— ₴',
                    style: TextStyle(
                      color: hasChange
                          ? (isPositive
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444))
                          : const Color(0xFFB0B7C3),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // ── Bonus transfer checkbox ────────────────────────────────
            if (showBonusTransfer && hasChange && isPositive)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: GestureDetector(
                  onTap: () => onTransferChangeToBonusChanged
                      ?.call(!transferChangeToBonus),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: transferChangeToBonus,
                          onChanged: (v) =>
                              onTransferChangeToBonusChanged?.call(v ?? false),
                          activeColor: const Color(0xFF1E7DC8),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(3),
                          ),
                          side: const BorderSide(
                            color: Color(0xFFD1D5DB),
                            width: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Переказати на бонусний рахунок',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
