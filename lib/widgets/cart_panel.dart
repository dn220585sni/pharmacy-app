import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/cart_item.dart';
import '../models/drug.dart';
import 'cart_item_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Payment method enum
// ─────────────────────────────────────────────────────────────────────────────

enum PaymentMethod { cash, card }

// ─────────────────────────────────────────────────────────────────────────────
// CustomerLoyalty — result from loyalty service after phone lookup.
// ─────────────────────────────────────────────────────────────────────────────

class CustomerLoyalty {
  final String phone;
  final double bonusBalance; // bonus points in ₴
  const CustomerLoyalty({required this.phone, required this.bonusBalance});
}

// ─────────────────────────────────────────────────────────────────────────────
// CartOffer — public model for pharmacist offer recommendations.
// Populated by PosScreen from a service; mock data used until service is ready.
// ─────────────────────────────────────────────────────────────────────────────

class CartOffer {
  final Drug drug;
  final String reason;
  const CartOffer({required this.drug, required this.reason});
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone prefix formatter — always keeps "+380 ", only digits allowed after it.
// ─────────────────────────────────────────────────────────────────────────────

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
    this.loyalty,
  });

  @override
  State<CartPanel> createState() => CartPanelState();
}

class CartPanelState extends State<CartPanel> {
  // ── Two-screen mode ────────────────────────────────────────────────────────
  bool _checkoutMode = false;
  bool _showPaymentSuccess = false;

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

  // ── Computed getters ──────────────────────────────────────────────────────

  double get _cartTotal => widget.cart.fold(0.0, (s, i) => s + i.total);
  int get _cartItemCount => widget.cart.fold(0, (s, i) => s + i.quantity);

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

  double? get _changeAmount {
    final text = _cashController.text.replaceAll(',', '.').replaceAll(' ', '');
    final cash = double.tryParse(text);
    if (cash == null) return null;
    return cash - _finalTotal;
  }

