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
    this.hasLoyalty = false,
    this.bonusTransferController,
    this.bonusTransferFocusNode,
    this.onBonusTransferAmountChanged,
    this.onFocusPhone,
  });

  final TextEditingController cashController;
  final FocusNode cashFocusNode;
  final double finalTotal;
  final VoidCallback onChanged;

  /// Whether "transfer change to bonus" checkbox is checked.
  final bool transferChangeToBonus;

  /// Callback when the checkbox changes.
  final ValueChanged<bool>? onTransferChangeToBonusChanged;

  /// Whether to show the bonus transfer option at all.
  final bool showBonusTransfer;

  /// Whether a loyalty phone number is linked.
  final bool hasLoyalty;

  /// Controller for the bonus transfer amount input.
  final TextEditingController? bonusTransferController;

  /// Focus node for the bonus transfer amount input.
  final FocusNode? bonusTransferFocusNode;

  /// Callback when bonus transfer amount changes.
  final VoidCallback? onBonusTransferAmountChanged;

  /// Called when user tries to use bonus transfer without loyalty — focuses the phone input.
  final VoidCallback? onFocusPhone;

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
            // ── Bonus transfer checkbox — visible when there is positive change
            if (showBonusTransfer && hasChange && isPositive)
              _buildBonusTransferRow(context, change),
          ],
        ),
      ),
    );
  }

  Widget _buildBonusTransferRow(BuildContext context, double change) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              if (!hasLoyalty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Авторизуйте клієнта для переказу решти на бонуси'),
                    backgroundColor: Color(0xFFF59E0B),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 3),
                  ),
                );
                onFocusPhone?.call();
                return;
              }
              final newValue = !transferChangeToBonus;
              onTransferChangeToBonusChanged?.call(newValue);
              // Pre-fill with full change amount when turning on
              if (newValue && bonusTransferController != null) {
                bonusTransferController!.text =
                    change.toStringAsFixed(2).replaceAll('.', ',');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  bonusTransferFocusNode?.requestFocus();
                });
              }
            },
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: transferChangeToBonus,
                    onChanged: (v) {
                      if (!hasLoyalty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Авторизуйте клієнта для переказу решти на бонуси'),
                            backgroundColor: Color(0xFFF59E0B),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 3),
                          ),
                        );
                        onFocusPhone?.call();
                        return;
                      }
                      final newValue = v ?? false;
                      onTransferChangeToBonusChanged?.call(newValue);
                      if (newValue && bonusTransferController != null) {
                        bonusTransferController!.text =
                            change.toStringAsFixed(2).replaceAll('.', ',');
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          bonusTransferFocusNode?.requestFocus();
                        });
                      }
                    },
                    activeColor: const Color(0xFF1E7DC8),
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                    ),
                    side: BorderSide(
                      color: hasLoyalty
                          ? const Color(0xFFD1D5DB)
                          : const Color(0xFFE5E7EB),
                      width: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Переказати на бонусний рахунок',
                  style: TextStyle(
                    color: hasLoyalty
                        ? const Color(0xFF6B7280)
                        : const Color(0xFFB0B7C3),
                    fontSize: 11.5,
                  ),
                ),
                if (!hasLoyalty) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.info_outline_rounded,
                      size: 13, color: Color(0xFFB0B7C3)),
                ],
              ],
            ),
          ),
          // ── Bonus transfer amount field (editable) ─────────────────────
          if (transferChangeToBonus && bonusTransferController != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 24),
              child: Row(
                children: [
                  const Text(
                    'Сума на бонуси:',
                    style: TextStyle(
                        color: Color(0xFF6B7280), fontSize: 11.5),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 90,
                    height: 28,
                    child: TextField(
                      controller: bonusTransferController,
                      focusNode: bonusTransferFocusNode,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[\d,.]')),
                      ],
                      onChanged: (_) =>
                          onBonusTransferAmountChanged?.call(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E7DC8),
                      ),
                      decoration: InputDecoration(
                        suffixText: '₴',
                        suffixStyle: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 11,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        filled: true,
                        fillColor: const Color(0xFFF0F7FF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              const BorderSide(color: Color(0xFFBFDBFE)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              const BorderSide(color: Color(0xFFBFDBFE)),
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
            ),
        ],
      ),
    );
  }
}
