import 'package:flutter/material.dart';
import '../models/edk_offer.dart';

/// Right-panel card proposing a pharmaceutical substitution (ЄДК).
class EdkPanel extends StatelessWidget {
  final EdkOffer offer;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;

  const EdkPanel({
    super.key,
    required this.offer,
    required this.onAdd,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final drug = offer.drug;
    final bonus = drug.pharmacistBonus;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF0F7FF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E7DC8),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Є дещо краще',
                    style: TextStyle(
                      color: Color(0xFF1E7DC8),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onDismiss,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0ECFA),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF1E7DC8),
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable body ────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                children: [
                  // Image
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: drug.imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Image.network(
                              drug.imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stack) =>
                                  _placeholderIcon(),
                            ),
                          )
                        : _placeholderIcon(),
                  ),
                  const SizedBox(height: 14),

                  // Name
                  Text(
                    drug.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF1C1C2E),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Manufacturer + category
                  Text(
                    '${drug.manufacturer} · ${drug.category}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Price row + bonus
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                        style: const TextStyle(
                          color: Color(0xFF1C1C2E),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (bonus != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFEF3C7),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$bonus',
                              style: const TextStyle(
                                color: Color(0xFFB45309),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Description
                  Text(
                    offer.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Script block
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF1E7DC8).withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 16,
                          color: Color(0xFF1E7DC8),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            offer.script,
                            style: const TextStyle(
                              color: Color(0xFF1E5A8A),
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom buttons ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                // Add to cart
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    width: double.infinity,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E7DC8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_shopping_cart_rounded,
                            color: Colors.white, size: 17),
                        SizedBox(width: 7),
                        Text(
                          'Додати в кошик',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 8),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x33FFFFFF),
                            borderRadius: BorderRadius.all(Radius.circular(3)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            child: Text(
                              'Enter',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Dismiss
                GestureDetector(
                  onTap: onDismiss,
                  child: Container(
                    width: double.infinity,
                    height: 36,
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ні, дякую',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 6),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x0F000000),
                            borderRadius: BorderRadius.all(Radius.circular(3)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            child: Text(
                              'Esc',
                              style: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
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

  Widget _placeholderIcon() {
    return const Center(
      child: Icon(
        Icons.medication_rounded,
        size: 44,
        color: Color(0xFFD1D5DB),
      ),
    );
  }
}
