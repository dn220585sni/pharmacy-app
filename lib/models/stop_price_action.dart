/// Активна акція/правило знижки на товар з API `GetStopPriceUKod`.
class StopPriceAction {
  /// ID акції — узгоджено з `pravilo` поля у GetSumSkid Goods.
  /// Наприклад `stop-price:42553:0:0,00{...}` ↔ id "42553".
  final String id;

  /// Текстовий опис від сервера. Може містити автора/відповідального
  /// після `/` — для UI використовуй [shortOpis].
  final String opis;

  /// Період дії, формат `DD.MM.YYYY`.
  final String? dateBegin;
  final String? dateEnd;

  /// Базове правило (закодоване): `r:-10.00%:1:`, `adddisk:0%:1:`, тощо.
  final String? pravilo;

  /// Додаткові правила залежно від кількості упаковок.
  final List<StopPriceRule> rules;

  /// Набір супутніх товарів акції (крос-сейл `Nabor`). У спостережених даних —
  /// 0..1 елемент, але сервер віддає масив, тому моделюємо списком.
  ///
  /// Семантика залежить від [NaborItem.isAdditional] (`dopgoods`):
  /// • `dopgoods=1` — додатковий рекомендований товар (допродаж); знижка на нього
  ///   зазвичай описана текстом у [opis] ("знижка 20%"), а [pravilo] = `adddisk:0%`.
  /// • `dopgoods=0` — товар, на який діє пряма знижка [pravilo] (`r:-XX%`); сам
  ///   акційний товар названо в [opis], а супутній-тригер згадано в дужках опису.
  final List<NaborItem> nabor;

  /// К-сть упаковок акційного товару для спрацювання (поле `pack`, дефолт 1).
  final int pack;

  /// Сегмент клієнта (`classifklient`); порожньо = для всіх.
  final String classifklient;

  /// Ціна набору (`priceNabor`); 0 якщо не задана.
  final double priceNabor;

  const StopPriceAction({
    required this.id,
    required this.opis,
    this.dateBegin,
    this.dateEnd,
    this.pravilo,
    this.rules = const [],
    this.nabor = const [],
    this.pack = 1,
    this.classifklient = '',
    this.priceNabor = 0,
  });

  factory StopPriceAction.fromJson(Map<String, dynamic> j) {
    final rawRules = j['rules'];
    final rules = rawRules is List
        ? rawRules
            .whereType<Map<String, dynamic>>()
            .map(StopPriceRule.fromJson)
            .toList(growable: false)
        : const <StopPriceRule>[];
    final rawNabor = j['Nabor'];
    final nabor = rawNabor is List
        ? rawNabor
            .whereType<Map<String, dynamic>>()
            .map(NaborItem.fromJson)
            .toList(growable: false)
        : const <NaborItem>[];
    return StopPriceAction(
      id: j['id']?.toString() ?? '',
      opis: j['opis']?.toString() ?? '',
      dateBegin: j['DateBegin']?.toString(),
      dateEnd: j['DateEnd']?.toString(),
      pravilo: j['pravilo']?.toString(),
      rules: rules,
      nabor: nabor,
      pack: int.tryParse(j['pack']?.toString() ?? '') ?? 1,
      classifklient: j['classifklient']?.toString() ?? '',
      priceNabor: double.tryParse(
            (j['priceNabor']?.toString() ?? '').replaceAll(',', '.'),
          ) ??
          0,
    );
  }

