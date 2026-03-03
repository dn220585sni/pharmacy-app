import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Vertical quick-action sidebar shown on the far right of the POS screen.
// Buttons are currently stubs — functionality wired later.
// ─────────────────────────────────────────────────────────────────────────────

class ActionSidebar extends StatelessWidget {
  const ActionSidebar({super.key});

  static const _buttons = [
    _SidebarItem(Icons.help_outline_rounded,         'Довідка'),
    _SidebarItem(Icons.mail_outline_rounded,          'Повідомлення'),
    _SidebarItem(Icons.language_rounded,              'Компендіум'),
    _SidebarItem(Icons.health_and_safety_outlined,    'Клінічна база'),
    _SidebarItem(Icons.mood_rounded,                  'Програма Лайк'),
    _SidebarItem(Icons.volunteer_activism_rounded,    'ТПК'),
    _SidebarItem(Icons.manage_search_rounded,         'Розширений пошук'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < _buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            _SidebarButton(item: _buttons[i]),
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
  const _SidebarItem(this.icon, this.tooltip);
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
    return Tooltip(
      message: widget.item.tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            // TODO: wire up action per button
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0xFFEEF2FF)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovered
                    ? const Color(0xFFBFCBFB)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: Icon(
              widget.item.icon,
              size: 20,
              color: _hovered
                  ? const Color(0xFF4F6EF7)
                  : const Color(0xFF9CA3AF),
            ),
          ),
        ),
      ),
    );
  }
}
