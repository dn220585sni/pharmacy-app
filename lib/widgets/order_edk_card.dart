import 'package:flutter/material.dart';
import '../models/edk_offer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OrderEdkCard — inline EDK substitution card for internet orders.
// ─────────────────────────────────────────────────────────────────────────────

class OrderEdkCard extends StatelessWidget {
  final EdkOffer offer;
  final VoidCallback onAcceptPackage;
  final VoidCallback? onAcceptBlister;
  final VoidCallback onDismiss;

  const OrderEdkCard({
    super.key,
    required this.offer,
    required this.onAcceptPackage,
    this.onAcceptBlister,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final drug = offer.drug;
    final bonus = drug.pharmacistBonus;
    final hasBlister = drug.unitsPerPackage != null;

    return Container(
      key: ValueKey('order_edk_${offer.donorDrugId}'),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF1E7DC8).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Є Дещо Краще',
                  style: TextStyle(
                    color: Color(0xFF1E7DC8),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (offer.promoLabel != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      offer.promoLabel!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                GestureDetector(
                  onTap: onDismiss,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: Color(0xFF9CA3AF)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Drug info row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // Image
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: drug.imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Image.network(
                            drug.imageUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stack) => const Icon(
                              Icons.medication_rounded,
                              size: 24,
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.medication_rounded,
                          size: 24,
                          color: Color(0xFFD1D5DB),
                        ),
                ),
                const SizedBox(width: 10),
                // Name + manufacturer + price
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        drug.name,
                        style: const TextStyle(
                          color: Color(0xFF1C1C2E),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        drug.manufacturer,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Price + bonus badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                      style: const TextStyle(
                        color: Color(0xFF1C1C2E),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (bonus != null) ...[
                      const SizedBox(height: 2),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFEF3C7),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$bonus',
                            style: const TextStyle(
                              color: Color(0xFFB45309),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Script block
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF1E7DC8).withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 14,
                    color: Color(0xFF1E7DC8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      offer.script,
                      style: const TextStyle(
                        color: Color(0xFF1E5A8A),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                if (hasBlister && onAcceptBlister != null) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: onAcceptBlister,
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F5F8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.grid_view_rounded,
                                size: 13, color: Color(0xFF6B7280)),
                            SizedBox(width: 5),
                            Text(
                              'Блістер',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: GestureDetector(
                    onTap: onAcceptPackage,
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E7DC8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_shopping_cart_rounded,
                              color: Colors.white, size: 13),
                          const SizedBox(width: 5),
                          const Text(
                            'Упаковку',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0x33FFFFFF),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'Enter',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Dismiss button
                GestureDetector(
                  onTap: onDismiss,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F5F8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Ні',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0x0F000000),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'Esc',
                            style: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
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
