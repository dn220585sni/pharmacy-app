import 'drug.dart';

/// Pharmacist offer recommendation for the current cart.
class CartOffer {
  final Drug drug;
  final String reason;

  /// Pharmacist script — phrase to say to the customer.
  final String? script;

  /// Promotion badge label (e.g. "Акція 1+1", "Знижка 15%").
  final String? promoLabel;

  const CartOffer({
    required this.drug,
    required this.reason,
    this.script,
    this.promoLabel,
  });
}
