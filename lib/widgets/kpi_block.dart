import 'package:flutter/material.dart';

import 'kpi_activity_ring.dart';
import 'kpi_cumulative_chart.dart';
import 'kpi_plan_calendar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Моделі й мок-дані
//
// ⚠️ Джерела цифр (сервіси Каті) ще не визначені — усі значення тут замокані.
// Коли зʼявиться сервіс, `KpiMockData.forScope` замінюється на завантаження,
// а віджети лишаються без змін.
// ─────────────────────────────────────────────────────────────────────────────

/// Чиї показники показуємо.
enum KpiScope { my, pharmacy }

/// Який показник розгорнуто в деталізацію.
enum KpiKind { turnover, vtm, zf }

class KpiTopItem {
  final String name;
  final String qty;
  final String sum;
  const KpiTopItem(this.name, this.qty, this.sum);
}

/// Рядок таблиці «Потенціал росту»: мій результат проти середнього по колегах.
class KpiGrowthRow {
  final String label;
  final String my;
  final String peers;

  /// true — мій результат кращий за колег (зелений), false — є потенціал (жовтий).
  final bool better;
  const KpiGrowthRow(this.label, this.my, this.peers, this.better);
}

/// Пропущена заміна бренду на ВТМ: клієнт узяв бренд, хоча в наявності був
/// ВТМ-аналог. [potential] — скільки ВТМ додало б до плану, грн.
class KpiVtmSwap {
  final String brand;
  final String vtm;
  final int qty;
  final double potential;
  const KpiVtmSwap(this.brand, this.vtm, this.qty, this.potential);
}

/// Дані деталізації «Товарообіг» за ОДИН день (обраний у календарі).
class KpiDayDetails {
  final List<KpiGrowthRow> growth;
  final KpiActivityData activity;
  const KpiDayDetails({required this.growth, required this.activity});
}

/// Знімок показників для одного [KpiScope].
class KpiSnapshot {
  final double turnoverFact;
  final double turnoverPlan; // план на день (план рахується поденно)
  final int checks;
  final double avgCheck;
  final List<double> turnoverDays; // факт по днях місяця (індекс 0 = 1-ше)

  /// Деталі за обраний день: «Потенціал росту» + «Активність».
  /// [today] потрібен, щоб відрізнити сьогодні (є «зараз») від минулого дня.
  final KpiDayDetails Function(int day, DateTime today) dayDetails;

  final double vtmFact; // ВТМ за день, грн
  final double vtmPlan; // план ВТМ на день = частка місячного за плановими годинами
  final double vtmMonthPlan; // план ВТМ на місяць, грн
  final List<double> vtmDays; // ВТМ по днях місяця, грн (індекс 0 = 1-ше)
  final int vtmChecks; // чеків із ВТМ
  final int vtmChecksTotal;

  /// Додаткові бали за продажі препаратів за місяць (персональні; для
  /// «Показників аптеки» — null, бонус не показуємо).
  final int? bonusPointsMonth;
  final List<KpiVtmSwap> vtmSwaps;
  final List<KpiTopItem> vtmTop;

  final double zfCur; // % частки ЗФ (накопичено з початку місяця)
  final double zfTarget; // місячний план, %
  final int zfChecks; // чеків із ЗФ
  final int zfChecksTotal;
  final List<double> zfDays; // накопичена частка по днях місяця
  final List<KpiTopItem> zfTop;

  /// Скільки зміни минуло, 0..1 (рисочка темпу на смужках за зміну).
  final double shiftElapsed;

  /// Скільки місяця минуло, 0..1 (рисочка темпу на смужці ЗФ).
  final double monthElapsed;

  const KpiSnapshot({
    required this.turnoverFact,
    required this.turnoverPlan,
    required this.checks,
    required this.avgCheck,
    required this.turnoverDays,
    required this.dayDetails,
    required this.vtmFact,
    required this.vtmPlan,
    required this.vtmMonthPlan,
    required this.vtmDays,
    required this.vtmChecks,
    required this.vtmChecksTotal,
    this.bonusPointsMonth,
    required this.vtmSwaps,
    required this.vtmTop,
    required this.zfCur,
    required this.zfTarget,
    required this.zfChecks,
    required this.zfChecksTotal,
    required this.zfDays,
    required this.zfTop,
    required this.shiftElapsed,
    required this.monthElapsed,
  });
}

