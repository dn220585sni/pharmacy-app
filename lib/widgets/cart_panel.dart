import 'package:flutter/material.dart';
import '../models/cart_item.dart';
import '../models/cart_offer.dart';
import '../models/customer_loyalty.dart';
import '../models/drug.dart';
import '../models/payment_method.dart';
import 'cart_item_widget.dart';
import 'checkout/bonus_discount_block.dart';
import 'checkout/cash_change_section.dart';
import 'checkout/payment_method_toggle.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CartPanel — inline cart shown in the right detail panel.
// Two-screen flow: Cart → Checkout (via F5 / "Розрахувати").
// ─────────────────────────────────────────────────────────────────────────────

class CartPanel extends StatefulWidget {
  final List<CartItem> cart;
  final List<CartOffer> offers;
  final VoidCallback onClear;
  final void Function(int index) onIncrease;
  final void Function(int index) onDecrease;
  final void Function(int index) onRemove;
  final VoidCallback onPay;
  final VoidCallback onClose;
  final void Function(Drug drug) onAddOffer;
  final void Function(Drug drug) onAddOfferBlister;
  final CustomerLoyalty? loyalty;

  const CartPanel({
    super.key,
    required this.cart,
    required this.offers,
    required this.onClear,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onPay,
    required this.onClose,
    required this.onAddOffer,
    required this.onAddOfferBlister,
    this.loyalty,
  });

  @override
  State<CartPanel> createState() => CartPanelState();
}

class CartPanelState extends State<CartPanel> {
  // ── Two-screen mode ────────────────────────────────────────────────────────
  bool _checkoutMode = false;
  bool _showPaymentSuccess = false;

  // Scanned drug IDs (simulated barcode scan by tapping price)
  final Set<String> _scannedDrugIds = {};

  // Bonuses
  bool _useBonuses = false;
  final _bonusController = TextEditingController();

  // Personal discount
  double? _personalDiscount;
  bool _isLoadingDiscount = false;

  // Payment method
  PaymentMethod _paymentMethod = PaymentMethod.card;

  // Cash change
  final _cashController = TextEditingController();
  final _cashFocusNode = FocusNode();
  bool _transferChangeToBonus = false;

  // ── Computed getters ──────────────────────────────────────────────────────

  double get _cartTotal => widget.cart.fold(0.0, (s, i) => s + i.total);
  int get _cartItemCount => widget.cart.length;

  double get _discountAmount {
    if (_personalDiscount == null) return 0;
    return _cartTotal * _personalDiscount! / 100;
  }

  double get _effectiveBonusAmount {
    if (!_useBonuses || widget.loyalty == null) return 0;
    final text = _bonusController.text.replaceAll(',', '.');
    final entered = double.tryParse(text) ?? 0;
    final maxByBalance = widget.loyalty!.bonusBalance;
    final maxByTotal = _cartTotal - _discountAmount;
    return entered.clamp(0, maxByBalance).clamp(0, maxByTotal).toDouble();
  }

  double get _finalTotal {
    final raw = _cartTotal - _discountAmount - _effectiveBonusAmount;
    return raw < 0 ? 0 : raw;
  }

  /// Whether all cart items have been scanned (barcode confirmed).
  bool get _allCartScanned {
    if (widget.cart.isEmpty) return false;
    return widget.cart.every((i) => _scannedDrugIds.contains(i.drug.id));
  }

  void _scanCartItem(CartItem item) {
    setState(() => _scannedDrugIds.add(item.drug.id));
  }

  /// Public method — allows PosScreen to enter checkout mode via F5
  void enterCheckout() {
    if (widget.cart.isEmpty || !_allCartScanned) return;
    setState(() => _checkoutMode = true);
  }

  /// Public method — allows PosScreen to exit checkout back to cart
  void exitCheckout() {
    setState(() => _checkoutMode = false);
  }

