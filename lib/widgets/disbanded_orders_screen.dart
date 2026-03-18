import 'package:flutter/material.dart';
import '../models/internet_order.dart';
import '../models/drug.dart'; // StorageLocation, StorageLocationType
import 'hover_icon_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DisbandedOrdersScreen — full-screen view for managing refused internet orders.
// Extracted from OrdersPanel to reduce file size.
// ─────────────────────────────────────────────────────────────────────────────

/// Storage location data for SKU-based order items.
/// Kept as a static const map — identical to the one previously in OrdersPanel.
final Map<String, List<StorageLocation>> skuStorageLocations = {
  '26993528': [
    StorageLocation(type: StorageLocationType.shelf, code: 'B3/04', qty: 18),
  ],
  '26771903': [
    StorageLocation(type: StorageLocationType.robot, code: 'R-078', qty: 6),
    StorageLocation(type: StorageLocationType.shelf, code: 'C2/09', qty: 3),
  ],
  '25112478': [
    StorageLocation(type: StorageLocationType.shelf, code: 'A3/02', qty: 12),
  ],
  '26890213': [
    StorageLocation(type: StorageLocationType.robot, code: 'R-104', qty: 8),
    StorageLocation(
        type: StorageLocationType.showcase, code: 'V1/05', qty: 2),
  ],
  '27234561': [
    StorageLocation(type: StorageLocationType.shelf, code: 'D1/03', qty: 5),
  ],
  '27001845': [
    StorageLocation(type: StorageLocationType.robot, code: 'R-035', qty: 4),
    StorageLocation(type: StorageLocationType.shelf, code: 'E2/01', qty: 2),
  ],
  '26104387': [
    StorageLocation(type: StorageLocationType.shelf, code: 'A4/07', qty: 9),
  ],
};

class DisbandedOrdersScreen extends StatefulWidget {
  final List<InternetOrder> refusedOrders;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final void Function(Set<String> checkedIds) onDisband;

  const DisbandedOrdersScreen({
    super.key,
    required this.refusedOrders,
    required this.onBack,
    required this.onClose,
    required this.onDisband,
  });

  @override
  State<DisbandedOrdersScreen> createState() => _DisbandedOrdersScreenState();
}

class _DisbandedOrdersScreenState extends State<DisbandedOrdersScreen> {
  late Set<String> _checkedIds;

  @override
  void initState() {
    super.initState();
    _checkedIds = widget.refusedOrders.map((o) => o.id).toSet();
  }