class KpiMockData {
  static const _zfTop = [
    KpiTopItem('Аскорбінова к-та ЗФ 500 мг №30', '4', '128,00'),
    KpiTopItem('Вітамін D3 ЗФ 2000 МО №60', '3', '387,00'),
    KpiTopItem('Магній B6 ЗФ №50', '2', '246,00'),
    KpiTopItem('Омега-3 ЗФ №30', '1', '215,00'),
  ];
  static const _zfTopPharmacy = [
    KpiTopItem('Аскорбінова к-та ЗФ 500 мг №30', '41', '1 312,00'),
    KpiTopItem('Вітамін D3 ЗФ 2000 МО №60', '27', '3 483,00'),
    KpiTopItem('Магній B6 ЗФ №50', '19', '2 337,00'),
    KpiTopItem('Омега-3 ЗФ №30', '12', '2 580,00'),
  ];
  static const _vtmTop = [
    KpiTopItem('Парацетамол АНЦ 500 мг №10', '6', '114,00'),
    KpiTopItem('Цитрамон АНЦ №10', '4', '92,00'),
    KpiTopItem('Лоратадин АНЦ №10', '3', '141,00'),
  ];
  static const _vtmTopPharmacy = [
    KpiTopItem('Парацетамол АНЦ 500 мг №10', '58', '1 102,00'),
    KpiTopItem('Цитрамон АНЦ №10', '44', '1 012,00'),
    KpiTopItem('Лоратадин АНЦ №10', '31', '1 457,00'),
  ];
  // ВТМ по днях місяця, грн (мої); аптека — ×12.
  static const List<double> _vtmDays = [
    1500, 1350, 1600, 1750, 1400, 1650, 1800, 1550, 1700, 1900, 1450, 1600,
    1850, 1750, 1500, 1650, 1900, 1700, 1600, 1800, 1750, 1650, 2100,
  ];
  static const _vtmSwaps = [
    KpiVtmSwap('Нурофен 200 мг №12', 'Ібупрофен АНЦ 200 мг №20', 5, 96),
    KpiVtmSwap('Но-шпа 40 мг №24', 'Дротаверин АНЦ 40 мг №20', 3, 54),
    KpiVtmSwap('Кларитин 10 мг №10', 'Лоратадин АНЦ 10 мг №10', 2, 118),
    KpiVtmSwap('Панадол 500 мг №12', 'Парацетамол АНЦ 500 мг №10', 4, 38),
  ];

  // Базовий ряд по днях; у снімках множиться так, щоб частина днів
  // виконувала денний план (5 000 / 60 000), а частина — ні.
  static const List<double> _turnoverDays = [
    1400, 2900, 2100, 3300, 2800, 1900, 2600, 3100, 2700, 2400, 3500, 2900,
    2200, 3000, 2600, 2800, 3200, 2500, 2900, 3100, 2700, 2600, 3200,
  ];
  static const _zfDaysMy = [
    9.1, 10.4, 11.2, 12.0, 11.8, 12.9, 13.1, 12.4, 13.6, 14.0, 13.2, 12.8,
    13.5, 13.9, 14.2, 13.0, 12.6, 13.4, 13.8, 14.1, 13.3, 13.5, 13.67,
  ];
  static const _zfDaysPharmacy = [
    10.2, 10.8, 11.0, 11.6, 11.9, 12.3, 12.0, 12.5, 12.2, 12.8, 12.6, 12.1,
    12.4, 12.9, 12.7, 12.3, 12.0, 12.6, 12.5, 12.8, 12.4, 12.3, 12.41,
  ];

  // ── Деталі за день (детермінований «шум» від номера дня) ────────────────

