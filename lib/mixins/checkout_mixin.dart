import 'package:flutter/material.dart';
import '../models/customer_loyalty.dart';
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

  PaymentMethod paymentMethod = PaymentMethod.cash;

  final TextEditingController cashCtr = TextEditingController();
  final FocusNode cashFocus = FocusNode();
  bool transferChangeToBonus = false;
  final TextEditingController bonusTransferCtr = TextEditingController();
  final FocusNode bonusTransferFocus = FocusNode();

  bool showPaymentSuccess = false;

  // ── Computed getters ───────────────────────────────────────────────────

  double get discountAmount {
    if (personalDiscount == null) return 0;
    return baseTotal * personalDiscount! / 100;
  }

  double get effectiveBonusAmount {
    if (!useBonuses || checkoutLoyalty == null) return 0;
    final text = bonusCtr.text.replaceAll(',', '.');
    final entered = double.tryParse(text) ?? 0;
    final maxByBalance = checkoutLoyalty!.bonusBalance;
    final maxByTotal = baseTotal - discountAmount;
    return entered.clamp(0, maxByBalance).clamp(0, maxByTotal).toDouble();
  }

  double get finalTotal {
    final raw = baseTotal - discountAmount - effectiveBonusAmount;
    return raw < 0 ? 0 : raw;
  }

  // ── Methods ────────────────────────────────────────────────────────────

  void resetCheckout() {
    paymentMethod = PaymentMethod.cash;
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
