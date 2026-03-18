import 'package:flutter/material.dart';
import '../mixins/checkout_mixin.dart';
import '../models/cart_item.dart';
import '../models/cart_offer.dart';
import '../models/customer_loyalty.dart';
import '../models/drug.dart';
import '../models/payment_method.dart';
import '../models/prescription.dart';
import '../services/bonus_service.dart';
import 'cart_item_widget.dart';
import 'cart_offer_card.dart';
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
  final VoidCallback? onFocusPhone;

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
    this.onFocusPhone,
  });

  @override
  State<CartPanel> createState() => CartPanelState();
}

class CartPanelState extends State<CartPanel> with CheckoutMixin {
  // ── Two-screen mode ────────────────────────────────────────────────────────
  bool _checkoutMode = false;
  bool _isProcessingPayment = false;

  // Scanned drug IDs (simulated barcode scan by tapping price)
  final Set<String> _scannedDrugIds = {};

  // Cash withdrawal (видача готівки з картки)
  bool _cashWithdrawal = false;
  final _cashWithdrawalController = TextEditingController();
  final _cashWithdrawalFocus = FocusNode();

  // Social projects
  String? _selectedSocialProject;

  // Prescription redemption (shown AFTER successful payment)
  final _redemptionCodeController = TextEditingController();
  final _redemptionCodeFocus = FocusNode();
  bool _isRedemptionVerified = false;
  bool _isVerifyingRedemption = false;
  bool _showRedemptionAfterPayment = false;
  // Snapshot of prescription data — persists after onPay clears the cart.
  PrescriptionCartData? _savedPrescriptionData;
  // Snapshot of fully-reimbursed flag — persists after onPay clears the cart.
  bool? _savedFullyReimbursed;

  // ── CheckoutMixin overrides ─────────────────────────────────────────────

  @override
  double get baseTotal => widget.cart.fold(0.0, (s, i) => s + i.total);

  @override
  CustomerLoyalty? get checkoutLoyalty => widget.loyalty;

  @override
  double get finalTotal {
    final raw = baseTotal - discountAmount - effectiveBonusAmount + _cashWithdrawalAmount;
    return raw < 0 ? 0 : raw;
  }

  // ── Cart-specific getters ───────────────────────────────────────────────

  double get _cashWithdrawalAmount {
    if (!_cashWithdrawal || paymentMethod != PaymentMethod.card) return 0;
    final text = _cashWithdrawalController.text.replaceAll(',', '.').replaceAll(' ', '');
    return double.tryParse(text) ?? 0;
  }

  /// Whether payment can be processed.
  /// For cash/mixed: requires entered amount ≥ finalTotal.
  /// For card: always allowed.
  bool get _canProcessPayment {
    if (widget.cart.isEmpty) return false;
    if (paymentMethod == PaymentMethod.card) return true;
    // Cash or mixed — must have sufficient cash entered
    final text =
        cashCtr.text.replaceAll(',', '.').replaceAll(' ', '');
    final cash = double.tryParse(text);
    if (cash == null) return false;
    return cash >= finalTotal;
  }

  /// Whether cart contains prescription items (or had them before payment).
  bool get _hasPrescriptionItems =>
      widget.cart.any((i) => i.isPrescription) ||
      _savedPrescriptionData != null;

  /// First prescription data found in cart, or saved snapshot after payment.
  PrescriptionCartData? get _prescriptionData {
    final fromCart = widget.cart.where((i) => i.isPrescription);
    if (fromCart.isNotEmpty) return fromCart.first.prescriptionData;
    return _savedPrescriptionData;
  }

  /// Whether this prescription checkout needs a redemption code.
  /// Paper 1303 prescriptions do not require redemption.
  bool get _needsRedemptionCode =>
      _prescriptionData?.needsRedemptionCode ?? false;