  static String _m(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
  static String _n1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  static String _pc(double v) => '${v.round()}%';

  /// «Потенціал росту» за день. Лічильники — лише цілі в межах 0–5, 0–4, 0–10.
  static List<KpiGrowthRow> growthRows(int day) {
    final k = ((day * 7) % 11) / 10;
    final avg = 150 + k * 60, len = 1.6 + k * 1.2, one = 62 - k * 25;
    final tpk = 30 + k * 30, tpkIz = 18 + k * 30;
    final edk = (k * 6).round(), custom = (k * 5).round();
    final other = (k * 4).round(), hand = (k * 10).round();
    return [
      KpiGrowthRow('Середній чек', _m(avg), _m(182.4), avg >= 182.4),
      KpiGrowthRow('Довжина чека', _n1(len), _n1(2.3), len >= 2.3),
      KpiGrowthRow('Частка чеків з 1 позицією', _pc(one), _pc(44), one <= 44),
      KpiGrowthRow('Конверсія ТПК', _pc(tpk), _pc(47), tpk >= 47),
      KpiGrowthRow('Конверсія ТПК в ІЗ', _pc(tpkIz), _pc(31), tpkIz >= 31),
      KpiGrowthRow('Продажів ЄДК на відсутній товар', '$edk', _n1(2.7), edk >= 2.7),
      KpiGrowthRow('Замовлень під клієнта', '$custom', _n1(2.1), custom >= 2.1),
      KpiGrowthRow('Замовлень в іншу аптеку', '$other', _n1(1.4), other >= 1.4),
      KpiGrowthRow('Знижки «Рука допомоги»', '$hand', _n1(3.6), hand >= 3.6),
    ];
  }

  /// Події зміни 08:00–20:00 (для сьогодні — до «зараз» 14:31).
  static KpiActivityData activity(int day, {required bool isToday}) {
    const start = 8 * 60, end = 20 * 60, now = 14 * 60 + 31;
    var s = day * 9973 + 17;
    double rnd() {
      s = (s * 1103515245 + 12345) % 2147483648;
      return s / 2147483648;
    }

    final n = 34 + (rnd() * 14).floor();
    final events = <KpiActivityEvent>[];
    for (var i = 0; i < n; i++) {
      final t = start + (rnd() * 12 * 60).floor();
      final r = rnd();
      final type = r < .62
          ? KpiEventType.cash
          : r < .80
              ? KpiEventType.card
              : r < .88
                  ? KpiEventType.iz
                  : r < .95
                      ? KpiEventType.reimb
                      : KpiEventType.doc;
      if (!isToday || t <= now) events.add(KpiActivityEvent(t, type));
    }
    events.sort((a, b) => a.minute.compareTo(b.minute));

    var ps = day * 7919 + 3;
    double prnd() {
      ps = (ps * 1103515245 + 12345) % 2147483648;
      return ps / 2147483648;
    }

    final presence = <KpiPresence>[];
    var t = start + 5;
    while (t < end - 10) {
      final len = 6 + (prnd() * 30).floor();
      presence.add(KpiPresence(t, (t + len).clamp(0, end)));
      t += len + 8 + (prnd() * 40).floor();
    }

    return KpiActivityData(
      shiftStart: start,
      shiftEnd: end,
      now: isToday ? now : null,
      events: events,
      presence: presence,
    );
  }

  static KpiDayDetails _dayDetails(int day, DateTime today) => KpiDayDetails(
        growth: growthRows(day),
        activity: activity(day, isToday: day == today.day),
      );

  static KpiSnapshot forScope(KpiScope scope) {
    switch (scope) {
      case KpiScope.my:
        return KpiSnapshot(
          turnoverFact: 3200,
          turnoverPlan: 5000,
          checks: 18,
          avgCheck: 177.78,
          turnoverDays: [for (final v in _turnoverDays) v * 1.6],
          dayDetails: _dayDetails,
          vtmFact: 2100,
          vtmPlan: 3000,
          vtmMonthPlan: 22000, // мої: план місяця перекрито вже з ~14-го → бонус
          vtmDays: _vtmDays,
          vtmChecks: 11,
          vtmChecksTotal: 18,
          bonusPointsMonth: 1240,
          vtmSwaps: _vtmSwaps,
          vtmTop: _vtmTop,
          zfCur: 13.67,
          zfTarget: 13,
          zfChecks: 11,
          zfChecksTotal: 18,
          zfDays: _zfDaysMy,
          zfTop: _zfTop,
          shiftElapsed: 0.62,
          monthElapsed: 0.767,
        );
      case KpiScope.pharmacy:
        return KpiSnapshot(
          turnoverFact: 41200,
          turnoverPlan: 60000,
          checks: 236,
          avgCheck: 174.58,
          turnoverDays: [for (final v in _turnoverDays) v * 12 * 1.6],
          dayDetails: _dayDetails,
          vtmFact: 26800,
          vtmPlan: 36000,
          vtmMonthPlan: 720000, // аптека: 64% плану, факт нижче лінії
          vtmDays: [for (final v in _vtmDays) v * 12],
          vtmChecks: 148,
          vtmChecksTotal: 236,
          vtmSwaps: [
            for (final s in _vtmSwaps)
              KpiVtmSwap(s.brand, s.vtm, s.qty * 12, s.potential * 12),
          ],
          vtmTop: _vtmTopPharmacy,
          zfCur: 12.41,
          zfTarget: 13,
          zfChecks: 121,
          zfChecksTotal: 236,
          zfDays: _zfDaysPharmacy,
          zfTop: _zfTopPharmacy,
          shiftElapsed: 0.62,
          monthElapsed: 0.767,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Кольори й форматування (у палітрі застосунку)
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  static const text = Color(0xFF1C1C2E);
  static const muted = Color(0xFF6B7280);
  static const state = Color(0xFF9CA3AF);
  static const border = Color(0xFFE5E7EB);
  static const divider = Color(0xFFF0F2F5);
  static const blue = Color(0xFF1E7DC8);
  static const segBg = Color(0xFFEEF0F3);
  static const hover = Color(0xFFF8F9FB);
  static const goodBg = Color(0xFFE7F6EC);
  static const goodFg = Color(0xFF15803D);
  static const warnBg = Color(0xFFFEF3C7);
  static const warnFg = Color(0xFFB45309);
  static const chartBar = Color(0xFFBFD6EE);
  static const chartGoal = Color(0xFFEF8F8F);
  static const chartGoalText = Color(0xFFB91C1C);
}

/// "3 200" — цілі з нерозривним тонким пробілом між тисячами.
String kpiInt(num v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// "13,67%" — відсоток із комою.
String kpiPct(double v, [int digits = 2]) =>
    '${v.toStringAsFixed(digits).replaceAll('.', ',')}%';

/// "177,78" — гроші без символу.
String kpiMoney(double v) {
  final cents = (v * 100).round();
  return '${kpiInt(cents ~/ 100)},${(cents % 100).toString().padLeft(2, '0')}';
}

const _monthsGen = [
  'січень', 'лютий', 'березень', 'квітень', 'травень', 'червень', 'липень',
  'серпень', 'вересень', 'жовтень', 'листопад', 'грудень',
];
/// Родовий відмінок для дат: «8 вересня».
const _monthsGenDay = [
  'січня', 'лютого', 'березня', 'квітня', 'травня', 'червня', 'липня',
  'серпня', 'вересня', 'жовтня', 'листопада', 'грудня',
];
const _monthsShort = [
  'січ', 'лют', 'бер', 'кві', 'тра', 'чер', 'лип', 'сер', 'вер', 'жов', 'лис',
  'гру',
];

// ─────────────────────────────────────────────────────────────────────────────
// KpiBlock
// ─────────────────────────────────────────────────────────────────────────────

/// Блок показників: перемикач «Мої / Аптеки», картка з трьома показниками
/// (Товарообіг, Продаж ВТМ, Частка ЗФ), клік по рядку — деталізація на місці.
class KpiBlock extends StatefulWidget {
  /// Джерело даних за областю; за замовчуванням мок.
  final KpiSnapshot Function(KpiScope) dataFor;

  /// «Сьогодні» — для підписів місяця й осі графіка.
  final DateTime? today;

  const KpiBlock({
    super.key,
    this.dataFor = KpiMockData.forScope,
    this.today,
  });

  @override
  State<KpiBlock> createState() => _KpiBlockState();
}

class _KpiBlockState extends State<KpiBlock> {
  KpiScope _scope = KpiScope.my;
  KpiKind? _open;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final data = widget.dataFor(_scope);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScopeToggle(
          scope: _scope,
          onChanged: (s) => setState(() => _scope = s),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SizeTransition(
              sizeFactor: anim,
              axisAlignment: -1,
              child: child,
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: _open == null
              ? _KpiCard(
                  key: const ValueKey('list'),
                  data: data,
                  onOpen: (k) => setState(() => _open = k),
                )
              : _KpiDetail(
                  key: ValueKey(_open),
                  kind: _open!,
                  scope: _scope,
                  data: data,
                  today: _today,
                  onBack: () => setState(() => _open = null),
                ),
        ),
      ],
    );
  }
}

// ── Перемикач ────────────────────────────────────────────────────────────────

class _ScopeToggle extends StatelessWidget {
  final KpiScope scope;
  final ValueChanged<KpiScope> onChanged;
  const _ScopeToggle({required this.scope, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _C.segBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _seg('Мої показники', KpiScope.my),
          _seg('Показники аптеки', KpiScope.pharmacy),
        ],
      ),
    );
  }

  Widget _seg(String label, KpiScope value) {
    final on = scope == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on ? _C.blue : _C.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Картка показників ────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final KpiSnapshot data;
  final ValueChanged<KpiKind> onOpen;
  const _KpiCard({super.key, required this.data, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _KpiRow(
            name: 'Товарообіг',
            ratio: data.turnoverFact / data.turnoverPlan,
            pace: data.shiftElapsed,
            fact: kpiInt(data.turnoverFact),
            plan: 'план ${kpiInt(data.turnoverPlan)}',
            onTap: () => onOpen(KpiKind.turnover),
          ),
          const Divider(height: 1, thickness: 1, color: _C.divider),
          _KpiRow(
            name: 'Продаж ВТМ',
            ratio: data.vtmFact / data.vtmPlan,
            pace: data.shiftElapsed,
            fact: kpiInt(data.vtmFact),
            plan: 'план ${kpiInt(data.vtmPlan)}',
            onTap: () => onOpen(KpiKind.vtm),
          ),
          const Divider(height: 1, thickness: 1, color: _C.divider),
          _KpiRow(
            name: 'Частка ЗФ',
            ratio: data.zfCur / data.zfTarget,
            pace: data.monthElapsed,
            fact: kpiPct(data.zfCur),
            plan: 'план ${kpiPct(data.zfTarget, 0)}',
            onTap: () => onOpen(KpiKind.zf),
          ),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final String name;
  final double ratio; // факт / план (може бути > 1)
  final double pace; // 0..1 — рисочка темпу
  final String fact;
  final String plan;
  final VoidCallback onTap;

  const _KpiRow({
    required this.name,
    required this.ratio,
    required this.pace,
    required this.fact,
    required this.plan,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: _C.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _C.text,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: _C.state),
                const Spacer(),
                _Badge(ratio: ratio),
              ],
            ),
            const SizedBox(height: 7),
            KpiTrack(ratio: ratio, pace: pace),
            const SizedBox(height: 5),
            Row(
              children: [
                Text(
                  fact,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _C.text,
                  ),
                ),
                const Spacer(),
                Text(
                  plan,
                  style: const TextStyle(fontSize: 11, color: _C.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Бейдж відсотка виконання: ≥100% зелений, <70% жовтий, інакше нейтральний.
class _Badge extends StatelessWidget {
  final double ratio;
  const _Badge({required this.ratio});

  @override
  Widget build(BuildContext context) {
    final pct = (ratio * 100).round();
    final (bg, fg) = pct >= 100
        ? (_C.goodBg, _C.goodFg)
        : pct < 70
            ? (_C.warnBg, _C.warnFg)
            : (_C.divider, _C.text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$pct%',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// Смужка прогресу 8 px: трек #E5E7EB, заповнення синє, рисочка темпу.
class KpiTrack extends StatelessWidget {
  final double ratio;
  final double? pace;
  const KpiTrack({super.key, required this.ratio, this.pace});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 2,
                left: 0,
                right: 0,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: _C.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                left: 0,
                width: w * ratio.clamp(0.0, 1.0),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: _C.blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              if (pace != null)
                Positioned(
                  top: 0,
                  left: (w * pace!.clamp(0.0, 1.0)).clamp(0.0, w - 1),
                  child: Container(width: 1, height: 12, color: _C.state),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Деталізація ──────────────────────────────────────────────────────────────

class _KpiDetail extends StatefulWidget {
  final KpiKind kind;
  final KpiScope scope;
  final KpiSnapshot data;
  final DateTime today;
  final VoidCallback onBack;

  const _KpiDetail({
    super.key,
    required this.kind,
    required this.scope,
    required this.data,
    required this.today,
    required this.onBack,
  });

  @override
  State<_KpiDetail> createState() => _KpiDetailState();
}

class _KpiDetailState extends State<_KpiDetail> {
  /// Обраний день у календарі (деталізація «Товарообіг»); типово сьогодні.
  late int _selDay = widget.today.day;

  KpiKind get kind => widget.kind;
  KpiScope get scope => widget.scope;
  KpiSnapshot get data => widget.data;
  DateTime get today => widget.today;
  VoidCallback get onBack => widget.onBack;

  String get _title => switch (kind) {
        KpiKind.turnover => 'Товарообіг',
        KpiKind.vtm => 'Продаж ВТМ',
        KpiKind.zf => 'Частка ЗФ',
      };

  String get _scopeTitle =>
      scope == KpiScope.my ? 'мої показники' : 'показники аптеки';

  /// Дні з початку місяця до сьогодні (мок може мати більше значень).
  List<double> _toDate(List<double> days) =>
      days.length > today.day ? days.sublist(0, today.day) : days;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _BackButton(onTap: onBack),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$_title · $_scopeTitle',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _C.text,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _C.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (kind) {
              KpiKind.turnover => _turnover(),
              KpiKind.vtm => _vtm(),
              KpiKind.zf => _zf(),
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _zf() {
    final ratio = data.zfCur / data.zfTarget;
    final diff = data.zfCur - data.zfTarget;
    return [
      _BigValue(
        value: kpiPct(data.zfCur),
        caption: 'план на ${_monthsGen[today.month - 1]} ${kpiPct(data.zfTarget, 0)}',
        ratio: ratio,
      ),
      const SizedBox(height: 6),
      KpiTrack(ratio: ratio, pace: data.monthElapsed),
      const SizedBox(height: 12),
      _Stats([
        _Stat('До плану',
            '${diff >= 0 ? '+' : '−'}${diff.abs().toStringAsFixed(2).replaceAll('.', ',')} п.п.'),
        _Stat('Чеків із ЗФ', '${data.zfChecks} / ${data.zfChecksTotal}'),
        _Stat('Пройшло місяця', kpiPct(data.monthElapsed * 100, 0)),
      ]),
      const SizedBox(height: 12),
      _SectionLabel('Динаміка по днях (накопичено з 1 ${_monthsShort[today.month - 1]})'),
      const SizedBox(height: 6),
      KpiDayChart(
        values: _toDate(data.zfDays),
        goal: data.zfTarget,
        goalLabel: 'план ${kpiPct(data.zfTarget, 0)}',
        firstLabel: '1 ${_monthsShort[today.month - 1]}',
        lastLabel: 'сьогодні, ${today.day} ${_monthsShort[today.month - 1]}',
      ),
      const SizedBox(height: 12),
      const _SectionLabel('Топ ЗФ за зміну'),
      const SizedBox(height: 4),
      _TopTable(items: data.zfTop),
      const SizedBox(height: 8),
      const Text(
        'Частка ЗФ = сума продажів товарів із маркером «Золота фішка» / '
        'загальний товарообіг за місяць.',
        style: TextStyle(fontSize: 11, color: _C.muted, height: 1.4),
      ),
    ];
  }

  /// Підпис обраного дня для заголовків «Потенціал росту» / «Активність».
  String get _selDayLabel => _selDay == today.day
      ? 'сьогодні'
      : '$_selDay ${_monthsGenDay[today.month - 1]}';

  List<Widget> _turnover() {
    final ratio = data.turnoverFact / data.turnoverPlan;
    final fact = data.turnoverFact;
    final day = data.dayDetails(_selDay, today);
    return [
      _BigValue(
        value: '${kpiInt(fact)} ₴',
        caption: 'план на день ${kpiInt(data.turnoverPlan)} ₴',
        ratio: ratio,
      ),
      const SizedBox(height: 6),
      KpiTrack(ratio: ratio, pace: data.shiftElapsed),
      const SizedBox(height: 12),
      _Stats([
        _Stat('Чеків', '${data.checks}'),
        _Stat('Середній чек', kpiMoney(data.avgCheck)),
      ]),
      const SizedBox(height: 12),
      _SectionLabel(
          'Виконання денного плану · ${_monthsGen[today.month - 1]}'),
      const SizedBox(height: 8),
      KpiPlanCalendar(
        dayFacts: data.turnoverDays,
        dayPlan: data.turnoverPlan,
        today: today,
        selectedDay: _selDay,
        onSelect: (d) => setState(() => _selDay = d),
      ),
      const SizedBox(height: 8),
      const Text(
        'За кожен день із виконаним планом додатково нараховується 0,2% '
        'від продажів цього дня.',
        style: TextStyle(fontSize: 11, color: _C.muted, height: 1.4),
      ),
      const SizedBox(height: 12),
      _SectionLabel('Потенціал росту', trailing: _selDayLabel),
      const SizedBox(height: 4),
      _GrowthTable(rows: day.growth),
      const SizedBox(height: 8),
      const Text(
        'Клікніть дату в календарі, щоб побачити показники за той день. '
        'Зелений — краще за колег, жовтий — є потенціал.',
        style: TextStyle(fontSize: 11, color: _C.muted, height: 1.4),
      ),
      const SizedBox(height: 12),
      _SectionLabel('Активність', trailing: _selDayLabel),
      const SizedBox(height: 4),
      KpiActivityRing(data: day.activity),
      const SizedBox(height: 8),
      const Text(
        'Наведіть на рисочку, щоб побачити тип події й час. '
        'Внутрішнє кільце — клієнти в торговому залі.',
        style: TextStyle(fontSize: 11, color: _C.muted, height: 1.4),
      ),
    ];
  }

  List<Widget> _vtm() {
    final ratio = data.vtmFact / data.vtmPlan;
    final monthFact =
        data.vtmDays.take(today.day).fold<double>(0, (s, v) => s + v);
    final monthPct = (monthFact / data.vtmMonthPlan * 100).round();
    // Бонус +20% — лише персональний і лише коли накопичений факт уже
    // перевищив план місяця (нарахування — після закриття місяця).
    final bonus = data.bonusPointsMonth;
    final showBonus = scope == KpiScope.my &&
        bonus != null &&
        monthFact >= data.vtmMonthPlan;
    return [
      _BigValue(
        value: '${kpiInt(data.vtmFact)} ₴',
        caption: 'план на день ${kpiInt(data.vtmPlan)} ₴',
        ratio: ratio,
      ),
      const SizedBox(height: 6),
      KpiTrack(ratio: ratio, pace: data.shiftElapsed),
      const SizedBox(height: 12),
      _Stats([
        _Stat('Чеків із ВТМ', '${data.vtmChecks} / ${data.vtmChecksTotal}'),
        _Stat('До плану дня',
            '${kpiInt((data.vtmPlan - data.vtmFact).clamp(0, double.infinity))} ₴'),
        _Stat(
          'План місяця',
          '$monthPct%',
          color: monthPct >= 100
              ? _C.goodFg
              : monthPct < 70
                  ? _C.warnFg
                  : null,
        ),
      ]),
      if (showBonus) ...[
        const SizedBox(height: 12),
        _BonusCard(
          points: bonus,
          monthGen: _monthsGenDay[today.month - 1],
        ),
      ],
      const SizedBox(height: 12),
      _SectionLabel(
        'ВТМ за місяць: факт і план',
        trailing: 'план ${kpiInt(data.vtmMonthPlan)} ₴',
      ),
      const SizedBox(height: 6),
      KpiCumulativeChart(
        dayFacts: data.vtmDays,
        monthPlan: data.vtmMonthPlan,
        today: today,
      ),
      const SizedBox(height: 6),
      const Text(
        'План на місяць у гривнях, розбитий по днях пропорційно плановим '
        'годинам фармацевта. Пунктир — план наростаючим підсумком.',
        style: TextStyle(fontSize: 11, color: _C.muted, height: 1.4),
      ),
      const SizedBox(height: 12),
      const _SectionLabel('Пропущені заміни на ВТМ', trailing: 'сьогодні'),
      const SizedBox(height: 4),
      _SwapsTable(swaps: data.vtmSwaps),
      const SizedBox(height: 8),
      const Text(
        'Чеки, де клієнт узяв бренд, хоча в наявності був ВТМ-аналог. '
        'Потенціал — скільки ВТМ додало б до плану.',
        style: TextStyle(fontSize: 11, color: _C.muted, height: 1.4),
      ),
      const SizedBox(height: 12),
      const _SectionLabel('Топ ВТМ за зміну'),
      const SizedBox(height: 4),
      _TopTable(items: data.vtmTop),
    ];
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: const BorderSide(color: _C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: _C.hover,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(6, 5, 9, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_left_rounded, size: 16, color: _C.blue),
              SizedBox(width: 2),
              Text('Назад',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _C.blue)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigValue extends StatelessWidget {
  final String value;
  final String caption;
  final double ratio;
  const _BigValue(
      {required this.value, required this.caption, required this.ratio});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: _C.text,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            caption,
            style: const TextStyle(fontSize: 12, color: _C.muted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _Badge(ratio: ratio),
      ],
    );
  }
}

class _Stat {
  final String label;
  final String value;
  final Color? color; // статусний колір значення (зелений/жовтий)
  const _Stat(this.label, this.value, {this.color});
}

class _Stats extends StatelessWidget {
  final List<_Stat> items;
  const _Stats(this.items);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: _C.hover,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    items[i].label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      color: _C.muted,
                      letterSpacing: 0.3,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: items[i].color ?? _C.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  /// Підпис праворуч (напр. обраний день), звичайним шрифтом.
  final String? trailing;
  const _SectionLabel(this.text, {this.trailing});

  /// Секції в картці деталізації розділяємо явно: відступ + лінія зверху.
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _C.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bar_chart_rounded, size: 14, color: _C.state),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _C.muted,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(fontSize: 11, color: _C.muted),
            ),
        ],
      ),
    );
  }
}

/// Зелена картка «Йдете на бонус +20%» — лише при перевищенні плану місяця.
class _BonusCard extends StatelessWidget {
  final int points; // додаткові бали за місяць
  final String monthGen; // «вересня»
  const _BonusCard({required this.points, required this.monthGen});

  @override
  Widget build(BuildContext context) {
    final extra = (points * 0.2).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _C.goodBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x4022C55E)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
            child: const Text(
              '+20%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Йдете на бонус +20%: близько +${kpiInt(extra)} балів',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _C.goodFg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Продажі ВТМ уже перевищили план $monthGen. 20% від '
                  '${kpiInt(points)} додаткових балів за продажі препаратів; '
                  'нарахується після закриття місяця.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF166534),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «Пропущені заміни на ВТМ»: бренд → ВТМ-аналог, к-сть, потенціал, разом.
class _SwapsTable extends StatelessWidget {
  final List<KpiVtmSwap> swaps;
  const _SwapsTable({required this.swaps});

  @override
  Widget build(BuildContext context) {
    const hs = TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: _C.muted,
        letterSpacing: 0.3);
    const cs = TextStyle(fontSize: 12, color: _C.text);
    const bold = TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700, color: _C.text);
    Widget line(Widget a, Widget b, Widget c, Color border) => Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: border))),
          child: Row(
            children: [
              Expanded(child: a),
              SizedBox(width: 48, child: b),
              SizedBox(width: 84, child: c),
            ],
          ),
        );
    final qty = swaps.fold<int>(0, (s, x) => s + x.qty);
    final sum = swaps.fold<double>(0, (s, x) => s + x.potential);
    return Column(
      children: [
        line(
          const Text('ПРОДАНО БРЕНД → Є ВТМ', style: hs),
          const Text('К-СТЬ', style: hs, textAlign: TextAlign.right),
          const Text('ПОТЕНЦІАЛ', style: hs, textAlign: TextAlign.right),
          _C.border,
        ),
        for (final s in swaps)
          line(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.brand, style: cs, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('→ ${s.vtm}',
                    style: const TextStyle(fontSize: 11, color: _C.goodFg),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
            Text('${s.qty}', style: cs, textAlign: TextAlign.right),
            Text('+${kpiInt(s.potential)} ₴',
                style: cs, textAlign: TextAlign.right),
            _C.divider,
          ),
        line(
          const Text('Разом', style: bold),
          Text('$qty', style: bold, textAlign: TextAlign.right),
          Text('+${kpiInt(sum)} ₴', style: bold, textAlign: TextAlign.right),
          Colors.transparent,
        ),
      ],
    );
  }
}

/// Таблиця «Потенціал росту»: Показник · Мій результат · У колег.
/// Мій результат зелений, якщо кращий за колег, жовтий — є потенціал.
class _GrowthTable extends StatelessWidget {
  final List<KpiGrowthRow> rows;
  const _GrowthTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    const hs = TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: _C.muted,
        letterSpacing: 0.3);
    Widget line(Widget a, Widget b, Widget c, Color border) => Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: border))),
          child: Row(
            children: [
              Expanded(child: a),
              SizedBox(width: 84, child: b),
              SizedBox(width: 56, child: c),
            ],
          ),
        );
    Text h(String s, [TextAlign align = TextAlign.left]) =>
        Text(s.toUpperCase(), style: hs, textAlign: align);
    return Column(
      children: [
        line(h('Показник'), h('Мій результат', TextAlign.right),
            h('У колег', TextAlign.right), _C.border),
        for (final r in rows)
          line(
            Text(r.label,
                style: const TextStyle(fontSize: 12, color: _C.text, height: 1.25),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            Text(
              r.my,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: r.better ? _C.goodFg : _C.warnFg,
              ),
            ),
            Text(r.peers,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, color: _C.text)),
            _C.divider,
          ),
      ],
    );
  }
}

