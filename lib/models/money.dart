import 'package:flutter/foundation.dart';

/// Грошова сума у **копійках** (1 грн = 100 коп.).
///
/// Канон для касового ПЗ: уся арифметика — у цілих копійках, без float-похибок.
/// `double` зʼявляється лише на межах (ввід користувача, відображення,
/// серіалізація у зовнішні API) і одразу округлюється в копійки.
///
/// Округлення — half-away-from-zero (як Dart `num.round()` і серверний
/// `(v*100).round()/100` у GetSumSkid), щоб поведінка збігалася з Caché.
@immutable
class Money implements Comparable<Money> {
  /// Сума у копійках. Може бути відʼємною (повернення, знижки).
  final int kopiykas;

  const Money._(this.kopiykas);

  /// Нуль.
  static const Money zero = Money._(0);

  /// З копійок напряму (без округлення).
  const Money.fromKopiykas(this.kopiykas);

  /// З гривень (`num`) — округлює до найближчої копійки (half-away-from-zero).
  /// `double` тут транзитний: одразу перетворюється в int, далі float не живе.
  factory Money.fromHryvnia(num hryvnia) => Money._((hryvnia * 100).round());

  /// Парсинг рядка ("125,99", "125.99", "1 234,56") → [Money].
  /// Прибирає всі пробільні символи (звичайний, nbsp), приймає кому або крапку.
  /// Повертає `null`, якщо розпарсити не вдалося (на відміну від мовчазного 0).
  static Money? tryParse(String raw) {
    final cleaned =
        raw.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.').trim();
    if (cleaned.isEmpty) return null;
    final v = double.tryParse(cleaned);
    if (v == null) return null;
    return Money.fromHryvnia(v);
  }

  /// Як [tryParse], але повертає [zero] замість `null`.
  factory Money.parse(String raw) => tryParse(raw) ?? Money.zero;

  // ── Арифметика ─────────────────────────────────────────────────────────────

  Money operator +(Money other) => Money._(kopiykas + other.kopiykas);
  Money operator -(Money other) => Money._(kopiykas - other.kopiykas);
  Money operator -() => Money._(-kopiykas);

  /// Множення на цілу кількість — **точне** (без округлення).
  Money operator *(int qty) => Money._(kopiykas * qty);

  /// Частка суми: `kopiykas * numerator / denominator`, округлено в копійки.
  /// Для дробових позицій (блістери): `fraction(fractionalQty, unitsPerPackage)`.
  Money fraction(int numerator, int denominator) {
    assert(denominator != 0, 'Money.fraction: denominator == 0');
    return Money._((kopiykas * numerator / denominator).round());
  }

  /// Відсоток від суми (напр. знижка %): `kopiykas * pct / 100`, округлено.
  Money percent(num pct) => Money._((kopiykas * pct / 100).round());

  /// Обмежити діапазоном [min]..[max].
  Money clampMoney(Money min, Money max) =>
      Money._(kopiykas.clamp(min.kopiykas, max.kopiykas));

  Money get abs => Money._(kopiykas.abs());

  // ── Порівняння ──────────────────────────────────────────────────────────────

  bool operator <(Money o) => kopiykas < o.kopiykas;
  bool operator <=(Money o) => kopiykas <= o.kopiykas;
  bool operator >(Money o) => kopiykas > o.kopiykas;
  bool operator >=(Money o) => kopiykas >= o.kopiykas;

  bool get isZero => kopiykas == 0;
  bool get isNegative => kopiykas < 0;
  bool get isPositive => kopiykas > 0;

  @override
  int compareTo(Money o) => kopiykas.compareTo(o.kopiykas);

  @override
  bool operator ==(Object other) => other is Money && other.kopiykas == kopiykas;

  @override
  int get hashCode => kopiykas.hashCode;

  // ── Конвертація назовні ──────────────────────────────────────────────────────

  /// У гривнях (`double`) — для API, що очікують decimal-число (ПРРО, Sparta).
  double toHryvnia() => kopiykas / 100;

  /// Рядок з 2 знаками і **крапкою** ("125.99") — для query-параметрів Caché/CIET.
  String toApiString() => (kopiykas / 100).toStringAsFixed(2);

  /// Відображення для UI: "125,99" (кома-роздільник), опційно з групуванням
  /// тисяч ("1 234,56", nbsp) і символом ("125,99 ₴").
  String format({bool symbol = false, bool grouped = false}) {
    final nbsp = String.fromCharCode(0x00A0);
    final neg = kopiykas < 0;
    final absKop = kopiykas.abs();
    final whole = absKop ~/ 100;
    final cents = (absKop % 100).toString().padLeft(2, '0');

    var wholeStr = whole.toString();
    if (grouped && wholeStr.length > 3) {
      final buf = StringBuffer();
      for (var i = 0; i < wholeStr.length; i++) {
        if (i > 0 && (wholeStr.length - i) % 3 == 0) buf.write(nbsp);
        buf.write(wholeStr[i]);
      }
      wholeStr = buf.toString();
    }

    final body = '${neg ? '-' : ''}$wholeStr,$cents';
    return symbol ? '$body ${String.fromCharCode(0x20B4)}' : body;
  }

  @override
  String toString() => 'Money(${format()})';
}
