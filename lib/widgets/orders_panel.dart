import 'package:flutter/material.dart';
import '../models/internet_order.dart';
import '../models/customer_loyalty.dart';
import '../models/payment_method.dart';
import '../data/mock_orders.dart';
import 'checkout/bonus_discount_block.dart';
import 'checkout/cash_change_section.dart';
import 'checkout/payment_method_toggle.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OrdersPanel — Internet orders panel shown in the right detail column.
// Three-screen flow: Order List → Order Details → Checkout.
// ─────────────────────────────────────────────────────────────────────────────

class OrdersPanel extends StatefulWidget {
  final VoidCallback onClose;
  final CustomerLoyalty? loyalty;

  const OrdersPanel({
    super.key,
    required this.onClose,
    this.loyalty,
  });

  @override
  State<OrdersPanel> createState() => OrdersPanelState();
}

class OrdersPanelState extends State<OrdersPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  InternetOrder? _selectedOrder;
  late List<InternetOrder> _filteredOrders;

  /// Mutable copy of mock orders (allows status changes).
  late List<InternetOrder> _orders;

  /// Index of the highlighted order in _filteredOrders (auto-selects first match).
  int _highlightedIndex = -1;

  /// SKUs scanned during the current order collection (simulated by price tap).
  final Set<String> _scannedSkus = {};

  /// Whether the search field has non-empty text (drives highlight).
  bool get _hasQuery => _searchController.text.trim().isNotEmpty;

  // ── Checkout state (mirrors CartPanel) ─────────────────────────────────────
  bool _orderCheckoutMode = false;
  bool _showPaymentSuccess = false;
  PaymentMethod _paymentMethod = PaymentMethod.card;
  final _cashController = TextEditingController();
  final _cashFocusNode = FocusNode();
  bool _transferChangeToBonus = false;
  bool _useBonuses = false;
  final _bonusController = TextEditingController();
  double? _personalDiscount;
  double? _availableDiscount;
  bool _isLoadingDiscount = false;

  double get _orderTotal => _selectedOrder?.total ?? 0;

  double get _discountAmount {
    if (_personalDiscount == null) return 0;
    return _orderTotal * _personalDiscount! / 100;
  }

  double get _effectiveBonusAmount {
    if (!_useBonuses || widget.loyalty == null) return 0;
    final text = _bonusController.text.replaceAll(',', '.');
    final entered = double.tryParse(text) ?? 0;
    final maxByBalance = widget.loyalty!.bonusBalance;
    final maxByTotal = _orderTotal - _discountAmount;
    return entered.clamp(0, maxByBalance).clamp(0, maxByTotal).toDouble();
  }

  double get _finalTotal {
    final raw = _orderTotal - _discountAmount - _effectiveBonusAmount;
    return raw < 0 ? 0 : raw;
  }

  /// Public — allows PosScreen to check if detail is open (for Esc cascade).
  bool get isDetailOpen => _selectedOrder != null && !_orderCheckoutMode;

  /// Public — allows PosScreen to check if checkout is open.
  bool get isInCheckout => _orderCheckoutMode;

  /// Public — allows PosScreen to close detail via Esc.
  void closeDetail() {
    setState(() {
      _selectedOrder = null;
      _scannedSkus.clear();
    });
  }

  /// Public — allows PosScreen to exit checkout via Esc.
  void exitOrderCheckout() {
    setState(() => _orderCheckoutMode = false);
  }

  /// Public — focuses the search field (called after panel opens).
  void focusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _orders = List<InternetOrder>.from(mockOrders);
    _filteredOrders = _sorted(_orders);
    _searchController.addListener(_filterOrders);
  }

  @override
  void didUpdateWidget(covariant OrdersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loyalty == null && widget.loyalty != null && _availableDiscount == null) {
      _fetchAvailableOrderDiscount();
    }
    if (widget.loyalty == null && _availableDiscount != null) {
      _availableDiscount = null;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _cashController.dispose();
    _cashFocusNode.dispose();
    _bonusController.dispose();
    super.dispose();
  }

  /// Sort: urgent non-collected first, then the rest chronologically.
  List<InternetOrder> _sorted(List<InternetOrder> orders) {
    final list = List<InternetOrder>.from(orders);
    list.sort((a, b) {
      final aUrgent = a.isUrgent && a.status != OrderStatus.collected && a.status != OrderStatus.dispensed;
      final bUrgent = b.isUrgent && b.status != OrderStatus.collected && b.status != OrderStatus.dispensed;
      if (aUrgent && !bUrgent) return -1;
      if (!aUrgent && bUrgent) return 1;
      return 0; // preserve original order within groups
    });
    return list;
  }

  void _filterOrders() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredOrders = _sorted(_orders);
        _highlightedIndex = -1;
      } else {
        _filteredOrders = _sorted(
          _orders
              .where((o) => o.reserveNumber.toLowerCase().contains(query))
              .toList(),
        );
        // Auto-highlight the first match
        _highlightedIndex = _filteredOrders.isNotEmpty ? 0 : -1;
      }
    });
  }

  /// Open highlighted order (Enter from search field).
  void _openHighlighted() {
    if (_highlightedIndex >= 0 &&
        _highlightedIndex < _filteredOrders.length) {
      _selectOrder(_filteredOrders[_highlightedIndex]);
    }
  }

  void _selectOrder(InternetOrder order) {
    setState(() {
      _selectedOrder = order;
      _scannedSkus.clear();
    });
  }

  /// Simulate barcode scan (triggered by tapping item price).
  void _scanItem(OrderItem item) {
    setState(() => _scannedSkus.add(item.sku));
  }

  /// Whether all real items (total >= 0) in the current order have been scanned.
  bool get _allScanned {
    final order = _selectedOrder;
    if (order == null) return false;
    final realItems = order.items.where((i) => i.total >= 0);
    return realItems.every((i) => _scannedSkus.contains(i.sku));
  }

  /// Enter checkout mode for the current order.
  void _enterOrderCheckout() {
    final order = _selectedOrder;
    if (order == null) return;
    // Collected orders skip scan check (already collected).
    // Non-collected orders require all items to be scanned first.
    if (order.status != OrderStatus.collected && !_allScanned) return;
    setState(() => _orderCheckoutMode = true);
  }

  /// Place order into locker → change status to collected.
  void _placeInLocker() {
    final order = _selectedOrder;
    if (order == null || !_allScanned) return;
    final idx = _orders.indexWhere((o) => o.id == order.id);
    if (idx < 0) return;
    // Assign a mock locker cell number
    final updated = order.copyWith(
      status: OrderStatus.collected,
      lockerCell: 10 + idx,
    );
    setState(() {
      _orders[idx] = updated;
      _selectedOrder = null;
      _scannedSkus.clear();
      _filterOrders();
    });
  }

  void _resetOrderCheckoutState() {
    _orderCheckoutMode = false;
    _showPaymentSuccess = false;
    _paymentMethod = PaymentMethod.card;
    _useBonuses = false;
    _bonusController.clear();
    _personalDiscount = null;
    _availableDiscount = null;
    _cashController.clear();
    _transferChangeToBonus = false;
  }

  void _processOrderPayment() {
    final order = _selectedOrder;
    if (order == null) return;
    setState(() => _showPaymentSuccess = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      // Mark order as dispensed
      final idx = _orders.indexWhere((o) => o.id == order.id);
      if (idx >= 0) {
        _orders[idx] = order.copyWith(status: OrderStatus.dispensed);
      }
      setState(() {
        _resetOrderCheckoutState();
        _selectedOrder = null;
        _scannedSkus.clear();
        _filterOrders();
      });
    });
  }

  Future<void> _fetchAvailableOrderDiscount() async {
    if (widget.loyalty == null) return;
    final lastDigit = widget.loyalty!.phone.characters.last;
    final d = int.tryParse(lastDigit) ?? 0;
    final discount = d >= 5 ? d.toDouble() : null;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _availableDiscount = discount);
  }

  Future<void> _requestOrderDiscount() async {
    if (widget.loyalty == null || _isLoadingDiscount) return;
    if (_availableDiscount != null) {
      setState(() => _personalDiscount = _availableDiscount);
      return;
    }
    setState(() => _isLoadingDiscount = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final lastDigit = widget.loyalty!.phone.characters.last;
    final d = int.tryParse(lastDigit) ?? 0;
    final discount = d >= 5 ? (d.toDouble()) : null;
    setState(() {
      _availableDiscount = discount;
      _personalDiscount = discount;
      _isLoadingDiscount = false;
    });
    if (discount == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Знижка для цього клієнта не передбачена'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.03, 0),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          ),
        ),
        child: _orderCheckoutMode && _selectedOrder != null
            ? _buildCheckoutScreen(_selectedOrder!)
            : _selectedOrder != null
                ? _buildDetailScreen(_selectedOrder!)
                : _buildListScreen(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 1 — ORDER LIST
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildListScreen() {
    return Column(
      key: const ValueKey('orders_list'),
      children: [
        _buildListHeader(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        _buildSearchField(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        Expanded(child: _buildOrdersList()),
        _buildListFooter(),
      ],
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const Icon(Icons.shopping_bag_outlined,
              color: Color(0xFF1E7DC8), size: 17),
          const SizedBox(width: 8),
          const Text(
            'Замовлення',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          // Hotkey badge matching CartPanel F2 style
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Text(
              'Ctrl+I',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Spacer(),
          // Close button
          _HoverIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Закрити',
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SizedBox(
        height: 34,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C2E)),
          onSubmitted: (_) => _openHighlighted(),
          decoration: InputDecoration(
            hintText: 'Номер замовлення, П.І.Б., Glovo',
            hintStyle:
                const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 18, color: Color(0xFF9CA3AF)),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 0),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            filled: true,
            fillColor: const Color(0xFFF4F5F8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E7DC8)),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.requestFocus();
                    },
                    child: const Icon(Icons.close_rounded,
                        size: 16, color: Color(0xFF9CA3AF)),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildOrdersList() {
    if (_filteredOrders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, size: 40, color: Color(0xFFD1D5DB)),
              SizedBox(height: 8),
              Text(
                'Замовлень не знайдено',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: _filteredOrders.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, thickness: 1, color: Color(0xFFF4F5F8)),
      itemBuilder: (context, index) {
        final order = _filteredOrders[index];
        return _OrderListTile(
          order: order,
          highlighted: _hasQuery && index == _highlightedIndex,
          onTap: () => _selectOrder(order),
        );
      },
    );
  }

  Widget _buildListFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          const Icon(Icons.list_alt_rounded,
              size: 14, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 6),
          Text(
            'Замовлень: ${_filteredOrders.length}',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 2 — ORDER DETAIL (mirrors CartPanel layout)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetailScreen(InternetOrder order) {
    return Column(
      key: ValueKey('order_detail_${order.id}'),
      children: [
        _buildDetailHeader(order),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        // Items scroll (like CartPanel's _buildItemsAndOffers)
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              for (final item in order.items)
                _OrderItemRow(
                  item: item,
                  isScanned: _scannedSkus.contains(item.sku),
                  canScan: order.status != OrderStatus.collected &&
                      order.status != OrderStatus.dispensed,
                  onScan: () => _scanItem(item),
                ),
            ],
          ),
        ),
        _buildDetailFooter(order),
      ],
    );
  }

  // ── Detail header (mirrors CartPanel header) ──────────────────────────────

  Widget _buildDetailHeader(InternetOrder order) {
    final dateStr =
        '${order.dateTime.day.toString().padLeft(2, '0')}.${order.dateTime.month.toString().padLeft(2, '0')}'
        '  ${order.dateTime.hour}:${order.dateTime.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 10, 12),
      child: Column(
        children: [
          // Row 1: back + reserve number + status badge
          Row(
            children: [
              _HoverIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'До списку',
                onTap: () => setState(() => _selectedOrder = null),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.receipt_long_rounded,
                  color: Color(0xFF1E7DC8), size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '#${order.reserveNumber}',
                  style: const TextStyle(
                    color: Color(0xFF1C1C2E),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _OrderStatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: date + source type + locker cell
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Row(
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: order.type == OrderType.glovo
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFFF4F5F8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    order.typeLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: order.type == OrderType.glovo
                          ? const Color(0xFFB45309)
                          : const Color(0xFF6B7280),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (order.lockerCell != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7FF),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2_outlined,
                            size: 11, color: Color(0xFF1E7DC8)),
                        const SizedBox(width: 4),
                        Text(
                          '${order.lockerCell}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E7DC8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Collected order actions: single "Розрахувати F5" button ────────────────

  Widget _buildCollectedActions() {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton(
        onPressed: _enterOrderCheckout,
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF1E7DC8),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.point_of_sale_rounded, size: 16),
            const SizedBox(width: 8),
            const Text('Розрахувати',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'F5',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Not-collected order actions: Розрахувати + Лікомат + Відмовити + Відсутність

  Widget _buildNotCollectedActions() {
    final allDone = _allScanned;
    final order = _selectedOrder;
    final showLocker = order != null && order.isLockerEligible;

    return Column(
      children: [
        // Primary row: Розрахувати + Покласти в лікомат (both disabled until scanned)
        if (showLocker)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: allDone ? _enterOrderCheckout : null,
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF1E7DC8),
                      disabledForegroundColor: const Color(0xFFD1D5DB),
                      disabledBackgroundColor: const Color(0xFFF4F5F8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.point_of_sale_rounded, size: 15),
                        const SizedBox(width: 4),
                        const Flexible(
                          child: Text('Розрахувати',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (allDone) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0x33FFFFFF),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'F5',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: allDone ? _placeInLocker : null,
                    icon: const Icon(Icons.lock_outline_rounded, size: 16),
                    label: const Text('В лікомат',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF1E7DC8),
                      disabledForegroundColor: const Color(0xFFD1D5DB),
                      disabledBackgroundColor: const Color(0xFFF4F5F8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          // Only "Розрахувати" full-width for non-locker orders
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              onPressed: allDone ? _enterOrderCheckout : null,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF1E7DC8),
                disabledForegroundColor: const Color(0xFFD1D5DB),
                disabledBackgroundColor: const Color(0xFFF4F5F8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.point_of_sale_rounded, size: 16),
                  const SizedBox(width: 8),
                  const Text('Розрахувати',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (allDone) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'F5',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        // Secondary row: Відмовити + Повідомити
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // TODO: wire up refuse
                  },
                  icon: const Icon(Icons.cancel_outlined, size: 15),
                  label: const Text('Відмовити',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    backgroundColor: const Color(0xFFFEF2F2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // TODO: wire up notify
                  },
                  icon: const Icon(Icons.sms_failed_outlined, size: 15),
                  label: const Text('Відсутність',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Detail footer (mirrors CartPanel footer with total) ───────────────────

  Widget _buildDetailFooter(InternetOrder order) {
    final formattedTotal =
        order.total.toStringAsFixed(2).replaceAll('.', ',');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Сума:',
                style: TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$formattedTotal ₴',
                style: const TextStyle(
                  color: Color(0xFF1E7DC8),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          // Locker hint for collected orders awaiting pickup
          if (order.lockerCell != null &&
              order.status == OrderStatus.collected) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF1E7DC8),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Запропонуйте клієнту забрати замовлення '
                      'самостійно в лікоматі, будь ласка',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF1E7DC8),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Scan hint for not-yet-collected orders
          if (order.status != OrderStatus.collected &&
              !_allScanned) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF1E7DC8),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Зберіть і відскануйте весь товар '
                      'в замовленні, будь ласка',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF1E7DC8),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Action buttons — depend on order status
          if (order.status == OrderStatus.collected)
            _buildCollectedActions()
          else
            _buildNotCollectedActions(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 3 — CHECKOUT (identical to CartPanel checkout)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCheckoutScreen(InternetOrder order) {
    return Column(
      key: const ValueKey('order_checkout'),
      children: [
        _buildCheckoutHeader(order),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        Expanded(
          child: SingleChildScrollView(
            child: _buildCheckoutBody(order),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutHeader(InternetOrder order) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              _resetOrderCheckoutState();
              setState(() => _orderCheckoutMode = false);
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F8),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: Color(0xFF6B7280), size: 16),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.point_of_sale_rounded,
              color: Color(0xFF1E7DC8), size: 17),
          const SizedBox(width: 8),
          const Text(
            'Розрахунок',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Order number badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F3FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '#${order.reserveNumber}',
              style: const TextStyle(
                color: Color(0xFF1E7DC8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 7),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F8),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Color(0xFF9CA3AF), size: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutBody(InternetOrder order) {
    final formattedTotal =
        _finalTotal.toStringAsFixed(2).replaceAll('.', ',');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── "До сплати" — big total ──────────────────────────────────────
          Row(
            children: [
              const Text(
                'До сплати:',
                style: TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$formattedTotal ₴',
                style: const TextStyle(
                  color: Color(0xFF1E7DC8),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          // ── Bonuses + Discount block ───────────────────────────────────────
          const SizedBox(height: 12),
          BonusDiscountBlock(
            loyalty: widget.loyalty,
            useBonuses: _useBonuses,
            onUseBonusesChanged: (v) {
              setState(() {
                _useBonuses = v;
                if (_useBonuses && widget.loyalty != null) {
                  final max = _orderTotal - _discountAmount;
                  final capped =
                      widget.loyalty!.bonusBalance.clamp(0, max);
                  _bonusController.text = capped.toStringAsFixed(0);
                }
              });
            },
            bonusController: _bonusController,
            cartTotal: _orderTotal,
            discountAmount: _discountAmount,
            effectiveBonusAmount: _effectiveBonusAmount,
            personalDiscount: _personalDiscount,
            availableDiscountAmount: _availableDiscount != null
                ? _orderTotal * _availableDiscount! / 100
                : null,
            isLoadingDiscount: _isLoadingDiscount,
            onRequestDiscount: _requestOrderDiscount,
            onClearDiscount: () =>
                setState(() => _personalDiscount = null),
            onBonusAmountChanged: () => setState(() {}),
          ),

          const SizedBox(height: 14),

          // ── Payment method toggle ──────────────────────────────────────────
          PaymentMethodToggle(
            selectedMethod: _paymentMethod,
            onMethodChanged: (method) => setState(() {
              _paymentMethod = method;
              if (method == PaymentMethod.cash) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _cashFocusNode.requestFocus();
                });
              } else {
                _cashController.clear();
              }
            }),
          ),

          // ── Cash section ───────────────────────────────────────────────────
          if (_paymentMethod == PaymentMethod.cash && !_showPaymentSuccess)
            CashChangeSection(
              cashController: _cashController,
              cashFocusNode: _cashFocusNode,
              finalTotal: _finalTotal,
              onChanged: () => setState(() {}),
              showBonusTransfer: widget.loyalty != null,
              transferChangeToBonus: _transferChangeToBonus,
              onTransferChangeToBonusChanged: (v) =>
                  setState(() => _transferChangeToBonus = v),
            ),

          const SizedBox(height: 10),

          // ── Pay / success button ───────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: _showPaymentSuccess
                ? _orderPaySuccessWidget()
                : _orderPayButtonWidget(),
          ),

          const SizedBox(height: 8),

          // ── Secondary actions ──────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _OrderSmallButton(
                    icon: Icons.inventory_2_outlined,
                    label: 'Резерв F6',
                    onTap: () {}),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _OrderSmallButton(
                    icon: Icons.smart_toy_outlined,
                    label: 'Привезти чек',
                    onTap: () {}),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderPaySuccessWidget() => Container(
        key: const ValueKey('order_pay_success'),
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 19),
            SizedBox(width: 7),
            Text(
              'Оплата проведена!',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _orderPayButtonWidget() => GestureDetector(
        key: const ValueKey('order_pay_btn'),
        onTap: _processOrderPayment,
        child: Container(
          width: double.infinity,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF1E7DC8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.payment_rounded, color: Colors.white, size: 18),
              SizedBox(width: 7),
              Text(
                'Провести оплату',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _OrderSmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _OrderSmallButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isEnabled
              ? const Color(0xFFE8F3FB)
              : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isEnabled
                ? const Color(0xFF1E7DC8).withValues(alpha: 0.2)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isEnabled
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFFD1D5DB),
                size: 16),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                  color: isEnabled
                      ? const Color(0xFF1E7DC8)
                      : const Color(0xFFD1D5DB),
                  fontSize: 11,
                )),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

// ── Order list tile ─────────────────────────────────────────────────────────

class _OrderListTile extends StatefulWidget {
  final InternetOrder order;
  final bool highlighted;
  final VoidCallback onTap;
  const _OrderListTile({
    required this.order,
    this.highlighted = false,
    required this.onTap,
  });

  @override
  State<_OrderListTile> createState() => _OrderListTileState();
}

class _OrderListTileState extends State<_OrderListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isHighlighted = widget.highlighted;
    // Build product names subtitle: full name for 1 item, first 10 chars each for multiple
    final realItems = order.items.where((i) => i.total >= 0).toList();
    final String itemsSummary;
    if (realItems.length == 1) {
      itemsSummary = realItems.first.name;
    } else {
      itemsSummary = realItems
          .map((i) => i.name.length > 10 ? '${i.name.substring(0, 10)}…' : i.name)
          .join(', ');
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isHighlighted
                ? const Color(0xFFEEF2FF)
                : _hovered
                    ? const Color(0xFFF8FAFF)
                    : Colors.transparent,
            border: isHighlighted
                ? const Border(
                    left: BorderSide(color: Color(0xFF1E7DC8), width: 3))
                : null,
          ),
          child: Row(
            children: [
              // Status dot
              _StatusDot(status: order.status, isUrgent: order.isUrgent),
              const SizedBox(width: 10),
              // Reserve number + locker cell + urgent badge + product names
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          order.reserveNumber,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1C1C2E),
                          ),
                        ),
                        if (order.isUrgent &&
                            order.status != OrderStatus.collected &&
                            order.status != OrderStatus.dispensed) ...[
                          // Reason badge: Лікомат or Glovo
                          if (order.isLockerEligible) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F7FF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: const Color(0xFFBFDBFE)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline_rounded,
                                      size: 9, color: Color(0xFF1E7DC8)),
                                  SizedBox(width: 3),
                                  Text(
                                    'Лікомат',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E7DC8),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (order.type == OrderType.glovo) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: const Color(0xFFFED7AA)),
                              ),
                              child: const Text(
                                'Glovo',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFEA580C),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                          // Термінове badge
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0xFFFECACA)),
                            ),
                            child: const Text(
                              'Термінове',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFDC2626),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                        if (order.lockerCell != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F7FF),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0xFFBFDBFE)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.inventory_2_outlined,
                                    size: 10, color: Color(0xFF1E7DC8)),
                                const SizedBox(width: 3),
                                Text(
                                  '${order.lockerCell}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E7DC8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      itemsSummary,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Price
              Text(
                '${order.total.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 6),
              if (isHighlighted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E7DC8),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'Enter',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Color(0xFFD1D5DB)),
            ],
          ),
        ),
      ),
    );
  }

}

// ── Status dot ──────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final OrderStatus status;
  final bool isUrgent;
  const _StatusDot({required this.status, this.isUrgent = false});

  @override
  Widget build(BuildContext context) {
    // Urgent + not yet collected/dispensed → red filled dot
    final isActiveUrgent = isUrgent &&
        status != OrderStatus.collected &&
        status != OrderStatus.dispensed;

    final color = isActiveUrgent
        ? const Color(0xFFEF4444)
        : switch (status) {
            OrderStatus.newOrder => const Color(0xFF3B82F6),     // blue
            OrderStatus.inProgress => const Color(0xFFF59E0B),   // amber
            OrderStatus.collected => const Color(0xFF22C55E),    // green
            OrderStatus.dispensed => const Color(0xFF6B7280),    // gray
            OrderStatus.refused => const Color(0xFFEF4444),      // red
          };

    final isFilled = isActiveUrgent ||
        status == OrderStatus.collected ||
        status == OrderStatus.dispensed;

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: isFilled ? color : Colors.transparent,
        border: isFilled ? null : Border.all(color: color, width: 1.5),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ── Status badge (for detail header) ────────────────────────────────────────

class _OrderStatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _OrderStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, bgColor) = switch (status) {
      OrderStatus.newOrder => (
          const Color(0xFF3B82F6),
          const Color(0xFFEFF6FF)
        ),
      OrderStatus.inProgress => (
          const Color(0xFFF59E0B),
          const Color(0xFFFFFBEB)
        ),
      OrderStatus.collected => (
          const Color(0xFF22C55E),
          const Color(0xFFF0FDF4)
        ),
      OrderStatus.dispensed => (
          const Color(0xFF6B7280),
          const Color(0xFFF9FAFB)
        ),
      OrderStatus.refused => (
          const Color(0xFFEF4444),
          const Color(0xFFFEF2F2)
        ),
    };

    final label = switch (status) {
      OrderStatus.newOrder => 'Нове',
      OrderStatus.inProgress => 'В обробці',
      OrderStatus.collected => 'Зібране',
      OrderStatus.dispensed => 'Видане',
      OrderStatus.refused => 'Відмовлено',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Order item row (mirrors CartItemWidget layout) ──────────────────────────

class _OrderItemRow extends StatelessWidget {
  final OrderItem item;

  /// Whether this item has been scanned (barcode confirmed).
  final bool isScanned;

  /// Whether scanning is available (order not yet collected).
  final bool canScan;

  /// Callback when the pharmacist taps the price (simulates barcode scan).
  final VoidCallback? onScan;

  const _OrderItemRow({
    required this.item,
    this.isScanned = false,
    this.canScan = false,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final isDiscount = item.total < 0;
    final qtyStr = item.fraction ??
        (item.quantity % 1 == 0
            ? item.quantity.toInt().toString()
            : item.quantity.toString());

    // Scanned items get a blue-tinted card
    final Color bgColor;
    final Color borderColor;
    if (isDiscount) {
      bgColor = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFDE68A);
    } else if (isScanned) {
      bgColor = const Color(0xFFEFF6FF);
      borderColor = const Color(0xFFBFDBFE);
    } else {
      bgColor = const Color(0xFFF9FAFB);
      borderColor = const Color(0xFFE5E7EB);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Icon: blue checkbox when scanned, default otherwise
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isDiscount
                  ? const Color(0xFFFEF3C7)
                  : isScanned
                      ? const Color(0xFFDBEAFE)
                      : const Color(0xFFE8F3FB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isDiscount
                  ? Icons.discount_outlined
                  : isScanned
                      ? Icons.check_box_rounded
                      : Icons.medication_rounded,
              color: isDiscount
                  ? const Color(0xFFB45309)
                  : const Color(0xFF1E7DC8),
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          // Name and price × qty
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: isDiscount
                        ? const Color(0xFFB45309)
                        : isScanned
                            ? const Color(0xFF1E7DC8)
                            : const Color(0xFF1C1C2E),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.price.toStringAsFixed(2).replaceAll('.', ',')} ₴ × $qtyStr',
                  style: TextStyle(
                    color: isScanned
                        ? const Color(0xFF93C5FD)
                        : const Color(0xFF9CA3AF),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Total price — tappable to simulate scan
          GestureDetector(
            onTap: (canScan && !isScanned && !isDiscount) ? onScan : null,
            child: MouseRegion(
              cursor: (canScan && !isScanned && !isDiscount)
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: (canScan && !isScanned && !isDiscount)
                    ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: const Color(0xFF1E7DC8)
                                .withValues(alpha: 0.3),
                            style: BorderStyle.solid,
                          ),
                        ),
                      )
                    : null,
                child: Text(
                  '${item.total.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: isDiscount
                        ? const Color(0xFFB45309)
                        : isScanned
                            ? const Color(0xFF1E7DC8)
                            : const Color(0xFF1C1C2E),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hover icon button (reusable) ────────────────────────────────────────────

class _HoverIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0xFFF4F5F8)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: _hovered
                  ? const Color(0xFF1C1C2E)
                  : const Color(0xFF9CA3AF),
            ),
          ),
        ),
      ),
    );
  }
}