class _TopTable extends StatelessWidget {
  static const header = ('Товар', 'К-сть', 'Сума');
  final List<KpiTopItem> items;
  const _TopTable({required this.items});

  @override
  Widget build(BuildContext context) {
    const hs = TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: _C.muted,
        letterSpacing: 0.3);
    const cs = TextStyle(fontSize: 12, color: _C.text);
    Widget row(String a, String b, String c, TextStyle s, Color line) =>
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: line))),
          child: Row(
            children: [
              Expanded(
                  child: Text(a, style: s, overflow: TextOverflow.ellipsis)),
              SizedBox(
                  width: 44,
                  child: Text(b, style: s, textAlign: TextAlign.right)),
              SizedBox(
                  width: 72,
                  child: Text(c, style: s, textAlign: TextAlign.right)),
            ],
          ),
        );
    return Column(
      children: [
        row(header.$1.toUpperCase(), header.$2.toUpperCase(),
            header.$3.toUpperCase(), hs, _C.border),
        for (final it in items) row(it.name, it.qty, it.sum, cs, _C.divider),
      ],
    );
  }
}

// ── Графік по днях ───────────────────────────────────────────────────────────

/// Стовпчики по днях місяця; останній (сьогодні) синій, решта світлі.
/// [goal] — пунктирна лінія плану з підписом.
class KpiDayChart extends StatelessWidget {
  final List<double> values;
  final double? goal;
  final String? goalLabel;
  final String firstLabel;
  final String lastLabel;
  final double height;

