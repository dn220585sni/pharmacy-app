import 'package:flutter/material.dart';
import '../models/cart_item.dart';
import 'hover_icon_button.dart';

// ═════════════════════════════════════════════════════════════════════════════
// ROBOT PANEL — right-panel widget for pharmacy robot control.
// Provides commands: deliver cart, open/close tray, reset queue, restart,
// and a toggle for automatic delivery.
// ═════════════════════════════════════════════════════════════════════════════

class RobotPanel extends StatefulWidget {
  final VoidCallback onClose;
  final List<CartItem> cart;
  final void Function(CartItem item)? onRequestItem;
  final VoidCallback? onRequestAll;

  const RobotPanel({
    super.key,
    required this.onClose,
    required this.cart,
    this.onRequestItem,
    this.onRequestAll,
  });

  @override
  State<RobotPanel> createState() => RobotPanelState();
}

class RobotPanelState extends State<RobotPanel> {
  bool _deliveryEnabled = true;
  bool _trayOpen = false;

  // ── Public API for POS screen Esc cascade ─────────────────────────────────
  bool get isDetailOpen => false;
  void closeDetail() {}
  void focusSearch() {}

  void _showStub(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.smart_toy_outlined,
                size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E7DC8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          Expanded(child: _buildCommandList()),
          if (widget.cart.isNotEmpty) ...[
            const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
            _buildCartSummary(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const Icon(Icons.smart_toy_outlined,
              color: Color(0xFF1E7DC8), size: 17),
          const SizedBox(width: 8),
          const Text(
            'Робот',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Text(
              'Ctrl+B',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _deliveryEnabled
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _deliveryEnabled
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _deliveryEnabled ? 'Активний' : 'Вимкнено',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _deliveryEnabled
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          HoverIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Закрити',
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildCommandList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildCommandTile(
          icon: Icons.shopping_cart_checkout_rounded,
          title: 'Привезти весь чек',
          subtitle: widget.cart.isEmpty
              ? 'Кошик порожній'
              : '${widget.cart.length} поз.',
          color: const Color(0xFF1E7DC8),
          enabled: widget.cart.isNotEmpty && _deliveryEnabled,
          onTap: () {
            widget.onRequestAll?.call();
            _showStub('Робот: привожу весь чек (${widget.cart.length} поз.)');
          },
        ),
        _buildCommandTile(
          icon: _trayOpen
              ? Icons.door_sliding_outlined
              : Icons.door_front_door_outlined,
          title: _trayOpen ? 'Закрити лоток' : 'Відкрити лоток',
          subtitle: _trayOpen ? 'Лоток відкритий' : 'Лоток закритий',
          color: const Color(0xFF8B5CF6),
          onTap: () {
            setState(() => _trayOpen = !_trayOpen);
            _showStub(
                'Робот: ${_trayOpen ? "лоток відкрито" : "лоток закрито"}');
          },
        ),
        _buildCommandTile(
          icon: Icons.playlist_remove_rounded,
          title: 'Погасити чергу',
          subtitle: 'Очистити чергу привезення',
          color: const Color(0xFFF59E0B),
          onTap: () => _showStub('Робот: чергу привезення очищено'),
        ),
        _buildCommandTile(
          icon: Icons.restart_alt_rounded,
          title: 'Перезапуск передньої стінки',
          subtitle: 'Рестарт фронтальної панелі',
          color: const Color(0xFFEF4444),
          onTap: () => _showStub('Робот: перезапуск передньої стінки'),
        ),
        const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: Color(0xFFE5E7EB)),
        _buildToggleTile(),
      ],
    );
  }

  Widget _buildCommandTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    bool enabled = true,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: enabled ? color.withOpacity(0.1) : const Color(0xFFF4F5F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    size: 20,
                    color: enabled ? color : const Color(0xFFD1D5DB)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? const Color(0xFF1C1C2E)
                            : const Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: enabled
                            ? const Color(0xFF6B7280)
                            : const Color(0xFFD1D5DB),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18,
                  color: enabled
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFFE5E7EB)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _deliveryEnabled
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _deliveryEnabled
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              size: 22,
              color: _deliveryEnabled
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Привезення з робота',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _deliveryEnabled ? 'Увімкнено' : 'Вимкнено',
                  style: TextStyle(
                    fontSize: 11,
                    color: _deliveryEnabled
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _deliveryEnabled,
            onChanged: (val) {
              setState(() => _deliveryEnabled = val);
              _showStub(
                  'Робот: привезення ${val ? "увімкнено" : "вимкнено"}');
            },
            activeColor: const Color(0xFF22C55E),
          ),
        ],
      ),
    );
  }

  Widget _buildCartSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Товари в кошику',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 6),
          ...widget.cart.take(5).map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    if (item.drug.storageLocations?.any(
                            (l) => l.type.name == 'robot') ==
                        true)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.smart_toy_outlined,
                            size: 12, color: Color(0xFF1E7DC8)),
                      ),
                    Expanded(
                      child: Text(
                        item.drug.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF374151)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '×${item.quantity}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              )),
          if (widget.cart.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '...ще ${widget.cart.length - 5} поз.',
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF9CA3AF)),
              ),
            ),
        ],
      ),
    );
  }
}
