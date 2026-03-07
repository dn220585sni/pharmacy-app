import 'package:flutter/material.dart';
import '../models/customer_loyalty.dart';
import '../utils/phone_prefix_formatter.dart';

/// Loyalty-card phone input with Ок / Попередній action buttons.
class CustomerAuthCard extends StatelessWidget {
  const CustomerAuthCard({
    super.key,
    required this.phoneController,
    required this.phoneFocusNode,
    required this.loyalty,
    required this.isLoadingLoyalty,
    required this.previousCustomerPhone,
    required this.onConfirmPhone,
    required this.onRecallPrevious,
    required this.onResetLoyalty,
  });

  /// Prefix that the phone field always starts with.
  static const loyaltyPhonePrefix = '+380 ';

  final TextEditingController phoneController;
  final FocusNode phoneFocusNode;
  final CustomerLoyalty? loyalty;
  final bool isLoadingLoyalty;
  final String? previousCustomerPhone;
  final VoidCallback onConfirmPhone;
  final VoidCallback onRecallPrevious;
  final VoidCallback onResetLoyalty;

  @override
  Widget build(BuildContext context) {
    final hasLoyalty = loyalty != null;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Header row ─────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E7DC8),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'ЛАЙК',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Номер клієнта',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (hasLoyalty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF10B981), size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '${loyalty!.bonusBalance.toStringAsFixed(0)} бонусів',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Phone input + action buttons in a row ─────────────────
            Builder(builder: (context) {
              final phoneDigits = phoneController.text
                  .substring(loyaltyPhonePrefix.length)
                  .replaceAll(RegExp(r'\D'), '');
              final hasDigits = phoneDigits.isNotEmpty;
              final canConfirm = phoneDigits.length >= 9 &&
                  !hasLoyalty &&
                  !isLoadingLoyalty;

              return SizedBox(
                height: 34,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: phoneController,
                        focusNode: phoneFocusNode,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [PhonePrefixFormatter()],
                        onSubmitted: (_) => onConfirmPhone(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1C1C2E),
                        ),
                        decoration: InputDecoration(
                          hintText: '+380 __ ___ __ __',
                          hintStyle: const TextStyle(
                              color: Color(0xFFB0B7C3), fontSize: 13),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 10, right: 6),
                            child: Icon(Icons.phone_outlined,
                                size: 15, color: Color(0xFF9CA3AF)),
                          ),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 0, minHeight: 0),
                          suffixIcon: isLoadingLoyalty
                              ? const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF1E7DC8),
                                    ),
                                  ),
                                )
                              : hasLoyalty
                                  ? GestureDetector(
                                      onTap: onResetLoyalty,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.close_rounded,
                                            size: 16,
                                            color: Color(0xFFB0B7C3)),
                                      ),
                                    )
                                  : null,
                          filled: true,
                          fillColor: hasLoyalty
                              ? const Color(0xFFF0FDF4)
                              : const Color(0xFFF9FAFB),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: hasLoyalty
                                  ? const Color(0xFF10B981)
                                      .withValues(alpha: 0.4)
                                  : const Color(0xFFDDE1F5),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFF1E7DC8)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildAuthActionButton(
                      label: 'Ок',
                      icon: Icons.check_rounded,
                      enabled: canConfirm,
                      primary: true,
                      onTap: onConfirmPhone,
                      hotkey: 'Enter',
                    ),
                    // «Попередній» — visible before user starts typing digits
                    if (!hasDigits && !hasLoyalty) ...[
                      const SizedBox(width: 4),
                      _buildAuthActionButton(
                        label: 'Попередній',
                        icon: Icons.history_rounded,
                        enabled: previousCustomerPhone != null &&
                            !isLoadingLoyalty,
                        primary: false,
                        onTap: onRecallPrevious,
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthActionButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required bool primary,
    required VoidCallback onTap,
    String? hotkey,
  }) {
    final Color bg = !enabled
        ? const Color(0xFFF4F5F8)
        : primary
            ? const Color(0xFF1E7DC8)
            : const Color(0xFFF4F5F8);
    final Color fg = !enabled
        ? const Color(0xFFB0B7C3)
        : primary
            ? Colors.white
            : const Color(0xFF6B7280);
    final Color borderColor = !enabled
        ? const Color(0xFFE5E7EB)
        : primary
            ? const Color(0xFF1E7DC8)
            : const Color(0xFFE5E7EB);

    return GestureDetector(
      onTap: enabled ? onTap : null,
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
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hotkey != null && enabled) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: primary
                      ? const Color(0x33FFFFFF)
                      : const Color(0x0F000000),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  hotkey,
                  style: TextStyle(
                    color: fg,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
