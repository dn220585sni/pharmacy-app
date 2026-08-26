import 'package:flutter/material.dart';
import '../models/checkout_totals.dart';
import '../models/customer_loyalty.dart';
import '../models/money.dart';
import '../models/payment_method.dart';

/// Shared checkout state & calculation logic.
///
/// Used by [CartPanelState] and [OrdersPanelState] to avoid duplicating
/// discount / bonus / payment-method code.
///
/// Implementors must override [baseTotal] and [checkoutLoyalty].
mixin CheckoutMixin<T extends StatefulWidget> on State<T> {
  // ── Abstract — each widget provides its own source ─────────────────────

  /// The pre-discount total (cart subtotal or order total).
  double get baseTotal;

  /// Current loyalty card (may be null if not authenticated).
  CustomerLoyalty? get checkoutLoyalty;

  // ── State ──────────────────────────────────────────────────────────────

  bool useBonuses = false;
  final TextEditingController bonusCtr = TextEditingController();

  double? personalDiscount;
  double? availableDiscount;
  bool isLoadingDiscount = false;

  // Дефолт — КАРТКА: клієнту одразу називаємо повну суму (без готівкового
  // округлення). Округлення застосовується лише коли касир свідомо тисне
  // «Готівкою». Так уникаємо конфлікту «назвали менше, ніж треба карткою».
  PaymentMethod paymentMethod = PaymentMethod.card;

  final TextEditingController cashCtr = TextEditingController();
  final FocusNode cashFocus = FocusNode();
  bool transferChangeToBonus = false;
  final TextEditingController bonusTransferCtr = TextEditingController();
  final FocusNode bonusTransferFocus = FocusNode();

  bool showPaymentSuccess = false;

  // ── Computed getters ───────────────────────────────────────────────────

  /// Розрахунок чекауту у копійках (без float-похибок). Публічні getter-и
  /// нижче конвертують у `double` на межі, тож споживачі не змінюються.
  CheckoutTotals get _totals => CheckoutTotals(
        base: Money.fromHryvnia(baseTotal),
        discountPct: personalDiscount,
        useBonuses: useBonuses && checkoutLoyalty != null,
        enteredBonus: Money.tryParse(bonusCtr.text) ?? Money.zero,
        bonusBalance: checkoutLoyalty == null
            ? Money.zero
            : Money.fromHryvnia(checkoutLoyalty!.bonusBalance),
      );

  double get discountAmount => _totals.discount.toHryvnia();

  double get effectiveBonusAmount => _totals.bonus.toHryvnia();

  double get finalTotal => _totals.finalTotal.toHryvnia();

  // ── Methods ────────────────────────────────────────────────────────────

  void resetCheckout() {
    paymentMethod = PaymentMethod.card;
    useBonuses = false;
    bonusCtr.clear();
    personalDiscount = null;
    availableDiscount = null;
    isLoadingDiscount = false;
    cashCtr.clear();
    transferChangeToBonus = false;
    bonusTransferCtr.clear();
    showPaymentSuccess = false;
  }

  void disposeCheckout() {
    bonusCtr.dispose();
    cashCtr.dispose();
    cashFocus.dispose();
    bonusTransferCtr.dispose();
    bonusTransferFocus.dispose();
  }

  void switchToCard() {
    setState(() {
      paymentMethod = PaymentMethod.card;
      cashCtr.clear();
    });
  }
}
