import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReservationSuccessDialog — success message after booking at another pharmacy.
// Extracted from PosScreen to reduce file size.
// ─────────────────────────────────────────────────────────────────────────────

class ReservationSuccessDialog extends StatefulWidget {
  final String drugName;
  final String pharmacyAddress;

  const ReservationSuccessDialog({
    super.key,
    required this.drugName,
    required this.pharmacyAddress,
  });

  @override
  State<ReservationSuccessDialog> createState() =>
      _ReservationSuccessDialogState();
}

class _ReservationSuccessDialogState extends State<ReservationSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _anim, curve: Curves.easeOut),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 380,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 32,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Check icon ─────────────────────────────────────────
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF6FF),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF1E7DC8).withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 34,
                      color: Color(0xFF1E7DC8),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Title ──────────────────────────────────────────────
                  const Text(
                    'Препарат успішно заброньовано',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF1C1C2E),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Pharmacy address ───────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F5F8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.store_outlined,
                            size: 18, color: Color(0xFF1E7DC8)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.pharmacyAddress,
                            style: const TextStyle(
                              color: Color(0xFF4B5563),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // ── Drug name ──────────────────────────────────────────
                  Text(
                    widget.drugName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── OK button ──────────────────────────────────────────
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: double.infinity,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E7DC8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Готово',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
