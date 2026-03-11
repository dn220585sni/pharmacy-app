import 'package:flutter/material.dart';
import '../../models/payment_method.dart';

/// Segmented toggle for choosing cash / card payment.
class PaymentMethodToggle extends StatelessWidget {
  const PaymentMethodToggle({
    super.key,
    required this.selectedMethod,
    required this.onMethodChanged,
  });

  final PaymentMethod selectedMethod;
  final ValueChanged<PaymentMethod> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          _segment(
            icon: Icons.payments_outlined,
            label: 'Готівка',
            method: PaymentMethod.cash,
            isLeft: true,
          ),
          _segment(
            icon: Icons.credit_card,
            label: 'Картка',
            method: PaymentMethod.card,
            isLeft: false,
            hotkey: 'F10',
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required IconData icon,
    required String label,
    required PaymentMethod method,
    required bool isLeft,
    String? hotkey,
  }) {
    final isActive = selectedMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => onMethodChanged(method),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: double.infinity,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1E7DC8) : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isLeft ? const Radius.circular(7) : Radius.zero,
              right: !isLeft ? const Radius.circular(7) : Radius.zero,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? Colors.white : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFF6B7280),
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (hotkey != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0x33FFFFFF)
                        : const Color(0x0F000000),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    hotkey,
                    style: TextStyle(
                      color: isActive
                          ? Colors.white
                          : const Color(0xFF9CA3AF),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
