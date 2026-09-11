import 'package:flutter/material.dart';

/// Top application bar with logo and pharmacist badge.
class TopBar extends StatelessWidget {
  /// Pharmacist full name to display in the badge.
  /// null = not selected yet (shows "Оберіть фармацевта").
  final String? pharmacistName;

  /// Called when the pharmacist badge is tapped.
  final VoidCallback? onPharmacistTap;

  const TopBar({
    super.key,
    this.pharmacistName,
    this.onPharmacistTap,
  });

  /// Extract short name: "Шайхутдинова Елена Васильевна" → "Шайхутдинова О.В."
  /// Falls back to full name if parsing fails.
  String _shortName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      final surname = parts[0];
      final firstInitial = parts[1].isNotEmpty ? parts[1][0] : '';
      final secondInitial = parts[2].isNotEmpty ? parts[2][0] : '';
      return '$surname $firstInitial.$secondInitial.';
    }
    if (parts.length == 2) {
      final surname = parts[0];
      final firstInitial = parts[1].isNotEmpty ? parts[1][0] : '';
      return '$surname $firstInitial.';
    }
    return fullName;
  }

  @override
  Widget build(BuildContext context) {
    final hasPharmacist = pharmacistName != null && pharmacistName!.isNotEmpty;
    final displayName =
        hasPharmacist ? _shortName(pharmacistName!) : 'Оберіть фармацевта';

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Row(
        children: [
          // АНЦ Каса — logo image from asset
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/Logo1.png',
              height: 40,
              fit: BoxFit.contain,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onPharmacistTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: hasPharmacist
                    ? const Color(0xFFE8F3FB)
                    : const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasPharmacist
                      ? const Color(0xFF1E7DC8).withValues(alpha: 0.25)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasPharmacist
                        ? Icons.person_outline_rounded
                        : Icons.person_add_alt_1_rounded,
                    color: hasPharmacist
                        ? const Color(0xFF1E7DC8)
                        : const Color(0xFFF59E0B),
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    displayName,
                    style: TextStyle(
                      color: hasPharmacist
                          ? const Color(0xFF1E7DC8)
                          : const Color(0xFFB45309),
                      fontSize: 13,
                    ),
                  ),
                  if (hasPharmacist) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color:
                          const Color(0xFF1E7DC8).withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Help button
          GestureDetector(
            onTap: () {
              // TODO: open help / knowledge base
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Help',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
