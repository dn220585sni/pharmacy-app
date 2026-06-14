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

  const CheckoutTotals({
    required this.base,
    this.discountPct,
    this.useBonuses = false,
    this.enteredBonus = Money.zero,
    this.bonusBalance = Money.zero,
  });

  /// Абсолютна сума персональної знижки, округлена в копійки.
  Money get discount =>
      discountPct == null ? Money.zero : base.percent(discountPct!);

  /// Фактична сума бонусів до списання: обмежена балансом і сумою після знижки.
  Money get bonus {
    if (!useBonuses) return Money.zero;
    final maxByTotal = base - discount;
    var upper = bonusBalance < maxByTotal ? bonusBalance : maxByTotal;
    if (upper.isNegative) upper = Money.zero;
    return enteredBonus.clampMoney(Money.zero, upper);
  }

  /// Сума до сплати (не може бути відʼємною).
  Money get finalTotal {
    final raw = base - discount - bonus;
    return raw.isNegative ? Money.zero : raw;
  }
}