  @override
  void didUpdateWidget(covariant DisbandedOrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the list changed externally, remove stale ids.
    _checkedIds.retainWhere(
        (id) => widget.refusedOrders.any((o) => o.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final refused = widget.refusedOrders;

    return Column(
      key: const ValueKey('disbanded_orders'),
      children: [
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 10, 12),
          child: Row(
            children: [
              HoverIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Назад',
                onTap: widget.onBack,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.inventory_2_outlined,
                  color: Color(0xFFEF4444), size: 17),
              const SizedBox(width: 8),
              const Text(
                'Розформовані',
                style: TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${refused.length}',
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              // Select all / deselect all
              if (refused.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() {
                    if (_checkedIds.length == refused.length) {
                      _checkedIds.clear();
                    } else {
                      _checkedIds = refused.map((o) => o.id).toSet();
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      _checkedIds.length == refused.length
                          ? 'Зняти все'
                          : 'Вибрати все',
                      style: const TextStyle(
                        color: Color(0xFF1E7DC8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              HoverIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Закрити',
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),

        // ── Orders list ──
        Expanded(
          child: refused.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 40, color: Color(0xFF10B981)),
                      SizedBox(height: 12),
                      Text(
                        'Немає розформованих замовлень',
                        style: TextStyle(
                            color: Color(0xFF6B7280), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: refused.length,
                  itemBuilder: (context, index) {
                    final order = refused[index];
                    return _buildOrderCard(order);
                  },
                ),
        ),

        // ── Footer: disband + print buttons ──
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // "Розформовано" — removes checked orders
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _checkedIds.isEmpty
                      ? null
                      : () => widget.onDisband(_checkedIds),
                  icon: const Icon(Icons.check_circle_outline_rounded,
                      size: 16),
                  label: Text(
                      'Розформовано · ${_checkedIds.length}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE5E7EB),
                    disabledForegroundColor: const Color(0xFF9CA3AF),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // "Роздрукувати на чеку"
              SizedBox(
                width: double.infinity,
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: _checkedIds.isEmpty
                      ? null
                      : () {
                          // Stub — print receipt
                        },
                  icon: const Icon(Icons.receipt_long_rounded, size: 15),
                  label: const Text('Роздрукувати на чеку'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E7DC8),
                    side: BorderSide(
                      color: _checkedIds.isEmpty
                          ? const Color(0xFFE5E7EB)
                          : const Color(0xFF1E7DC8).withValues(alpha: 0.4),
                    ),
                    disabledForegroundColor: const Color(0xFF9CA3AF),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Order card with checkbox ──────────────────────────────────────────────

  Widget _buildOrderCard(InternetOrder order) {
    final dateStr =
        '${order.dateTime.day.toString().padLeft(2, '0')}.${order.dateTime.month.toString().padLeft(2, '0')}.${order.dateTime.year}';
    final timeStr =
        '${order.dateTime.hour.toString().padLeft(2, '0')}:${order.dateTime.minute.toString().padLeft(2, '0')}';
    final isChecked = _checkedIds.contains(order.id);

    return GestureDetector(
      onTap: () => setState(() {
        if (isChecked) {
          _checkedIds.remove(order.id);
        } else {
          _checkedIds.add(order.id);
        }
      }),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color:
              isChecked ? const Color(0xFFF0FAF5) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isChecked
                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order header with checkbox
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: isChecked,
                      onChanged: (_) => setState(() {
                        if (isChecked) {
                          _checkedIds.remove(order.id);
                        } else {
                          _checkedIds.add(order.id);
                        }
                      }),
                      activeColor: const Color(0xFF10B981),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '№${order.reserveNumber}',
                    style: const TextStyle(
                      color: Color(0xFF1C1C2E),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$dateStr  $timeStr',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Locker cell badge (if order was in лікомат)
            if (order.lockerCell != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color:
                            const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.door_sliding_outlined,
                          size: 13, color: Color(0xFFD97706)),
                      const SizedBox(width: 5),
                      const Text(
                        'Лікомат',
                        style: TextStyle(
                          color: Color(0xFFD97706),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD97706),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'комірка ${order.lockerCell}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            // Items
            for (final item in order.items) _buildItemRow(item),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  // ── Item row with storage locations ───────────────────────────────────────

  Widget _buildItemRow(OrderItem item) {
    final locations = skuStorageLocations[item.sku];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drug name + qty
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(
                      color: Color(0xFF1C1C2E),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5F8),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '×${item.fraction ?? (item.quantity % 1 == 0 ? item.quantity.toInt().toString() : item.quantity.toString())}',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Storage locations
            if (locations != null && locations.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final loc in locations)
                    _DisbandedLocationChip(
                        type: loc.type, code: loc.code, qty: loc.qty),
                ],
              )
            else
              const Text(
                'Місце не вказано',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DisbandedLocationChip extends StatelessWidget {
  final StorageLocationType type;
  final String code;
  final int? qty;
  const _DisbandedLocationChip(
      {required this.type, required this.code, this.qty});

  @override
  Widget build(BuildContext context) {
    final isRobot = type == StorageLocationType.robot;

    final IconData icon;
    final Color iconColor;
    final Color bgColor;
    final Color borderColor;

    if (isRobot) {
      icon = Icons.smart_toy_rounded;
      iconColor = const Color(0xFF10B981);
      bgColor = const Color(0xFFECFDF5);
      borderColor = const Color(0xFF10B981).withValues(alpha: 0.3);
    } else if (type == StorageLocationType.showcase) {
      icon = Icons.storefront_rounded;
      iconColor = const Color(0xFF8B5CF6);
      bgColor = const Color(0xFFF5F3FF);
      borderColor = const Color(0xFF8B5CF6).withValues(alpha: 0.3);
    } else {
      icon = Icons.shelves;
      iconColor = const Color(0xFF1E7DC8);
      bgColor = const Color(0xFFE8F3FB);
      borderColor = const Color(0xFF1E7DC8).withValues(alpha: 0.3);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              code,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (qty != null) ...[
            const SizedBox(width: 4),
            Text(
              '$qty',
              style: TextStyle(
                color: iconColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