  /// Скорочений опис для бейджа: без частини після `/` (автор) і обрізаний
  /// до розумної довжини.
  String get shortOpis {
    var s = opis;
    final slashIdx = s.indexOf('/');
    if (slashIdx > 0) s = s.substring(0, slashIdx).trim();
    // Прибираємо подвійні пробіли.
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Частина `opis` після `/` — автор/відповідальний (для tooltip/audit).
  String? get author {
    final i = opis.indexOf('/');
    if (i < 0 || i == opis.length - 1) return null;
    final s = opis.substring(i + 1).trim();
    return s.isEmpty ? null : s;
  }

  /// Найкращий incentive — пріоритет `rules` (бо там залежність від кількості,
  /// корисніше фармацевту), fallback на `pravilo` (базова знижка з 1 шт).
  /// `null` якщо жоден варіант не має знижки.
  String? get bestIncentive {
    StopPriceRule? best;
    double bestAbs = 0;
    for (final r in rules) {
      if (!r.hasDiscount) continue;
      final mag = r.discountPercent?.abs() ?? r.discountUah ?? 0;
      if (mag > bestAbs) {
        bestAbs = mag;
        best = r;
      }
    }
    if (best != null) return best.incentiveText;
    return baseIncentiveText;
  }

  /// Декодоване базове правило (`pravilo`). Діє з 1 шт без умов.
  /// Формат "−20%" / "−32 грн" / null.
  String? get baseIncentiveText => baseRule?.discountLabel;

  /// Список усіх incentives для tooltip — базове правило + всі rules.
  List<String> get incentiveLines {
    final list = <String>[];
    final base = baseIncentiveText;
    if (base != null) list.add('Базова знижка: $base');
    for (final r in rules) {
      final t = r.incentiveText;
      if (t != null) list.add(t);
    }
    return list;
  }

  /// Базове правило `pravilo` як псевдо-правило з kol=1.
  StopPriceRule? get baseRule => pravilo == null || pravilo!.isEmpty
      ? null
      : StopPriceRule(kol: 1, praviloup: pravilo!);

  /// Правила що вже діють для поточної кількості (включно з базовим).
  List<StopPriceRule> appliedRules(int qty) {
    final result = <StopPriceRule>[];
    if (qty < 1) return result;
    final base = baseRule;
    if (base != null && base.hasDiscount) result.add(base);
    for (final r in rules) {
      if (r.kol <= qty && r.hasDiscount) result.add(r);
    }
    return result;
  }

  /// Безумовна акційна ціна на сам товар при роздрібній [retail] — з базового
  /// правила (`r:-XX%` або `r:-XX` грн). `null` якщо безумовної знижки нема.
  ///
  /// КРИТИЧНО: знижка безумовна лише коли немає [nabor] — наявність набору
  /// означає, що акція діє у зв'язці з іншим препаратом (напр. «Купуй БЕТАГІСТИН
  /// → −20% на ГІНКГО»), тобто умовна, і застосовується сервером лише коли
  /// потрібний товар теж у чеку.
  double? unconditionalPromoPrice(double retail) {
    if (nabor.isNotEmpty) return null;
    return baseRule?.promoPrice(retail);
  }

  /// Перше досяжне правило з більшим порогом kol — для CTA.
  StopPriceRule? nextActionableRule(int qty) {
    StopPriceRule? best;
    for (final r in rules) {
      if (r.kol > qty && r.hasDiscount) {
        if (best == null || r.kol < best.kol) best = r;
      }
    }
    return best;
  }

  /// Тег "Холдинг" з opis (якщо є) — для контексту applied-бейджа базового правила.
  String? get holdingTag {
    if (opis.toLowerCase().contains('холдинг')) return 'Холдинг';
    return null;
  }

  /// Чи є супутній набір (крос-сейл).
  bool get hasNabor => nabor.isNotEmpty;

  /// Додаткові рекомендовані товари (допродаж, `dopgoods=1`) — для крос-сейл
  /// підказки фармацевту.
  List<NaborItem> get recommendedItems =>
      nabor.where((n) => n.isAdditional).toList(growable: false);

  /// Знижка на рекомендований товар, витягнута з тексту [opis]
  /// ("...знижка 20.0%..."). Для `adddisk`-наборів % не в [pravilo], а в описі.
  /// Формат "−20%" або `null` якщо не знайдено / 0%.
  String? get recommendedDiscountText {
    final m = RegExp(r'знижк\S*\s*(\d+(?:[.,]\d+)?)\s*%', caseSensitive: false)
        .firstMatch(opis);
    if (m == null) return null;
    final pct = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (pct == null || pct == 0) return null;
    final abs = pct == pct.roundToDouble()
        ? pct.toInt().toString()
        : pct.toString();
    return '−$abs%';
  }
}

/// Супутній товар у [StopPriceAction.nabor] (елемент `Nabor`).
class NaborItem {
  /// Код товару, узгоджений з `ukod` у GetSKU/GetTopDrugs.
  final String ukod;

  /// Назва товару (як віддає сервер).
  final String name;

  /// К-сть упаковок у наборі (`kol`, дефолт 1).
  final int kol;

