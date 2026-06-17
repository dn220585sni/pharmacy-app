import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../mixins/checkout_mixin.dart';
import '../models/cart_item.dart';
import '../models/cart_offer.dart';
import '../models/customer_loyalty.dart';
import '../models/drug.dart';
import '../models/money.dart';
import '../models/payment_method.dart';
import '../models/prescription.dart';
import '../models/payment_terminal.dart';
import '../models/social_project.dart';
import '../models/stop_price_action.dart';
import '../services/api_config.dart';
import '../services/cart_price_service.dart';
import '../services/terminal_service.dart';
import '../services/prro_queue.dart';
import '../services/prro_service.dart';
import '../services/skarb_service.dart';
import 'cart_item_widget.dart';
import 'cart_offer_card.dart';
import 'checkout/bonus_discount_block.dart';
import 'checkout/cash_change_section.dart';
import 'checkout/payment_method_toggle.dart';
import 'prro_receipt_dialog.dart';

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
  final void Function({double paidByPoints}) onPay;
  final VoidCallback onClose;
  final void Function(Drug drug) onAddOffer;
  final void Function(Drug drug) onAddOfferBlister;
  final CustomerLoyalty? loyalty;
  final VoidCallback? onFocusPhone;
  /// Серверна калькуляція цін (`GetSumSkid`) — джерело правди для UI.
  /// Обчислюється у `PosScreen` (parent), щоб глобальний UI бачив ту ж суму.
  final CartPricing? serverPricing;
  /// Чи зараз триває запит до сервера. UI показує спінер біля суми.
  final bool isLoadingPricing;
  /// Перелік соц-програм (server + always-shown local) — з `pos_screen`.
  final List<SocialProject> socialProjects;
  /// Активні акції на товари кошика (key = `drug.ukod`).
  final Map<String, List<StopPriceAction>> stopPrices;
  /// Чи активний режим "Пакунок Малюка". Накладає обмеження на оплату:
  /// тільки картка, тільки контактна (чіп/магнітна стрічка), без NFC.
  final bool isPakunokMode;

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
    this.serverPricing,
    this.isLoadingPricing = false,
    this.socialProjects = const [],
    this.stopPrices = const {},
    this.isPakunokMode = false,
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

  // Платіжні термінали (GetTermBank). Основний привʼязаний до каси; резервний
  // обирається вручну при поломці основного. Обраний kodterm піде в накладну
  // (впливає на контрагента), не в ПРРО.
  List<PaymentTerminal> _terminals = const [];
  PaymentTerminal? _selectedTerminal;
  bool _terminalsLoading = false;

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
    // Якщо є відповідь з сервера — пріоритет. Cash withdrawal накладаємо
    // зверху бо це окрема операція (видача готівки), не частина чеку.
    final base = widget.serverPricing?.total ??
        (baseTotal - discountAmount - effectiveBonusAmount);
    final raw = base + _cashWithdrawalAmount;
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
  /// Завжди вимагає актуальної ціни з сервера (бо інакше можемо взяти
  /// застарілу/локальну калькуляцію).
  bool get _canProcessPayment {
    if (widget.cart.isEmpty) return false;
    if (widget.isLoadingPricing || widget.serverPricing == null) return false;
    // Пакунок Малюка — тільки безготівка через термінал.
    if (widget.isPakunokMode && paymentMethod != PaymentMethod.card) {
      return false;
    }
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
    _ensureTerminalsLoaded(); // підвантажити платіжні термінали (для картки)

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

  // ── Платіжний термінал (GetTermBank) ────────────────────────────────────────

  Future<void> _ensureTerminalsLoaded() async {
    if (_terminals.isNotEmpty || _terminalsLoading) return;
    setState(() => _terminalsLoading = true);
    final list = await TerminalService.getTerminals();
    if (!mounted) return;
    setState(() {
      _terminals = list;
      _selectedTerminal = TerminalService.mainOf(list);
      _terminalsLoading = false;
    });
  }

  /// Селектор платіжного термінала (показується при оплаті карткою).
  /// Дефолт — основний; якщо терміналів кілька, можна обрати резервний.
  Widget _buildTerminalSelector() {
    if (_terminalsLoading) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Row(
          children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Завантаження терміналів…',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ],
        ),
      );
    }
    if (_terminals.isEmpty) return const SizedBox.shrink();
    final sel = _selectedTerminal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.point_of_sale_outlined,
              size: 16, color: Color(0xFF6B7280)),
          const SizedBox(width: 8),
          const Text('Термінал',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280))),
          const SizedBox(width: 10),
          Expanded(
            child: _terminals.length == 1
                ? Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      sel?.displayName ?? '',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : DropdownButton<PaymentTerminal>(
                    value: sel,
                    isExpanded: true,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: _terminals
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(
                                t.isMain
                                    ? '${t.displayName} • основний'
                                    : t.displayName,
                                style: const TextStyle(fontSize: 12.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (t) => setState(() => _selectedTerminal = t),
                  ),
          ),
        ],
      ),
    );
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
  void processPayment() => unawaited(_processPayment());

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

    // Пакунок Малюка — показати інструкцію оплати перед фіскалізацією.
    if (widget.isPakunokMode) {
      final ok = await _showPakunokPaymentInstruction();
      if (ok != true) return;
    }

    // Capture state BEFORE clearing cart.
    final hadPrescription = _hasPrescriptionItems;
    final neededRedemption = _needsRedemptionCode;
    final rxDataSnapshot = _prescriptionData;
    final wasFullyReimbursed = _isFullyReimbursed;

    setState(() => _isProcessingPayment = true);

    // Skip PRRO for fully-reimbursed prescription checkouts (no money, no fiscal check).
    final skipPrro = wasFullyReimbursed;

    if (!skipPrro) {
      final ok = await _sendFiscalReceipt();
      if (!mounted) return;
      if (!ok) {
        setState(() => _isProcessingPayment = false);
        return;
      }
    }

    // Bonus write-off is handled by Sparta LoyaltyService.sale()
    // in POS._processPayment() — fire-and-forget, no blocking here.
    widget.onPay(paidByPoints: effectiveBonusAmount);
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

  /// Зареєструвати фіскальний чек у ПРРО.
  ///
  /// Повертає `true` якщо можна продовжити продаж:
  /// - успіх → показав preview, далі onPay
  /// - connection error → поклав у чергу, продовжуємо
  /// - логічна помилка ПРРО → блок (`false`)
  Future<bool> _sendFiscalReceipt() async {
    final products = _buildPrroProducts();
    // Сума рядків у копійках (без float-дрейфу), потім назад у грн.
    final saleTotal = products
        .fold(Money.zero, (Money s, p) => s + Money.fromHryvnia(p.cost))
        .toHryvnia();
    // Payments вирівнюються з sum(products.cost) — інакше ПРРО відхилить
    // ("payments not equal products sum"). Округлення на чек (skidka_sumcheck)
    // і cash_withdrawal — поки не передаємо у ПРРО.
    final payments = _buildPrroPayments(saleTotal);

    // TODO(local_number): підмінити timestamp на реальний номер з sgVRoznSale
    // (Caché реєстрація роздрібного продажу) коли її буде реалізовано.
    final localNumber = DateTime.now().millisecondsSinceEpoch % 10000000000;

    final result = await PrroService.createSaleReceipt(
      products: products,
      payments: payments,
      totalSum: saleTotal,
      localNumber: localNumber,
    );

    if (!mounted) return false;

    if (result.success) {
      await PrroReceiptDialog.show(context, result);
      // Спробувати скинути попередньо відкладені чеки у фоні.
      unawaited(PrroQueue.flush());
      return mounted;
    }

    if (result.errorKind == PrroErrorKind.connection) {
      await PrroQueue.enqueueSale(
        products: products,
        payments: payments,
        totalSum: saleTotal,
        localNumber: localNumber,
        error: result.error,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ПРРО недоступний — чек відкладено в чергу '
              '(буде надіслано пізніше)',
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB45309),
          ),
        );
      }
      return mounted;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Помилка ПРРО: ${result.error ?? "невідома"}'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
    return false;
  }

  /// Сформувати список товарів для фіскального чеку.
  ///
  /// Payload товарів дзеркалить кошик (ті самі `item.*`, що показані клієнту),
  /// щоб сума чека ПРРО точно дорівнювала кошику. Серверне per-item ціноутворення
  /// тут НЕ використовуємо: його `itemAt` може бути зміщене відносно порядку
  /// кошика, що давало чужу ціну в чеку.
  List<PrroProduct> _buildPrroProducts() {
    final items = widget.cart;
    if (items.isEmpty) return const [];

    return List.generate(items.length, (i) {
      final item = items[i];
      final isFractional = item.isFractional;

      // ПРРО вимагає cost == price * amount. Щоб рівність трималась точно,
      // одиниця продажу має бути цілою: для блістерів — це БЛІСТЕР (price за
      // блістер у копійках, amount = ціле число блістерів), а не дробова
      // частка паковки (де price*amount = нескінченний дріб і ПРРО відхиляє).
      final Money unitMoney =
          isFractional ? item.blisterPriceMoney : Money.fromHryvnia(item.effectivePrice);
      final double amount =
          isFractional ? item.fractionalQty!.toDouble() : item.quantity.toDouble();

      // price і cost — чисті 2 знаки (через Money). cost == item.totalMoney,
      // тож чек збігається з кошиком до копійки.
      final price = unitMoney.toHryvnia();
      final cost = item.totalMoney.toHryvnia();

      return PrroProduct.classified(
        name: item.drug.displayName,
        amount: amount,
        price: price,
        cost: cost,
        isMedicine: item.drug.isMedicine,
        code: item.drug.skuCode,
        barcode: item.drug.barcode,
        unitName: isFractional ? 'блістер' : 'штука',
      );
    }, growable: false);
  }

  /// Інструкція оплати для Пакунка Малюка — лише контактна оплата
  /// (NFC заборонено, треба вставити чіп або провести магнітною стрічкою).
  Future<bool?> _showPakunokPaymentInstruction() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: const Icon(Icons.credit_card,
            color: Color(0xFF1E7DC8), size: 36),
        title: const Text(
          'Пакунок Малюка — оплата',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Картка Пакунка Малюка приймає лише КОНТАКТНУ оплату.',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Text(
              '✓ Вставте картку чіпом у термінал\n'
              '✓ Або проведіть магнітною стрічкою\n\n'
              '✗ NFC (безконтактно) НЕ приймається',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Скасувати'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E7DC8),
              foregroundColor: Colors.white,
            ),
            child: const Text('Продовжити оплату'),
          ),
        ],
      ),
    );
  }

  /// Сформувати список оплат. Сума має точно співпадати з `sum(products.cost)`
  /// (звідси параметр [saleAmount]), інакше ПРРО відхилить.
  /// Cash withdrawal (видача готівки понад чек) поки не передається у ПРРО.
  List<PrroPayment> _buildPrroPayments(double saleAmount) {
    if (paymentMethod == PaymentMethod.card) {
      return [PrroPayment.card(sum: saleAmount)];
    }
    final providedText = cashCtr.text.replaceAll(',', '.');
    final provided = double.tryParse(providedText) ?? saleAmount;
    return [PrroPayment.cash(sum: saleAmount, provided: provided)];
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
            serverUnitPrice: widget.serverPricing?.itemAt(i)?.unitPrice,
            serverCost: widget.serverPricing?.itemAt(i)?.cost,
            actions: widget.stopPrices[widget.cart[i].drug.ukod] ?? const [],
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
    // Показуємо серверну фінальну суму (з усіма знижками) — `finalTotal`
    // повертає її коли є server pricing, інакше fallback на baseTotal.
    final formattedTotal =
        finalTotal.asMoney;
    final hasItems = widget.cart.isNotEmpty;
    final canCheckout = hasItems && _allCartScanned && !widget.isLoadingPricing;

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
              if (widget.isLoadingPricing) ...[
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E7DC8)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              AnimatedOpacity(
                opacity: widget.isLoadingPricing ? 0.45 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  '$formattedTotal ₴',
                  style: const TextStyle(
                    color: Color(0xFF1E7DC8),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
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
                onTap: () {
                  setState(() => _selectedSocialProject = null);
                },
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
      items: widget.socialProjects.map((p) {
        final isActive = _selectedSocialProject == p.name;
        return PopupMenuItem<String>(
          value: p.name,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  p.name,
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

          // ── Код погашення / PIN-код ───────────────────────────────────
          Text(
              rxData.isSkarb
                  ? 'PIN-код пацієнта (4 цифри)'
                  : 'Код погашення рецепту',
              style: const TextStyle(
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
                    maxLength: rxData.isSkarb ? 4 : null,
                    keyboardType: rxData.isSkarb ? TextInputType.number : null,
                    style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8),
                    onSubmitted: (_) => _verifyRedemptionCode(),
                    decoration: InputDecoration(
                      counterText: '', // hide maxLength counter
                      hintText: rxData.isSkarb ? '0000' : 'Введіть код',
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

    final rxData = _prescriptionData;
    final isSkarb = rxData?.isSkarb ?? false;

    // Skarb: PIN must be 4 digits
    if (isSkarb && (code.length != 4 || int.tryParse(code) == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN-код має бути 4 цифри')),
      );
      return;
    }

    setState(() => _isVerifyingRedemption = true);

    if (isSkarb && !ApiConfig.useMock) {
      await _processSkarbDispense(code, rxData!);
    } else {
      // Mock: simulate API call
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      setState(() {
        _isVerifyingRedemption = false;
        _isRedemptionVerified = true;
      });
      _onRedemptionSuccess();
    }
  }

  /// Погашення рецепта через Skarb Cloud API.
  Future<void> _processSkarbDispense(
      String pinCode, PrescriptionCartData rxData) async {
    // Collect Skarb IDs from prescription cart items
    final rxItems = widget.cart.where((i) => i.isPrescription).toList();
    final medicationIds = <String>[];
    final participantIds = <String>[];
    final prices = <double>[];
    final quantities = <int>[];

    for (final item in rxItems) {
      final pd = item.prescriptionData!;
      if (pd.skarbMedicationId != null) {
        medicationIds.add(pd.skarbMedicationId!);
      }
      if (pd.skarbParticipantId != null) {
        participantIds.add(pd.skarbParticipantId!);
      }
      prices.add(item.drug.price);
      quantities.add(item.quantity);
    }

    final paymentAmount = _isFullyReimbursed ? 0.0 : finalTotal;

    final result = await SkarbService.processDispenseViaSmartSign(
      code: pinCode,
      medicalProgramId: rxData.skarbMedicalProgramId ?? '',
      medicationRequestId: rxData.skarbMedicationRequestId ?? '',
      medicationIds: medicationIds,
      participantIds: participantIds,
      prices: prices,
      quantities: quantities,
      paymentAmount: paymentAmount,
      paymentId: DateTime.now().millisecondsSinceEpoch.toString(),
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _isVerifyingRedemption = false;
        _isRedemptionVerified = true;
      });
      _onRedemptionSuccess();
    } else {
      // SmartSign failed — try fallback with init-dispense-form
      final fallback = await SkarbService.initDispenseForm(
        code: pinCode,
        medicalProgramId: rxData.skarbMedicalProgramId ?? '',
        medicationRequestId: rxData.skarbMedicationRequestId ?? '',
        medicationIds: medicationIds,
        participantIds: participantIds,
        prices: prices,
        quantities: quantities,
        paymentAmount: paymentAmount,
        paymentId: DateTime.now().millisecondsSinceEpoch.toString(),
      );

      if (!mounted) return;

      if (fallback.success && fallback.data!.url.isNotEmpty) {
        setState(() => _isVerifyingRedemption = false);
        // Open manual signing URL
        final url = Uri.tryParse(fallback.data!.url);
        if (url != null) {
          launchUrl(url, mode: LaunchMode.externalApplication);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Відкрито сторінку підпису. '
                  'Після підпису натисніть "Погасити" знову.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      } else {
        setState(() => _isVerifyingRedemption = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.error ?? 'Помилка погашення')),
          );
        }
      }
    }
  }

  /// Спільна логіка після успішного погашення.
  void _onRedemptionSuccess() {
    // For fully reimbursed: trigger onPay callback now (no prior payment)
    if (_isFullyReimbursed && !showPaymentSuccess) {
      widget.onPay(paidByPoints: 0);
    }

    // Close cart after a short pause so the user sees the "Погашено" state
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _closeAfterPayment();
    });
  }

  // ── Checkout body: total → bonuses/discount → payment → pay → change ────

  Widget _buildCheckoutBody() {
    final formattedTotal =
        finalTotal.asMoney;

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
              if (widget.isLoadingPricing) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E7DC8)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              AnimatedOpacity(
                opacity: widget.isLoadingPricing ? 0.45 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  '$formattedTotal ₴',
                  style: const TextStyle(
                    color: Color(0xFF1E7DC8),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
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

            // ── Термінал + Cash withdrawal (card only) ───────────────────────
            if (paymentMethod == PaymentMethod.card && !showPaymentSuccess) ...[
              const SizedBox(height: 10),
              _buildTerminalSelector(),
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
                              item.drug.displayName,
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
