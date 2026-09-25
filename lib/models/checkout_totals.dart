import 'money.dart';

/// Чиста математика чекауту — у копійках, без UI/стану.
///
/// Винесено з [CheckoutMixin] заради тестованості й усунення float-похибок:
/// знижка/бонус/фінал рахуються в [Money] (цілі копійки), а не на `double`.
class CheckoutTotals {
  /// Сума до знижок (subtotal кошика або total замовлення).
  final Money base;

  /// Персональна знижка у відсотках (null = немає).
  final double? discountPct;

  /// Чи застосовувати бонуси.
  final bool useBonuses;

  /// Введена користувачем сума бонусів до списання.
  final Money enteredBonus;

  /// Доступний баланс бонусів картки.
  final Money bonusBalance;

  /// Мінімум, який клієнт платить грошима (`edSPLMinSumOplCash` з
  /// GetSPLParam): бонусами не можна закрити чек повністю. Zero — без
  /// обмеження. Перевірка на клієнті — Микола, 14.09.2026.
  final Money minCash;

  const CheckoutTotals({
    required this.base,
    this.discountPct,
    this.useBonuses = false,
    this.enteredBonus = Money.zero,
    this.bonusBalance = Money.zero,
    this.minCash = Money.zero,
  });

  /// Абсолютна сума персональної знижки, округлена в копійки.
  Money get discount =>
      discountPct == null ? Money.zero : base.percent(discountPct!);

  /// Хоч 1 грн клієнт платить грошима завжди — навіть коли GetSPLParam ще
  /// не підвантажено чи там 0 (Микола 25.09: чек 27 грн, підставляло 27).
  static const Money minCashFloor = Money.fromKopiykas(100);

  /// Стеля списання: min(баланс, сума після знижки − мінімум готівкою), ≥ 0.
  /// Мінімум готівкою — більший з [minCash] і [minCashFloor].
  /// Показується касиру як «можна списати до …».
  Money get bonusCap {
    final mustPay = minCash > minCashFloor ? minCash : minCashFloor;
    var upper = base - discount - mustPay;
    if (bonusBalance < upper) upper = bonusBalance;
    return upper.isNegative ? Money.zero : upper;
  }

  /// Фактична сума бонусів до списання: введена, обрізана стелею [bonusCap].
  Money get bonus {
    if (!useBonuses) return Money.zero;
    return enteredBonus.clampMoney(Money.zero, bonusCap);
  }

  /// Сума до сплати (не може бути відʼємною).
  Money get finalTotal {
    final raw = base - discount - bonus;
    return raw.isNegative ? Money.zero : raw;
  }
}
