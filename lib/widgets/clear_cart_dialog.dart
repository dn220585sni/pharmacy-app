import 'package:flutter/material.dart';

/// Shows a confirmation dialog for clearing the cart.
/// Returns `true` if the user confirmed, `null`/`false` otherwise.
Future<bool?> showClearCartDialog({
  required BuildContext context,
  required int itemCount,
  required double cartTotal,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.shopping_cart_outlined,
                    size: 26, color: Color(0xFFEF4444)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Очистити кошик?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ви дійсно хочете очистити кошик?\n'
                '$itemCount поз. на суму '
                '${cartTotal.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        side: const BorderSide(
                            color: Color(0xFFE5E7EB)),
                      ),
                      child: const Text(
                        'Ні',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      autofocus: true,
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Так',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
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
    ),
  );
}