  /// Public method — allows PosScreen to enter checkout mode via F5
  void enterCheckout() {
    if (widget.cart.isEmpty) return;
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
          ),
        // Offers sit right under items
        if (widget.offers.isNotEmpty) _buildOffersSection(),
      ],
    );
  }

  // ── Offers section ────────────────────────────────────────────────────────

  Widget _buildOffersSection() {
    if (widget.offers.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    color: Color(0xFFF59E0B), size: 14),
                const SizedBox(width: 6),
                const Text(
                  'Турбота про клієнта',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          for (final offer in widget.offers) _buildOfferCard(offer),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildOfferCard(CartOffer offer) {
    final drug = offer.drug;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drug.name,
                    style: const TextStyle(
                      color: Color(0xFF1C1C2E),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    offer.reason,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            // Pharmacist bonus badge
            if (drug.pharmacistBonus != null) ...[
              const SizedBox(width: 6),
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F0E8),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${drug.pharmacistBonus}',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Text(
              '${drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => widget.onAddOffer(drug),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E7DC8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Додати',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Cart footer (simple total + "Розрахувати" button) ─────────────────────

  Widget _buildCartFooter() {
    final formattedTotal =
        _cartTotal.toStringAsFixed(2).replaceAll('.', ',');
    final hasItems = widget.cart.isNotEmpty;

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
          const SizedBox(height: 12),

          // "Розрахувати" button
          GestureDetector(
            onTap: hasItems ? enterCheckout : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              height: 46,
              decoration: BoxDecoration(
                color: hasItems
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calculate_outlined,
                    color: hasItems ? Colors.white : const Color(0xFFB0B7C3),
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Розрахувати',
                    style: TextStyle(
                      color:
                          hasItems ? Colors.white : const Color(0xFFB0B7C3),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (hasItems) ...[
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
    final hasLoyalty = widget.loyalty != null;

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

          // ── Bonuses + Discount block (appears after phone lookup) ────────
          if (hasLoyalty) ...[
            const SizedBox(height: 12),
            _buildBonusAndDiscountBlock(),
          ],

          const SizedBox(height: 14),

          // ── Payment method toggle ────────────────────────────────────────
          _buildPaymentMethodToggle(),
          const SizedBox(height: 10),

          // ── Pay / success button ─────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: _showPaymentSuccess
                ? _paySuccessWidget()
                : _payButtonWidget(),
          ),

          // ── Cash change section ──────────────────────────────────────────
          if (_paymentMethod == PaymentMethod.cash && !_showPaymentSuccess)
            _buildCashChangeSection(),

          const SizedBox(height: 8),

          // ── Secondary actions ────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                  child: _SmallButton(
                      icon: Icons.print_outlined,
                      label: 'Друк',
                      onTap: () {})),
              const SizedBox(width: 7),
              Expanded(
                  child: _SmallButton(
                      icon: Icons.pause_outlined,
                      label: 'Пауза',
                      onTap: () {})),
            ],
          ),
        ],
      ),
    );
  }

  // ── Combined bonuses + discount block ─────────────────────────────────────

  Widget _buildBonusAndDiscountBlock() {
    final loyalty = widget.loyalty!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE1F5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Bonus row ────────────────────────────────────────────────────
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _useBonuses,
                  onChanged: (v) {
                    setState(() {
                      _useBonuses = v ?? false;
                      if (_useBonuses) {
                        final max = _cartTotal - _discountAmount;
                        final capped = loyalty.bonusBalance.clamp(0, max);
                        _bonusController.text = capped.toStringAsFixed(0);
                      }
                    });
                  },
                  activeColor: const Color(0xFF1E7DC8),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Списати бонуси ',
                    style: const TextStyle(
                        color: Color(0xFF1C1C2E), fontSize: 12),
                    children: [
                      TextSpan(
                        text: '(доступно ${loyalty.bonusBalance.toStringAsFixed(2).replaceAll('.', ',')})',
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Bonus amount input (if checked)
          if (_useBonuses) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 28), // align with text above
                SizedBox(
                  width: 80,
                  height: 30,
                  child: TextField(
                    controller: _bonusController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[\d,.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C2E),
                    ),
                    decoration: InputDecoration(
                      suffixText: '₴',
                      suffixStyle: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 7),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFF1E7DC8)),
                      ),
                    ),
                  ),
                ),
                if (_effectiveBonusAmount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '-${_effectiveBonusAmount.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],

          // ── Divider ──────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Color(0xFFE5E7EB), height: 1),
          ),

          // ── Personal discount row ────────────────────────────────────────
          GestureDetector(
            onTap: () {
              if (_personalDiscount != null) {
                // Already applied — toggle off
                setState(() => _personalDiscount = null);
              } else {
                _requestDiscount();
              }
            },
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: _isLoadingDiscount
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF1E7DC8),
                          ),
                        )
                      : Checkbox(
                          value: _personalDiscount != null,
                          onChanged: (_) {
                            if (_personalDiscount != null) {
                              setState(() => _personalDiscount = null);
                            } else {
                              _requestDiscount();
                            }
                          },
                          activeColor: const Color(0xFF1E7DC8),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          side:
                              const BorderSide(color: Color(0xFFD1D5DB)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'Застосувати персон. знижку',
                      style: const TextStyle(
                          color: Color(0xFF1C1C2E), fontSize: 12),
                      children: [
                        if (_personalDiscount != null)
                          TextSpan(
                            text: '  -${_discountAmount.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Payment method toggle ─────────────────────────────────────────────────

  Widget _buildPaymentMethodToggle() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          _paymentSegment(
            icon: Icons.payments_outlined,
            label: 'Готівка',
            method: PaymentMethod.cash,
            isLeft: true,
          ),
          _paymentSegment(
            icon: Icons.credit_card,
            label: 'Картка',
            method: PaymentMethod.card,
            isLeft: false,
          ),
        ],
      ),
    );
  }

  Widget _paymentSegment({
    required IconData icon,
    required String label,
    required PaymentMethod method,
    required bool isLeft,
  }) {
    final isActive = _paymentMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _paymentMethod = method;
          if (method != PaymentMethod.cash) {
            _cashController.clear();
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: double.infinity,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1E7DC8) : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isLeft ? const Radius.circular(7) : Radius.zero,
              right: !isLeft ? const Radius.circular(7) : Radius.zero,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? Colors.white : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFF6B7280),
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Cash change section ───────────────────────────────────────────────────

  Widget _buildCashChangeSection() {
    final change = _changeAmount;
    final hasChange = change != null;
    final isPositive = hasChange && change >= 0;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Сума від клієнта:',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
                const Spacer(),
                SizedBox(
                  width: 100,
                  height: 32,
                  child: TextField(
                    controller: _cashController,
                    focusNode: _cashFocusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C2E),
                    ),
                    decoration: InputDecoration(
                      suffixText: '₴',
                      suffixStyle: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 13,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFF1E7DC8)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (hasChange)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      isPositive
                          ? Icons.check_circle_outline_rounded
                          : Icons.warning_amber_rounded,
                      size: 15,
                      color: isPositive
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Решта:',
                      style: TextStyle(
                          color: Color(0xFF6B7280), fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      '${change.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                      style: TextStyle(
                        color: isPositive
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
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