  /// `dopgoods=1` — додатковий рекомендований товар (допродаж); `0` — товар,
  /// на який діє пряма знижка акції.
  final bool isAdditional;

  const NaborItem({
    required this.ukod,
    required this.name,
    this.kol = 1,
    this.isAdditional = false,
  });

  factory NaborItem.fromJson(Map<String, dynamic> j) => NaborItem(
        ukod: j['ukod']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        kol: int.tryParse(j['kol']?.toString() ?? '') ?? 1,
        isAdditional: (j['dopgoods']?.toString() ?? '0') == '1',
      );
}

/// Правило знижки залежно від кількості упаковок.
class StopPriceRule {
  /// Від якої кількості діє правило.
  final int kol;
  /// Закодоване правило: `r:-10.00%:1:`, `adddisk:0%:1:`.
  final String praviloup;

  const StopPriceRule({required this.kol, required this.praviloup});

  factory StopPriceRule.fromJson(Map<String, dynamic> j) => StopPriceRule(
        kol: int.tryParse(j['kol']?.toString() ?? '') ?? 0,
        praviloup: j['praviloup']?.toString() ?? '',
      );

  /// Тип правила (перша частина перед `:`). Наприклад `r`, `adddisk`, `stop-price`.
  String get ruleType => praviloup.split(':').first;

  /// Сире значення зі знаком з другої частини (напр. -20.0 або -32.0). null якщо нема.
  double? get _rawValue {
    final parts = praviloup.split(':');
    if (parts.length < 2) return null;
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(parts[1]);
    return m == null ? null : double.tryParse(m.group(0)!);
  }

  /// Чи знижка задана у відсотках (друга частина містить `%`); інакше — у грн.
  /// КРИТИЧНО: `r:-32.00:1:` (без `%`) = 32 ГРН, а `r:-20.00%:1:` = 20 ВІДСОТКІВ.
  bool get isPercent {
    final parts = praviloup.split(':');
    return parts.length >= 2 && parts[1].contains('%');
  }

  /// Відсоток знижки — ЛИШЕ для правил зі знаком `%` (напр. `r:-20.00%`).
  /// `null` для абсолютних (грн), нерозпізнаних або 0%.
  double? get discountPercent {
    if (!isPercent) return null;
    final v = _rawValue;
    return (v == null || v == 0) ? null : v;
  }

  /// Абсолютна знижка у грн — для правил БЕЗ `%` (напр. `r:-32.00` = 32 грн).
  /// Повертає додатну суму до віднімання. `null` для відсоткових/0/нерозпізнаних.
  double? get discountUah {
    if (isPercent) return null;
    final v = _rawValue;
    return (v == null || v == 0) ? null : v.abs();
  }

  /// Чи правило несе реальну знижку (% або грн).
  bool get hasDiscount => discountPercent != null || discountUah != null;

  /// Текстовий ярлик знижки: "−20%" / "−32 грн" / "+5% дод." `null` якщо нема.
  String? get discountLabel {
    final pct = discountPercent;
    if (pct != null) {
      final sign = pct < 0 ? '−' : '+';
      final suffix = ruleType == 'adddisk' ? '% дод.' : '%';
      return '$sign${_fmt(pct.abs())}$suffix';
    }
    final uah = discountUah;
    if (uah != null) return '−${_fmt(uah)} грн';
    return null;
  }

  /// Акційна ціна при роздрібній [retail]: для % → `retail×(1−%)`, для грн →
  /// `retail−грн`. `null` якщо знижки нема або ціна некоректна.
  double? promoPrice(double retail) {
    if (retail <= 0) return null;
    final pct = discountPercent;
    if (pct != null && pct < 0) return retail * (1 + pct / 100);
    final uah = discountUah;
    if (uah != null) return (retail - uah).clamp(0, retail).toDouble();
    return null;
  }

  /// Короткий текст: "Купи 2+ → −10%" / "Купи 2+ → −32 грн". `null` якщо нема знижки.
  String? get incentiveText {
    final label = discountLabel;
    return label == null ? null : 'Купи $kol+ → $label';
  }

  /// Текст для applied-бейджа: "−10% від 2 уп." / "−32 грн" / "−30%".
  String? get appliedText {
    final label = discountLabel;
    if (label == null) return null;
    return kol <= 1 ? label : '$label від $kol уп.';
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