  /// Whether all prescription items are 100% reimbursed (copayment == 0).
  /// In this case no payment is needed — only redemption code verification.
  /// Uses saved snapshot after onPay clears the cart.
  bool get _isFullyReimbursed {
    if (_savedFullyReimbursed != null) return _savedFullyReimbursed!;
    if (!_hasPrescriptionItems) return false;
    final rxItems = widget.cart.where((i) => i.isPrescription);
    if (rxItems.isEmpty) return false;
    return rxItems.every((i) => i.prescriptionData!.copayment <= 0);
  }

  /// Whether we're in a state where redemption is required but not yet done.
  bool get _isRedemptionPending =>
      _hasPrescriptionItems &&
      _needsRedemptionCode &&
      !_isRedemptionVerified &&
      (showPaymentSuccess || _isFullyReimbursed);

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

    // Auto-fill social project from prescription program if present
    if (_hasPrescriptionItems) {
      final rxData = _prescriptionData;
      if (rxData != null) {
        _selectedSocialProject =
            _mapProgramToSocialProject(rxData.programName);
      }
    }
    if (_isFullyReimbursed && _needsRedemptionCode) {
      // 100% reimbursed → focus the redemption code field
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redemptionCodeFocus.requestFocus();
      });
    } else {
      // Default is cash → auto-focus the cash amount field
      WidgetsBinding.instance.addPostFrameCallback((_) {
        cashFocus.requestFocus();
      });
    }
  }

  /// Map prescription program name to social project.
  static String? _mapProgramToSocialProject(String program) {
    if (program.contains('1303')) return 'Паперові 1303';
    if (program.contains('Доступні ліки') || program.contains('Реімбурсація')) {
      return 'Реімбурсація';
    }
    if (program.contains('Рецептурний')) return 'Рецептурний відпуск';
    return null;
  }

  /// Public method — allows PosScreen to exit checkout back to cart
  void exitCheckout() {
    if (_isRedemptionPending) {
      _confirmExitWithoutRedemption(() => _closeAfterPayment());
      return;
    }
    setState(() => _checkoutMode = false);
  }

  bool get isInCheckout => _checkoutMode;

  @override
  void switchToCard() {
    if (!_checkoutMode) return;
    super.switchToCard();
  }

  /// Public method — F5 processes payment when already in checkout
  void processPayment() => _processPayment();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void didUpdateWidget(covariant oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-fetch available discount when loyalty card is first linked
    if (oldWidget.loyalty == null && widget.loyalty != null && availableDiscount == null) {
      _fetchAvailableDiscount();
    }
    // Reset when loyalty removed
    if (widget.loyalty == null && availableDiscount != null) {
      availableDiscount = null;
    }
  }

  @override
  void dispose() {
    disposeCheckout();
    _cashWithdrawalController.dispose();
    _cashWithdrawalFocus.dispose();
    _redemptionCodeController.dispose();
    _redemptionCodeFocus.dispose();
    super.dispose();
  }

  // ── Mock discount service ─────────────────────────────────────────────────

  /// Pre-fetch discount % as soon as loyalty is linked (without activating it).
  Future<void> _fetchAvailableDiscount() async {
    if (widget.loyalty == null) return;
    final lastDigit = widget.loyalty!.phone.characters.last;
    final d = int.tryParse(lastDigit) ?? 0;
    final discount = d >= 5 ? d.toDouble() : null;
    // Simulate short network delay
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => availableDiscount = discount);
  }

  Future<void> _requestDiscount() async {
    if (widget.loyalty == null || isLoadingDiscount) return;
    if (availableDiscount != null) {
      // Already fetched — just activate
      setState(() => personalDiscount = availableDiscount);
      return;
    }
    setState(() => isLoadingDiscount = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final lastDigit = widget.loyalty!.phone.characters.last;
    final d = int.tryParse(lastDigit) ?? 0;
    final discount = d >= 5 ? (d.toDouble()) : null;
    setState(() {
      availableDiscount = discount;
      personalDiscount = discount;
      isLoadingDiscount = false;
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

  Future<void> _processPayment() async {
    if (!_canProcessPayment || _isProcessingPayment) return;

    final bonusAmount = effectiveBonusAmount;
    final hasBonusWriteOff = useBonuses && bonusAmount > 0 && widget.loyalty != null;

    // ── Step 1: write off bonuses on the server ──────────────────────────
    if (hasBonusWriteOff) {
      setState(() => _isProcessingPayment = true);
      try {
        final result = await BonusService.writeOff(
          clientCode: widget.loyalty!.phone,
          amount: bonusAmount,
        );
        if (!mounted) return;
        if (!result.success) {
          setState(() => _isProcessingPayment = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Не вдалося списати бонуси'),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Помилка зʼєднання: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    // ── Step 2: complete payment ─────────────────────────────────────────
    // Capture prescription state BEFORE onPay (which clears the cart).
    final hadPrescription = _hasPrescriptionItems;
    final neededRedemption = _needsRedemptionCode;
    final rxDataSnapshot = _prescriptionData;
    final wasFullyReimbursed = _isFullyReimbursed;

    widget.onPay();
    setState(() {
      _isProcessingPayment = false;
      showPaymentSuccess = true;
      // Persist prescription data so redemption section can render
      // even after cart is cleared by onPay.
      if (hadPrescription && rxDataSnapshot != null) {
        _savedPrescriptionData = rxDataSnapshot;
      }
      _savedFullyReimbursed = wasFullyReimbursed;
    });

    if (hadPrescription && neededRedemption) {
      // Prescription checkout: show redemption code input after short delay
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() => _showRedemptionAfterPayment = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _redemptionCodeFocus.requestFocus();
        });
      });
    } else {
      // Normal checkout: auto-close after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _closeAfterPayment();
      });
    }
  }

  /// Show warning when pharmacist tries to exit with unredeemed prescription.
  Future<void> _confirmExitWithoutRedemption(VoidCallback onConfirm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: const Icon(Icons.warning_amber_rounded,
            color: Color(0xFFF59E0B), size: 36),
        title: const Text(
          'Рецепт не погашено',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Ви маєте погасити рецепт клієнта.\n'
          'Ви точно хочете завершити цю транзакцію?',
          style: TextStyle(fontSize: 13.5, height: 1.4),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ні, погасити рецепт',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Так, завершити',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }

  /// Attempt to close — checks if redemption is pending first.
  void _tryClose() {
    if (_isRedemptionPending) {
      _confirmExitWithoutRedemption(() => _closeAfterPayment());
    } else {
      widget.onClose();
    }
  }

  /// Attempt to go back from checkout — checks if redemption is pending first.
  void _tryBackFromCheckout() {
    if (_isRedemptionPending) {
      _confirmExitWithoutRedemption(() => _closeAfterPayment());
    } else {
      _resetCheckoutState();
      setState(() => _checkoutMode = false);
    }
  }

  void _closeAfterPayment() {
    setState(() {
      _checkoutMode = false;
      _resetCheckoutState();
    });
    widget.onClose();
  }

  void _resetCheckoutState() {
    resetCheckout();
    _scannedDrugIds.clear();
    _redemptionCodeController.clear();
    _isRedemptionVerified = false;
    _isVerifyingRedemption = false;
    _showRedemptionAfterPayment = false;
    _savedPrescriptionData = null;
    _savedFullyReimbursed = null;
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
    return CartOfferCard(
      offer: offer,
      onAddPackage: widget.onAddOffer,
      onAddBlister: widget.onAddOfferBlister,
    );
  }

  // ── Cart footer (simple total + "Розрахувати" button) ─────────────────────

  Widget _buildCartFooter() {
    final formattedTotal =
        baseTotal.toStringAsFixed(2).replaceAll('.', ',');
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
            onTap: _tryBackFromCheckout,
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
          GestureDetector(
            onTap: _tryClose,
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

  // ── Social projects section ─────────────────────────────────────────────

  static const _socialProjects = [
    'Care365',
    'EPRUF',
    'ІОЦ «За Рівні Права»',
    'Алерговакцини',
    'БО Асістанс',
    'БФ Карітас',
    'ГО «Азов Супровід»',
    'Ебот кард',
    'Знижка для УБД',
    'МП Налбуфін',
    'Медікард',
    'Паперові 1303',
    'Реімбурсація',
    'Рецептурний відпуск',
    'Сантен',
    'Серце Азовсталі',
    'Серце Азовсталі Ліки',
    'Сонафарм',
    'Центр прав. рішень',
  ];

  Widget _buildSocialProjectsSection() {
    final isSelected = _selectedSocialProject != null;

    return GestureDetector(
      onTap: () => _showSocialProjectPicker(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1E7DC8)
                : const Color(0xFFDDE1F5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.volunteer_activism_rounded,
              size: 18,
              color: isSelected
                  ? const Color(0xFF1E7DC8)
                  : const Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isSelected ? _selectedSocialProject! : 'Соціальні проекти',
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFF1C1C2E)
                      : const Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected) ...[
              GestureDetector(
                onTap: () => setState(() => _selectedSocialProject = null),
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.close_rounded,
                      size: 15, color: Color(0xFF9CA3AF)),
                ),
              ),
            ] else
              const Icon(Icons.unfold_more_rounded,
                  size: 16, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  void _showSocialProjectPicker() {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = box.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx + 14,
        position.dy,
        position.dx + box.size.width - 14,
        position.dy + box.size.height,
      ),
      constraints: const BoxConstraints(maxHeight: 320, maxWidth: 260),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: Colors.white,
      elevation: 6,
      items: _socialProjects.map((name) {
        final isActive = _selectedSocialProject == name;
        return PopupMenuItem<String>(
          value: name,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? const Color(0xFF1E7DC8)
                        : const Color(0xFF1C1C2E),
                  ),
                ),
              ),
              if (isActive)
                const Icon(Icons.check_rounded,
                    size: 15, color: Color(0xFF1E7DC8)),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null) {
        setState(() => _selectedSocialProject = value);
      }
    });
  }

  // ── Prescription checkout section ──────────────────────────────────────────

  Widget _buildPrescriptionCheckoutSection() {
    final rxData = _prescriptionData;
    if (rxData == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label ──────────────────────────────────────────────────────
          Row(
            children: const [
              Icon(Icons.health_and_safety,
                  size: 14, color: Color(0xFF16A34A)),
              SizedBox(width: 6),
              Text('Погашення рецепту',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF16A34A))),
            ],
          ),
          const SizedBox(height: 8),

          // ── Рецепт (read-only, auto-filled) ────────────────────────────
          _rxReadOnlyField('Рецепт', rxData.prescriptionNumber),
          const SizedBox(height: 6),

          // ── Соц.проект (read-only, auto-filled) ────────────────────────
          _rxReadOnlyField(
              'Соц.проект', _selectedSocialProject ?? rxData.programName),
          const SizedBox(height: 8),

          // ── Код погашення ──────────────────────────────────────────────
          const Text('Код погашення рецепту',
              style: TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _redemptionCodeController,
                    focusNode: _redemptionCodeFocus,
                    enabled: !_isRedemptionVerified,
                    style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8),
                    onSubmitted: (_) => _verifyRedemptionCode(),
                    decoration: InputDecoration(
                      hintText: 'Введіть код',
                      hintStyle: TextStyle(
                          fontSize: 12, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: _isRedemptionVerified
                          ? const Color(0xFFECFDF5)
                          : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide:
                            const BorderSide(color: Color(0xFFBBF7D0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: BorderSide(
                            color: _isRedemptionVerified
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFBBF7D0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: const BorderSide(
                            color: Color(0xFF16A34A), width: 1.5),
                      ),
                      suffixIcon: _isRedemptionVerified
                          ? const Icon(Icons.check_circle,
                              size: 18, color: Color(0xFF16A34A))
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: ElevatedButton(
                  onPressed: _isRedemptionVerified || _isVerifyingRedemption
                      ? null
                      : _verifyRedemptionCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRedemptionVerified
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFF16A34A),
                    foregroundColor: _isRedemptionVerified
                        ? const Color(0xFF16A34A)
                        : Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7)),
                  ),
                  child: _isVerifyingRedemption
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          _isRedemptionVerified
                              ? 'Погашено'
                              : 'Погасити',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rxReadOnlyField(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Text(value,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF15803D)),
                overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }

  /// Mock API call to verify prescription redemption code.
  Future<void> _verifyRedemptionCode() async {
    final code = _redemptionCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isVerifyingRedemption = true);
    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _isVerifyingRedemption = false;
      _isRedemptionVerified = true;
    });

    // For fully reimbursed: trigger onPay callback now (no prior payment)
    if (_isFullyReimbursed && !showPaymentSuccess) {
      widget.onPay();
    }

    // Close cart after a short pause so the user sees the "Погашено" state
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _closeAfterPayment();
    });
  }

  // ── Checkout body: total → bonuses/discount → payment → pay → change ────

  Widget _buildCheckoutBody() {
    final formattedTotal =
        finalTotal.toStringAsFixed(2).replaceAll('.', ',');

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

          // ── Fully reimbursed: skip payment, go straight to redemption ──
          if (_isFullyReimbursed) ...[
            const SizedBox(height: 12),
            // Green info: 100% reimbursement
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified_rounded,
                          size: 16, color: Color(0xFF16A34A)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '100% реімбурсація — оплата клієнта не потрібна',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_needsRedemptionCode) ...[
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.only(left: 24),
                      child: Text(
                        'Обовʼязково погасіть рецепт через введення коду '
                        'і тільки потім віддайте товар і чек.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF15803D),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Social projects ──────────────────────────────────────────
            _buildSocialProjectsSection(),
            const SizedBox(height: 12),

            // Redemption code section shown directly
            if (_needsRedemptionCode) _buildPrescriptionCheckoutSection(),
          ] else ...[
            // ── Normal checkout: bonuses + discount + payment ─────────────

            // ── Bonuses + Discount block (always visible, disabled w/o loyalty)
            const SizedBox(height: 12),
            BonusDiscountBlock(
              loyalty: widget.loyalty,
              useBonuses: useBonuses,
              onUseBonusesChanged: (v) {
                setState(() {
                  useBonuses = v;
                  if (useBonuses && widget.loyalty != null) {
                    final max = baseTotal - discountAmount;
                    final capped =
                        widget.loyalty!.bonusBalance.clamp(0, max);
                    bonusCtr.text = capped.toStringAsFixed(0);
                  }
                });
              },
              bonusController: bonusCtr,
              cartTotal: baseTotal,
              discountAmount: discountAmount,
              effectiveBonusAmount: effectiveBonusAmount,
              personalDiscount: personalDiscount,
              availableDiscountAmount: availableDiscount != null
                  ? baseTotal * availableDiscount! / 100
                  : null,
              isLoadingDiscount: isLoadingDiscount,
              onRequestDiscount: _requestDiscount,
              onClearDiscount: () =>
                  setState(() => personalDiscount = null),
              onBonusAmountChanged: () => setState(() {}),
            ),

            const SizedBox(height: 10),

            // ── Social projects ────────────────────────────────────────────
            _buildSocialProjectsSection(),

            const SizedBox(height: 14),

            // ── Payment method toggle ────────────────────────────────────────
            PaymentMethodToggle(
              selectedMethod: paymentMethod,
              onMethodChanged: (method) => setState(() {
                paymentMethod = method;
                if (method == PaymentMethod.cash) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    cashFocus.requestFocus();
                  });
                } else {
                  cashCtr.clear();
                }
                if (method != PaymentMethod.card) {
                  _cashWithdrawal = false;
                  _cashWithdrawalController.clear();
                }
              }),
            ),

            // ── Cash withdrawal (card only) ───────────────────────────────────
            if (paymentMethod == PaymentMethod.card && !showPaymentSuccess) ...[
              const SizedBox(height: 10),
              _buildCashWithdrawalSection(),
            ],

            // ── Cash: amount from client + change ────────────────────────────
            if (paymentMethod == PaymentMethod.cash && !showPaymentSuccess)
              CashChangeSection(
                cashController: cashCtr,
                cashFocusNode: cashFocus,
                finalTotal: finalTotal,
                onChanged: () => setState(() {}),
                showBonusTransfer: true,
                hasLoyalty: widget.loyalty != null,
                transferChangeToBonus: transferChangeToBonus,
                onTransferChangeToBonusChanged: (v) =>
                    setState(() => transferChangeToBonus = v),
                bonusTransferController: bonusTransferCtr,
                bonusTransferFocusNode: bonusTransferFocus,
                onBonusTransferAmountChanged: () => setState(() {}),
                onFocusPhone: widget.onFocusPhone,
              ),

            const SizedBox(height: 10),

            // ── Cash hint — ask to enter amount ────────────────────────────
            if (!showPaymentSuccess &&
                paymentMethod != PaymentMethod.card &&
                !_canProcessPayment)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: Color(0xFF1E7DC8),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Введіть суму готівки від клієнта',
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
              ),

            // ── Pay / success button ─────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: showPaymentSuccess
                  ? _paySuccessWidget()
                  : _payButtonWidget(),
            ),

            // ── Prescription redemption code (after payment) ───────────────
            if (showPaymentSuccess && _showRedemptionAfterPayment) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 15, color: Color(0xFF16A34A)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Оплата успішна! Обовʼязково погасіть рецепт '
                        'через введення коду і тільки потім '
                        'віддайте товар і чек.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF15803D),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildPrescriptionCheckoutSection(),
            ],
          ],

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

  // ── Cash withdrawal section (card payment) ────────────────────────────────

  Widget _buildCashWithdrawalSection() {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: _cashWithdrawal,
              onChanged: (v) => setState(() {
                _cashWithdrawal = v ?? false;
                if (_cashWithdrawal) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _cashWithdrawalFocus.requestFocus();
                  });
                } else {
                  _cashWithdrawalController.clear();
                }
              }),
              activeColor: const Color(0xFF1E7DC8),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Видати готівку з картки клієнта',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 12,
            ),
          ),
          if (_cashWithdrawal) ...[
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 28,
                child: TextField(
                  controller: _cashWithdrawalController,
                  focusNode: _cashWithdrawalFocus,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C2E),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 7),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    suffixText: '₴',
                    suffixStyle: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                    ),
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
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ],
        ],
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

  Widget _payButtonWidget() {
    final enabled = _canProcessPayment && !_isProcessingPayment;
    return GestureDetector(
        key: const ValueKey('pay'),
        onTap: enabled ? _processPayment : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 46,
          decoration: BoxDecoration(
            color: enabled
                ? const Color(0xFF1E7DC8)
                : _isProcessingPayment
                    ? const Color(0xFF1E7DC8).withValues(alpha: 0.7)
                    : const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isProcessingPayment) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Списання бонусів…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else ...[
                Icon(
                  Icons.payment_rounded,
                  color: enabled
                      ? Colors.white
                      : const Color(0xFFB0B7C3),
                  size: 18,
                ),
                const SizedBox(width: 7),
                Text(
                  'Провести оплату',
                  style: TextStyle(
                    color: enabled
                        ? Colors.white
                        : const Color(0xFFB0B7C3),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(3),
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
            ],
          ),
        ),
      );
  }
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
