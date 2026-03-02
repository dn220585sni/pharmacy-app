import 'package:flutter/material.dart';
import '../models/drug.dart';
import 'drug_list_item.dart' show kColBadge;

class AnaloguesPanel extends StatelessWidget {
  final List<Drug> analogues;
  final void Function(Drug) onSelect;

  const AnaloguesPanel({
    super.key,
    required this.analogues,
    required this.onSelect,
  });

  static const double _kColPrice = 72.0;
  static const double _kColManufacturer = 82.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    const labelStyle = TextStyle(
      color: Color(0xFF9CA3AF),
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
    );

    return Container(
      color: const Color(0xFFF9FAFB),
      child: Column(
        children: [
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                const SizedBox(width: kColBadge + 10),
                const Expanded(
                  child: Text('Аналоги за діючою речовиною',
                      style: labelStyle),
                ),
                SizedBox(
                  width: _kColPrice,
                  child: const Text('Ціна',
                      textAlign: TextAlign.right, style: labelStyle),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: _kColManufacturer,
                  child: const Text('Виробник',
                      textAlign: TextAlign.right, style: labelStyle),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (analogues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.compare_arrows_rounded,
                color: Colors.grey.shade200, size: 44),
            const SizedBox(height: 10),
            const Text(
              'Аналоги відсутні',
              style: TextStyle(color: Color(0xFFB0B7C3), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: analogues.length,
      itemBuilder: (context, index) {
        final drug = analogues[index];
        return _AnalogueRow(
          drug: drug,
          isEven: index.isEven,
          onTap: () => onSelect(drug),
        );
      },
    );
  }
}

class _AnalogueRow extends StatelessWidget {
  final Drug drug;
  final bool isEven;
  final VoidCallback onTap;

  const _AnalogueRow({
    required this.drug,
    required this.isEven,
    required this.onTap,
  });

  static const double _kColPrice = 72.0;
  static const double _kColManufacturer = 82.0;

  Widget _buildBadge() {
    // Priority: inTransit → expired/expiringSoon → ownBrand → bonus → none
    if (drug.isInTransit) {
      return _BadgeBox(
        color: const Color(0xFFEEEFF2),
        child: const Icon(
          Icons.local_shipping_outlined,
          size: 15,
          color: Color(0xFF94A3B8),
        ),
      );
    }

    if (drug.isExpired || drug.isExpiringSoon) {
      return _BadgeBox(
        color: const Color(0xFFF5EDED),
        child: const Icon(
          Icons.hourglass_bottom_rounded,
          size: 14,
          color: Color(0xFFAA8080),
        ),
      );
    }

    if (drug.isOwnBrand) {
      return _BadgeBox(
        color: const Color(0xFFECEEF6),
        child: drug.pharmacistBonus != null
            ? Text(
                '${drug.pharmacistBonus}',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              )
            : const Text(
                'ВТМ',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
              ),
      );
    }

    if (drug.pharmacistBonus != null) {
      return _BadgeBox(
        color: const Color(0xFFF5F0E8),
        child: Text(
          '${drug.pharmacistBonus}',
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return const SizedBox(width: kColBadge, height: 28);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDimmed =
        (drug.stock == 0 && !drug.isInTransit) || drug.isExpired;
    final Color textPrimary =
        isDimmed ? const Color(0xFFB0B7C3) : const Color(0xFF1C1C2E);
    final Color textSecondary =
        isDimmed ? const Color(0xFFCBD5E1) : const Color(0xFF6B7280);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: isEven ? Colors.white : const Color(0xFFF8F9FB),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Badge
            SizedBox(width: kColBadge, child: _buildBadge()),
            const SizedBox(width: 10),

            // Name
            Expanded(
              child: Text(
                drug.name,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Price
            SizedBox(
              width: _kColPrice,
              child: Text(
                '${drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Manufacturer
            SizedBox(
              width: _kColManufacturer,
              child: Text(
                drug.manufacturer,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeBox extends StatelessWidget {
  final Color color;
  final Widget child;

  const _BadgeBox({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kColBadge,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
