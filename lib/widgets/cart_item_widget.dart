import 'package:flutter/material.dart';
import '../models/cart_item.dart';

class CartItemWidget extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  /// Whether this item has been scanned (barcode confirmed).
  final bool isScanned;

  /// Callback when the pharmacist taps the price (simulates barcode scan).
  final VoidCallback? onScan;

  const CartItemWidget({
    super.key,
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    this.isScanned = false,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final canScan = onScan != null && !isScanned;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: isScanned ? const Color(0xFFEFF6FF) : const Color(0xFFF9FAFB),
        border: Border.all(
          color:
              isScanned ? const Color(0xFFBFDBFE) : const Color(0xFFE5E7EB),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Drug icon — Rx badge for prescriptions, blue checkbox when scanned
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.isPrescription
                  ? const Color(0xFFDCFCE7)
                  : isScanned
                      ? const Color(0xFFDBEAFE)
                      : const Color(0xFFE8F3FB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: item.isPrescription
                ? const Center(
                    child: Text('Rx',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF16A34A))))
                : Icon(
                    isScanned
                        ? Icons.check_box_rounded
                        : Icons.medication_rounded,
                    color: const Color(0xFF1E7DC8),
                    size: 17,
                  ),
          ),
          const SizedBox(width: 10),

          // Name and price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.drug.name,
                  style: TextStyle(
                    color: isScanned
                        ? const Color(0xFF1E7DC8)
                        : const Color(0xFF1C1C2E),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (item.isPrescription) ...[
                  Text(
                    'Доплата: ${item.prescriptionData!.copayment.toStringAsFixed(2)} ₴ × ${item.displayQty}',
                    style: const TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else
                  Text(
                    '${item.drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴ × ${item.displayQty}',
                    style: TextStyle(
                      color: isScanned
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFF9CA3AF),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Quantity controls
          Row(
            children: [
              _ControlButton(
                icon: Icons.remove_rounded,
                onTap: onDecrease,
              ),
              SizedBox(
                width: item.isFractional ? 42 : 30,
                child: Text(
                  item.displayQty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFF1C1C2E),
                    fontSize: item.isFractional ? 12 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ControlButton(
                icon: Icons.add_rounded,
                onTap: item.isFractional
                    ? (item.fractionalQty! < item.drug.unitsPerPackage!
                        ? onIncrease
                        : null)
                    : (item.quantity < item.drug.stock
                        ? onIncrease
                        : null),
              ),
            ],
          ),
          const SizedBox(width: 10),

          // Total price — tappable to simulate scan
          GestureDetector(
            onTap: canScan ? onScan : null,
            child: MouseRegion(
              cursor: canScan
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: canScan
                    ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: const Color(0xFF1E7DC8)
                                .withValues(alpha: 0.3),
                            style: BorderStyle.solid,
                          ),
                        ),
                      )
                    : null,
                child: Text(
                  '${item.total.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: isScanned
                        ? const Color(0xFF1E7DC8)
                        : const Color(0xFF1C1C2E),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Remove button
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Color(0xFFEF5350),
                size: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ControlButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFFE8F3FB)
              : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          color: enabled
              ? const Color(0xFF1E7DC8)
              : const Color(0xFFD1D5DB),
          size: 15,
        ),
      ),
    );
  }
}
