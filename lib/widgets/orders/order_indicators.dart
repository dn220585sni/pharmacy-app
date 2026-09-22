import 'package:flutter/material.dart';

import '../../models/order_extras.dart';

/// Миготіння дочірнього віджета (колірний blink, ТЗ §6). Коли [active] ==
/// false — дитина показується як є, без анімації.
class Blink extends StatefulWidget {
  final bool active;
  final Widget child;
  const Blink({super.key, required this.active, required this.child});

  @override
  State<Blink> createState() => _BlinkState();
}

class _BlinkState extends State<Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(Blink old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.25).animate(_ctrl),
      child: widget.child,
    );
  }
}

/// Маленька плашка з іконкою і текстом (рядок замовлення, шапка списку).
class OrderPill extends StatelessWidget {
  final IconData? icon;
  final String? text;
  final Color color;
  final Color background;
  final Color border;
  final String? tooltip;
  final VoidCallback? onTap;

  const OrderPill({
    super.key,
    this.icon,
    this.text,
    required this.color,
    required this.background,
    required this.border,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 11, color: color),
          if (icon != null && text != null) const SizedBox(width: 3),
          if (text != null)
            Text(
              text!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
        ],
      ),
    );
    if (onTap != null) {
      w = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: w),
      );
    }
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// Конверт переписки з кол-центром: синій — є переписка, з крапкою — є
/// непрочитане.
class MessageEnvelope extends StatelessWidget {
  final bool unread;
  final VoidCallback? onTap;
  const MessageEnvelope({super.key, required this.unread, this.onTap});

  @override
  Widget build(BuildContext context) {
    return OrderPill(
      icon: unread ? Icons.mark_email_unread_rounded : Icons.mail_outline_rounded,
      text: unread ? 'Нове' : null,
      color: const Color(0xFF1E7DC8),
      background: unread ? const Color(0xFFE8F3FB) : Colors.white,
      border: const Color(0xFFBFDBFE),
      tooltip: unread
          ? 'Нове повідомлення від кол-центру'
          : 'По замовленню є переписка з кол-центром',
      onTap: onTap,
    );
  }
}

/// Годинник часу на збір: червоний — час спливає, миготить — час вичерпано.
class SlaBadge extends StatelessWidget {
  final OrderSla sla;
  const SlaBadge({super.key, required this.sla});

  @override
  Widget build(BuildContext context) {
    if (sla == OrderSla.none) return const SizedBox.shrink();
    final overdue = sla == OrderSla.overdue;
    return Blink(
      active: overdue,
      child: OrderPill(
        icon: Icons.timer_outlined,
        text: overdue ? 'Час вийшов' : 'Час спливає',
        color: overdue ? Colors.white : const Color(0xFFDC2626),
        background: overdue ? const Color(0xFFDC2626) : const Color(0xFFFEE2E2),
        border: overdue ? const Color(0xFFDC2626) : const Color(0xFFFECACA),
        tooltip: overdue
            ? 'Нормативний час на збір замовлення вичерпано'
            : 'Нормативний час на збір замовлення спливає',
      ),
    );
  }
}

/// Кругла галочка автопідтвердження (ТЗ §6).
class AutoConfirmMark extends StatelessWidget {
  final double size;
  const AutoConfirmMark({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Автопідтвердження: термінового збору не потребує, '
          'можна зібрати при клієнтові',
      child: Icon(Icons.check_circle_outline_rounded,
          size: size, color: const Color(0xFF059669)),
    );
  }
}