  const KpiDayChart({
    super.key,
    required this.values,
    this.goal,
    this.goalLabel,
    required this.firstLabel,
    required this.lastLabel,
    this.height = 90,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _DayChartPainter(
              values: values,
              goal: goal,
              goalLabel: goalLabel,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(firstLabel,
                style: const TextStyle(fontSize: 10, color: _C.state)),
            const Spacer(),
            Text(lastLabel,
                style: const TextStyle(fontSize: 10, color: _C.state)),
          ],
        ),
      ],
    );
  }
}

class _DayChartPainter extends CustomPainter {
  final List<double> values;
  final double? goal;
  final String? goalLabel;
  const _DayChartPainter({required this.values, this.goal, this.goalLabel});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var max = values.reduce((a, b) => a > b ? a : b);
    if (goal != null && goal! > max) max = goal!;
    max *= 1.1;
    if (max <= 0) max = 1;

    const gap = 3.0;
    final n = values.length;
    final bw = (size.width - gap * (n - 1)) / n;
    final bar = Paint()..color = _C.chartBar;
    final today = Paint()..color = _C.blue;
    for (var i = 0; i < n; i++) {
      final h = size.height * (values[i] / max).clamp(0.0, 1.0);
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(i * (bw + gap), size.height - h, bw, h),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      );
      canvas.drawRRect(r, i == n - 1 ? today : bar);
    }

    // Базова лінія.
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = _C.border
        ..strokeWidth = 1,
    );

    // Пунктир плану + підпис.
    if (goal != null) {
      final y = size.height - size.height * (goal! / max).clamp(0.0, 1.0);
      final p = Paint()
        ..color = _C.chartGoal
        ..strokeWidth = 2;
      const dash = 6.0, space = 4.0;
      for (var x = 0.0; x < size.width; x += dash + space) {
        canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), p);
      }
      if (goalLabel != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: goalLabel,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _C.chartGoalText,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - tp.width, y - tp.height - 2));
        tp.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_DayChartPainter old) =>
      old.values != values || old.goal != goal || old.goalLabel != goalLabel;
}
