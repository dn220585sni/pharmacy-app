import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/money.dart';
import 'package:pharmacy_app/models/checkout_totals.dart';

void main() {
  group('CheckoutTotals — знижка', () {
    test('без знижки → 0', () {
      final t = CheckoutTotals(base: Money.fromHryvnia(100));
      expect(t.discount, Money.zero);
      expect(t.finalTotal, Money.fromHryvnia(100));
    });

    test('відсоткова знижка округлюється в копійки', () {
      // 33,33 × 10% = 3,333 → 3,33
      final t = CheckoutTotals(base: Money.fromHryvnia(33.33), discountPct: 10);
      expect(t.discount, Money.fromHryvnia(3.33));
      expect(t.finalTotal, Money.fromHryvnia(30.00));
    });

    test('100% знижка → фінал 0', () {
      final t = CheckoutTotals(base: Money.fromHryvnia(50), discountPct: 100);
      expect(t.finalTotal, Money.zero);
    });
  });

  group('CheckoutTotals — бонуси', () {
    test('useBonuses=false → бонус 0 навіть якщо введено', () {
      final t = CheckoutTotals(
        base: Money.fromHryvnia(100),
        enteredBonus: Money.fromHryvnia(50),
        bonusBalance: Money.fromHryvnia(50),
      );
      expect(t.bonus, Money.zero);
    });

    test('бонус обмежений балансом картки', () {
      final t = CheckoutTotals(
        base: Money.fromHryvnia(100),
        useBonuses: true,
        enteredBonus: Money.fromHryvnia(80),
        bonusBalance: Money.fromHryvnia(30),
      );
      expect(t.bonus, Money.fromHryvnia(30));
      expect(t.finalTotal, Money.fromHryvnia(70));
    });

    test('бонус обмежений сумою після знижки', () {
      // base 100, знижка 10% = 90 до сплати; бонус введено 95, баланс 200
      final t = CheckoutTotals(
        base: Money.fromHryvnia(100),
        discountPct: 10,
        useBonuses: true,
        enteredBonus: Money.fromHryvnia(95),
        bonusBalance: Money.fromHryvnia(200),
      );
      expect(t.bonus, Money.fromHryvnia(90));
      expect(t.finalTotal, Money.zero);
    });

    test('знижка + бонус разом', () {
      // base 200, знижка 25% = 50 → 150; бонус 20 → фінал 130
      final t = CheckoutTotals(
        base: Money.fromHryvnia(200),
        discountPct: 25,
        useBonuses: true,
        enteredBonus: Money.fromHryvnia(20),
        bonusBalance: Money.fromHryvnia(100),
      );
      expect(t.discount, Money.fromHryvnia(50));
      expect(t.bonus, Money.fromHryvnia(20));
      expect(t.finalTotal, Money.fromHryvnia(130));
    });
  });

  group('CheckoutTotals — без float-дрейфу', () {
    test('базова сума з копійок не дрейфує у фіналі', () {
      // 0,10 × 3 = 0,30; знижка 0; фінал 0,30 рівно
      final t = CheckoutTotals(base: Money.fromHryvnia(0.30));
      expect(t.finalTotal.kopiykas, 30);
    });
  });
}
