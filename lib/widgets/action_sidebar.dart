import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Vertical quick-action sidebar shown on the far right of the POS screen.
// Most buttons are stubs — functionality wired later.
// ─────────────────────────────────────────────────────────────────────────────

class ActionSidebar extends StatelessWidget {
  /// Callback when "Замовлення" (internet orders) button is tapped.
  final VoidCallback? onOrdersTap;

  /// Whether the orders panel is currently open (shows active state).
  final bool ordersActive;

  /// Number of urgent non-collected orders (red dot badge on button).
  final int urgentCount;

  const ActionSidebar({
    super.key,
    this.onOrdersTap,
    this.ordersActive = false,
    this.urgentCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      _SidebarItem(Icons.help_outline_rounded, 'Довідка'),
      _SidebarItem(Icons.shopping_bag_outlined, 'Замовлення',
          onTap: onOrdersTap, isActive: ordersActive, badgeCount: urgentCount),
      _SidebarItem(Icons.mail_outline_rounded, 'Повідомлення'),
      _SidebarItem(Icons.language_rounded, 'Компендіум'),
      _SidebarItem(Icons.health_and_safety_outlined, 'Клінічна база'),
      _SidebarItem(Icons.mood_rounded, 'Програма Лайк'),
      _SidebarItem(Icons.volunteer_activism_rounded, 'ТПК'),
      _SidebarItem(Icons.manage_search_rounded, 'Розширений пошук'),
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

class _SidebarItem {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isActive;
  final int badgeCount;
  _SidebarItem(this.icon, this.tooltip,
      {this.onTap, this.isActive = false, this.badgeCount = 0});
}

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

    return Tooltip(
      message: widget.item.tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
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
                child: Icon(
                  widget.item.icon,
                  size: 28,
                  color: isHighlighted
                      ? const Color(0xFF1E7DC8)
                      : const Color(0xFF9CA3AF),
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
