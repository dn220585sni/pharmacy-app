import 'drug.dart';

/// ЄДК (Є Дещо Краще) — pharmaceutical substitution offer.
/// In production, provided by an external service; currently hardcoded.
class EdkOffer {
  final Drug drug; // replacement drug (higher margin / bonus)
  final String donorDrugId; // id of the drug being replaced
  final String description; // short benefit description
  final String script; // pharmacist speech module text
  final String? promoLabel; // optional promo badge (e.g. "Потрійний кешбек")

  const EdkOffer({
    required this.drug,
    required this.donorDrugId,
    required this.description,
    required this.script,
    this.promoLabel,
  });
}