  bool get isInCheckout => _checkoutMode;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _bonusController.dispose();
    _cashController.dispose();
    _cashFocusNode.dispose();
    super.dispose();
  }

  // ── Mock discount service ─────────────────────────────────────────────────

  Future<void> _requestDiscount() async {
    if (widget.loyalty == null || _isLoadingDiscount) return;
    setState(() => _isLoadingDiscount = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final lastDigit = widget.loyalty!.phone.characters.last;
    final d = int.tryParse(lastDigit) ?? 0;
    final discount = d >= 5 ? (d.toDouble()) : null;
    setState(() {
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

  // ── Payment ───────────────────────────────────────────────────────────────

  void _processPayment() {
    if (widget.cart.isEmpty) return;
    widget.onPay();
    setState(() => _showPaymentSuccess = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showPaymentSuccess = false;
          _checkoutMode = false;
          _paymentMethod = PaymentMethod.card;
          _useBonuses = false;
          _bonusController.clear();
          _personalDiscount = null;
          _cashController.clear();
          _transferChangeToBonus = false;
          _scannedDrugIds.clear();
        });
        widget.onClose();
      }
    });
  }

  void _resetCheckoutState() {
    _paymentMethod = PaymentMethod.card;
    _useBonuses = false;
    _bonusController.clear();
    _personalDiscount = null;
    _cashController.clear();
    _transferChangeToBonus = false;
    _scannedDrugIds.clear();
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
            ).animate(CurvedAnimation(
                parent: animation, curve: Curves.easeOut)),
            child: child,
          ),
        ),
        child: _checkoutMode
            ? _buildCheckoutScreen()
            : _buildCartScreen(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 1 — CART (items + offers + simple total + "Розрахувати")
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCartScreen() {
    return Column(
      key: const ValueKey('cart_screen'),
      children: [
        _buildCartHeader(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        // Items + Offers scroll together so offers sit right under items
        Expanded(child: _buildItemsAndOffers()),
        _buildCartFooter(),
      ],
    );
  }

  // ── Cart header ───────────────────────────────────────────────────────────

  Widget _buildCartHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded,
              color: Color(0xFF1E7DC8), size: 17),
          const SizedBox(width: 8),
          const Text(
            'Поточний чек',
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
              'F2',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Spacer(),
          if (widget.cart.isNotEmpty) ...[
            GestureDetector(
              onTap: widget.onClear,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFFEF5350).withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFEF5350), size: 13),
                    SizedBox(width: 4),
                    Text('Очистити',
                        style: TextStyle(
                            color: Color(0xFFEF5350), fontSize: 11.5)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 7),
          ],
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

  // ── Items + Offers (scrollable together) ────────────────────────────────

  Widget _buildItemsAndOffers() {
    if (widget.cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined,
                color: Colors.grey.shade200, size: 52),
            const SizedBox(height: 12),
            const Text(
              'Кошик порожній',
              style: TextStyle(color: Color(0xFFB0B7C3), fontSize: 14.5),
            ),
            const SizedBox(height: 5),
            const Text(
              'Введіть кількість у полі «Відпущ»',
              style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 12.5),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (int i = 0; i < widget.cart.length; i++)
          CartItemWidget(
            item: widget.cart[i],
            onIncrease: () => setState(() => widget.onIncrease(i)),
            onDecrease: () => setState(() => widget.onDecrease(i)),
            onRemove: () => setState(() => widget.onRemove(i)),
            isScanned: _scannedDrugIds.contains(widget.cart[i].drug.id),
            onScan: () => _scanCartItem(widget.cart[i]),
          ),
        // Offers sit right under items
        if (widget.offers.isNotEmpty) _buildOffersSection(),
      ],
    );
  }

  // ── Offers section (single ТПК card, EdkPanel-like style) ────────────────

  Widget _buildOffersSection() {
    if (widget.offers.isEmpty) return const SizedBox.shrink();
    final offer = widget.offers.first;
    return _buildOfferCard(offer);
  }

  Widget _buildOfferCard(CartOffer offer) {
    final drug = offer.drug;
    final bonus = drug.pharmacistBonus;
    final hasScript = offer.script != null && offer.script!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFF1E7DC8).withValues(alpha: 0.18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: const BoxDecoration(
                color: Color(0xFFF0F7FF),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Турбота Про Клієнта',
                      style: TextStyle(
                        color: Color(0xFF1E7DC8),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (offer.promoLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        offer.promoLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                children: [
                  // Image
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: drug.imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.network(
                              drug.imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stack) =>
                                  _offerPlaceholderIcon(),
                            ),
                          )
                        : _offerPlaceholderIcon(),
                  ),
                  const SizedBox(height: 10),

                  // Name
                  Text(
                    drug.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF1C1C2E),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),

                  // Manufacturer + category
                  Text(
                    '${drug.manufacturer} · ${drug.category}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Price + bonus
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                        style: const TextStyle(
                          color: Color(0xFF1C1C2E),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (bonus != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFEF3C7),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$bonus',
                              style: const TextStyle(
                                color: Color(0xFFB45309),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Script block
                  if (hasScript) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F7FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF1E7DC8)
                              .withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 14,
                            color: Color(0xFF1E7DC8),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              offer.script!,
                              style: const TextStyle(
                                color: Color(0xFF1E5A8A),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 6),
                    Text(
                      offer.reason,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Buttons ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  if (drug.unitsPerPackage != null) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onAddOfferBlister(drug),
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F5F8),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFE5E7EB)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.grid_view_rounded,
                                  size: 13, color: Color(0xFF6B7280)),
                              SizedBox(width: 5),
                              Text(
                                'Блістер',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onAddOffer(drug),
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E7DC8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_shopping_cart_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 5),
                            Text(
                              'Упаковку',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _offerPlaceholderIcon() {
    return const Center(
      child: Icon(
        Icons.medication_rounded,
        size: 32,
        color: Color(0xFFD1D5DB),
      ),
    );
  }

  // ── Cart footer (simple total + "Розрахувати" button) ─────────────────────

  Widget _buildCartFooter() {
    final formattedTotal =
        _cartTotal.toStringAsFixed(2).replaceAll('.', ',');
    final hasItems = widget.cart.isNotEmpty;
    final canCheckout = hasItems && _allCartScanned;

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
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          // Scan hint — above the button when not all scanned
          if (hasItems && !_allCartScanned) ...[
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
                      'Відскануйте весь товар, будь ласка',
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

          // "Розрахувати" button — disabled until all items scanned
          GestureDetector(
            onTap: canCheckout ? enterCheckout : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              height: 46,
              decoration: BoxDecoration(
                color: canCheckout
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calculate_outlined,
                    color:
                        canCheckout ? Colors.white : const Color(0xFFB0B7C3),
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Розрахувати',
                    style: TextStyle(
                      color: canCheckout
                          ? Colors.white
                          : const Color(0xFFB0B7C3),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (canCheckout) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'F5',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 2 — CHECKOUT (phone, bonuses, discount, payment, change)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCheckoutScreen() {
    return Column(
      key: const ValueKey('checkout_screen'),
      children: [
        _buildCheckoutHeader(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        // Scrollable: total → bonuses/discount → payment → pay → change
        Expanded(
          child: SingleChildScrollView(
            child: _buildCheckoutBody(),
          ),
        ),
      ],
    );
  }

  // ── Checkout header ───────────────────────────────────────────────────────

  Widget _buildCheckoutHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              _resetCheckoutState();
              setState(() => _checkoutMode = false);
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
          // Item count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F3FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$_cartItemCount шт.',
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

  // ── Checkout body ──────────────────────────────────────────────────────

  // ── Checkout body: total → bonuses/discount → payment → pay → change ────

  Widget _buildCheckoutBody() {
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

          // ── Bonuses + Discount block (always visible, disabled w/o loyalty)
          const SizedBox(height: 12),
          BonusDiscountBlock(
            loyalty: widget.loyalty,
            useBonuses: _useBonuses,
            onUseBonusesChanged: (v) {
              setState(() {
                _useBonuses = v;
                if (_useBonuses && widget.loyalty != null) {
                  final max = _cartTotal - _discountAmount;
                  final capped =
                      widget.loyalty!.bonusBalance.clamp(0, max);
                  _bonusController.text = capped.toStringAsFixed(0);
                }
              });
            },
            bonusController: _bonusController,
            cartTotal: _cartTotal,
            discountAmount: _discountAmount,
            effectiveBonusAmount: _effectiveBonusAmount,
            personalDiscount: _personalDiscount,
            isLoadingDiscount: _isLoadingDiscount,
            onRequestDiscount: _requestDiscount,
            onClearDiscount: () =>
                setState(() => _personalDiscount = null),
            onBonusAmountChanged: () => setState(() {}),
          ),

          const SizedBox(height: 14),

          // ── Payment method toggle ────────────────────────────────────────
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

          // ── Cash: amount from client + change ────────────────────────────
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

          // ── Pay / success button ─────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: _showPaymentSuccess
                ? _paySuccessWidget()
                : _payButtonWidget(),
          ),

          const SizedBox(height: 8),

          // ── Secondary actions ────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                  child: _SmallButton(
                      icon: Icons.inventory_2_outlined,
                      label: 'Резерв F6',
                      onTap: () {})),
              const SizedBox(width: 7),
              Expanded(
                  child: _SmallButton(
                      icon: Icons.smart_toy_outlined,
                      label: 'Привезти чек',
                      onTap: () {})),
            ],
          ),

          // ── Intake warnings from external service ───────────────────────
          ..._buildIntakeWarnings(),
        ],
      ),
    );
  }

  // ── Intake warnings ──────────────────────────────────────────────────────

  List<Widget> _buildIntakeWarnings() {
    final warnings = widget.cart
        .where((item) => item.drug.intakeWarning != null)
        .toList();
    if (warnings.isEmpty) return [];
    return [
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: Color(0xFFF59E0B)),
                SizedBox(width: 5),
                Text(
                  'Особливості прийому',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...warnings.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drug image / placeholder
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                          ),
                        ),
                        child: item.drug.imageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: Image.network(
                                  item.drug.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stack) =>
                                      const Icon(Icons.medication_rounded,
                                          size: 16,
                                          color: Color(0xFFF59E0B)),
                                ),
                              )
                            : const Icon(Icons.medication_rounded,
                                size: 16, color: Color(0xFFF59E0B)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.drug.name,
                              style: const TextStyle(
                                color: Color(0xFF92400E),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              item.drug.intakeWarning!,
                              style: const TextStyle(
                                color: Color(0xFFB45309),
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    ];
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _paySuccessWidget() => Container(
        key: const ValueKey('success'),
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

  Widget _payButtonWidget() => GestureDetector(
        key: const ValueKey('pay'),
        onTap: _processPayment,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 46,
          decoration: BoxDecoration(
            color: widget.cart.isNotEmpty
                ? const Color(0xFF1E7DC8)
                : const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.payment_rounded,
                color: widget.cart.isNotEmpty
                    ? Colors.white
                    : const Color(0xFFB0B7C3),
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                'Провести оплату',
                style: TextStyle(
                  color: widget.cart.isNotEmpty
                      ? Colors.white
                      : const Color(0xFFB0B7C3),
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

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  const _SmallButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true, // ignore: unused_element_parameter
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled && onTap != null;
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
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
