import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Vertical quick-action sidebar shown on the far right of the POS screen.
// Most buttons are stubs — functionality wired later.
// ─────────────────────────────────────────────────────────────────────────────

class ActionSidebar extends StatelessWidget {
  /// Callback when "Інтернет-замовлення" button is tapped.
  final VoidCallback? onOrdersTap;

  /// Whether the orders panel is currently open (shows active state).
  final bool ordersActive;

  /// Number of urgent non-collected orders (red dot badge on button).
  final int urgentCount;

  /// Callback when "Витрати по касі" button is tapped.
  final VoidCallback? onExpensesTap;

  /// Whether the expenses panel is currently open (shows active state).
  final bool expensesActive;

  /// Callback when "е-Рецепт" button is tapped.
  final VoidCallback? onPrescriptionTap;

  /// Whether the prescription panel is currently open (shows active state).
  final bool prescriptionActive;

  const ActionSidebar({
    super.key,
    this.onOrdersTap,
    this.ordersActive = false,
    this.urgentCount = 0,
    this.onExpensesTap,
    this.expensesActive = false,
    this.onPrescriptionTap,
    this.prescriptionActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      _SidebarItem(
        icon: Icons.mail_outline_rounded,
        tooltip: 'Повідомлення',
        hotkeyLabel: 'Ctrl M',
      ),
      _SidebarItem(
        icon: Icons.shopping_bag_outlined,
        tooltip: 'Інтернет-замовлення',
        onTap: onOrdersTap,
        isActive: ordersActive,
        badgeCount: urgentCount,
        hotkeyLabel: 'Ctrl I',
      ),
      _SidebarItem(
        icon: Icons.health_and_safety_outlined,
        tooltip: 'е-Рецепт',
        onTap: onPrescriptionTap,
        isActive: prescriptionActive,
        hotkeyLabel: 'Ctrl R',
      ),
      _SidebarItem(
        tooltip: 'Пакунок малюка',
        customChild: const _SwaddledBabyIcon(),
      ),
      _SidebarItem(
        icon: Icons.receipt_long_outlined,
        tooltip: 'Витрати по касі',
        onTap: onExpensesTap,
        isActive: expensesActive,
        hotkeyLabel: 'Ctrl E',
      ),
      _SidebarItem(icon: Icons.explore_outlined, tooltip: 'Путівник'),
      _SidebarItem(
        tooltip: 'АНЦДок',
        customChild: const _AntsDocLogo(),
      ),
      _SidebarItem(
        tooltip: 'ШІ помічник',
        customChild: const _AiSparkleIcon(),
      ),
    ];

    return SizedBox(
      width: 64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _SidebarButton(item: buttons[i]),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarItem {
  final IconData? icon;
  final Widget? customChild;
  final String tooltip;
  final String? hotkeyLabel;
  final VoidCallback? onTap;
  final bool isActive;
  final int badgeCount;

  _SidebarItem({
    this.icon,
    this.customChild,
    required this.tooltip,
    this.hotkeyLabel,
    this.onTap,
    this.isActive = false,
    this.badgeCount = 0,
  }) : assert(icon != null || customChild != null);
}

// ─────────────────────────────────────────────────────────────────────────────
// Button widget
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarButton extends StatefulWidget {
  final _SidebarItem item;
  const _SidebarButton({required this.item});

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.item.isActive;
    final isHighlighted = _hovered || isActive;

    final color = isHighlighted
        ? const Color(0xFF1E7DC8)
        : const Color(0xFF9CA3AF);

    return Tooltip(
      message: widget.item.tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.item.onTap ?? () {},
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? const Color(0xFFE8F3FB)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF1E7DC8)
                        : isHighlighted
                            ? const Color(0xFFBFCBFB)
                            : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.item.hotkeyLabel != null)
                      const SizedBox(height: 2),
                    widget.item.icon != null
                        ? Icon(widget.item.icon, size: 28, color: color)
                        : _ColorFiltered(
                            color: color,
                            child: widget.item.customChild!,
                          ),
                    if (widget.item.hotkeyLabel != null) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0x0F000000),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          widget.item.hotkeyLabel!,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            height: 1,
                            color: isHighlighted
                                ? const Color(0xFF1E7DC8)
                                : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.item.badgeCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33EF4444),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${widget.item.badgeCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Applies a single [color] tint to the child via ColorFiltered.
/// Used to match custom widgets with the standard icon color states.
class _ColorFiltered extends StatelessWidget {
  final Color color;
  final Widget child;
  const _ColorFiltered({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom icon: Swaddled Baby (Пакунок малюка)
// ─────────────────────────────────────────────────────────────────────────────

class _SwaddledBabyIcon extends StatelessWidget {
  const _SwaddledBabyIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(painter: _SwaddledBabyPainter()),
    );
  }
}

class _SwaddledBabyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width / 2;

    // --- Head (circle) ---
    final headRadius = size.width * 0.19;
    final headCenter = Offset(cx, size.height * 0.22);
    canvas.drawCircle(headCenter, headRadius, paint);

    // --- Eyes (two dots) ---
    final eyePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(cx - headRadius * 0.4, headCenter.dy + headRadius * 0.1),
        1.2,
        eyePaint);
    canvas.drawCircle(
        Offset(cx + headRadius * 0.4, headCenter.dy + headRadius * 0.1),
        1.2,
        eyePaint);

    // --- Blanket body (rounded teardrop / swaddle shape) ---
    final blanketTop = headCenter.dy + headRadius * 0.5;
    final blanketBottom = size.height * 0.92;
    final blanketWidth = size.width * 0.42;

    final path = Path()
      ..moveTo(cx - blanketWidth * 0.6, blanketTop)
      ..quadraticBezierTo(
        cx - blanketWidth * 1.15,
        blanketTop + (blanketBottom - blanketTop) * 0.35,
        cx - blanketWidth * 0.25,
        blanketBottom,
      )
      ..quadraticBezierTo(cx, blanketBottom + 2, cx + blanketWidth * 0.25,
          blanketBottom)
      ..quadraticBezierTo(
        cx + blanketWidth * 1.15,
        blanketTop + (blanketBottom - blanketTop) * 0.35,
        cx + blanketWidth * 0.6,
        blanketTop,
      );

    canvas.drawPath(path, paint);

    // --- Blanket fold line (V shape across chest) ---
    final foldY = blanketTop + (blanketBottom - blanketTop) * 0.15;
    final foldPath = Path()
      ..moveTo(cx - blanketWidth * 0.55, blanketTop + 1)
      ..lineTo(cx, foldY + 2)
      ..lineTo(cx + blanketWidth * 0.55, blanketTop + 1);

    canvas.drawPath(
        foldPath,
        paint
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom icon: АНЦДок (text logo)
// ─────────────────────────────────────────────────────────────────────────────

class _AntsDocLogo extends StatelessWidget {
  const _AntsDocLogo();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'АНЦ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.1,
            color: Colors.black,
          ),
        ),
        Text(
          'Док',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            height: 1.1,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom icon: AI Sparkle (Gemini-style 4-point star)
// ─────────────────────────────────────────────────────────────────────────────

class _AiSparkleIcon extends StatelessWidget {
  const _AiSparkleIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(painter: _AiSparklePainter()),
    );
  }
}

class _AiSparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    // --- Main 4-point star (large) ---
    _drawSparkle(
      canvas,
      paint,
      center: Offset(size.width * 0.42, size.height * 0.48),
      radiusX: size.width * 0.35,
      radiusY: size.height * 0.40,
    );

    // --- Small accent star (top right) ---
    _drawSparkle(
      canvas,
      paint,
      center: Offset(size.width * 0.82, size.height * 0.17),
      radiusX: size.width * 0.13,
      radiusY: size.height * 0.15,
    );
  }

  void _drawSparkle(
    Canvas canvas,
    Paint paint, {
    required Offset center,
    required double radiusX,
    required double radiusY,
  }) {
    final path = Path();
    // Top
    path.moveTo(center.dx, center.dy - radiusY);
    // Right
    path.quadraticBezierTo(
        center.dx + radiusX * 0.12,
        center.dy - radiusY * 0.12,
        center.dx + radiusX,
        center.dy);
    // Bottom
    path.quadraticBezierTo(
        center.dx + radiusX * 0.12,
        center.dy + radiusY * 0.12,
        center.dx,
        center.dy + radiusY);
    // Left
    path.quadraticBezierTo(
        center.dx - radiusX * 0.12,
        center.dy + radiusY * 0.12,
        center.dx - radiusX,
        center.dy);
    // Back to top
    path.quadraticBezierTo(
        center.dx - radiusX * 0.12,
        center.dy - radiusY * 0.12,
        center.dx,
        center.dy - radiusY);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
