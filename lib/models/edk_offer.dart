import 'drug.dart';

/// ЄДК (Є Дещо Краще) — pharmaceutical substitution offer.
///
/// In mock mode: hardcoded from edk_offers.dart, donorDrugId = Drug.id.
/// In live mode: from Priority Analogs API, donorDrugId = Drug.ukod.
class EdkOffer {
  final Drug drug; // replacement drug (higher margin / bonus)
  final String donorDrugId; // mock: Drug.id, live: donor ukod
  final String description; // short benefit description
  final String script; // pharmacist speech module text
  final String? promoLabel; // optional promo badge (e.g. "Потрійний кешбек")

  // ── API fields (null для hardcoded offers) ─────────────────────────────
  final int? bonus; // бонус з API
  final int? dodBonus; // додатковий бонус
  final int? linkType; // null=загальна, 1=дефектурна
  final int? rating; // пріоритет (менше = вище)

  const EdkOffer({
    required this.drug,
    required this.donorDrugId,
    required this.description,
    required this.script,
    this.promoLabel,
    this.bonus,
    this.dodBonus,
    this.linkType,
    this.rating,
  });
}
