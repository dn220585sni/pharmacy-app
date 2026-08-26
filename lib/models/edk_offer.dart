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

  /// Пошукові запити для назви заміни — від точного до широкого.
  ///
  /// `GetEdkOffers` віддає ПОВНУ назву з фасуванням і скороченням виробника
  /// («ЦИТРАМОН-В №10 УСТМ»), а `SearchByNameSKU` за такою не знаходить нічого
  /// (перевірено на касі 1334: 0 рядків). Тому відрізаємо хвіст після «№»/дужки
  /// й, у крайньому разі, лишаємо перше слово. Ризику взяти чужий товар немає:
  /// рядок усе одно вибирається ТОЧНО за u-кодом, запит лише розширює вибірку.
  static List<String> searchQueriesFor(String name) {
    final out = <String>[];
    void add(String s) {
      final v = s.trim();
      if (v.length >= 3 && !out.contains(v)) out.add(v);
    }

    add(name);
    final head = name.split(RegExp(r'[№,(]')).first;
    add(head);
    add(head.split(RegExp(r'[\s\-/]')).first);
    return out;
  }

  /// Чи є [d] тим товаром, який ця пропозиція замінює.
  ///
  /// [donorDrugId] формується як `drug.ukod ?? drug.id`, тому звіряти треба з
  /// ОБОМА полями. Порівняння лише за `ukod` лишало донора в кошику разом із
  /// заміною (у клієнта два препарати замість одного, резерв донора не знятий).
  bool isDonor(Drug d) => d.id == donorDrugId || d.ukod == donorDrugId;

  /// Чи можна взагалі продати цю заміну.
  ///
  /// `GetEdkOffers` віддає u-код, а для продажу потрібен s-код (код приходу):
  /// на ньому тримаються резервування `sgVRoznSetLock`, серверний кошик,
  /// `GetSumSkid`, накладна і чек. Якщо s-код не резолвнувся, `drug.id`
  /// лишається з префіксом `edk_` — таку позицію в кошик пускати не можна:
  /// вона занижує суму й не потрапляє в чек.
  bool get isSellable => !drug.id.startsWith('edk_');
}
