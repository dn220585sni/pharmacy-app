import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/money.dart';
import 'package:pharmacy_app/models/stop_price_action.dart';

void main() {
  group('StopPriceRule.promoPriceMoney', () {
    test('відсоткова знижка: retail × (1 − %), округлено', () {
      // -20% від 100,00 → 80,00
      final r = StopPriceRule(kol: 1, praviloup: 'r:-20.00%:1:');
      expect(r.promoPriceMoney(Money.fromHryvnia(100)), Money.fromHryvnia(80));
    });

    test('відсоткова знижка з округленням копійок', () {
      // -10% від 19,99 → 17,991 → 17,99
      final r = StopPriceRule(kol: 1, praviloup: 'r:-10.00%:1:');
      expect(
          r.promoPriceMoney(Money.fromHryvnia(19.99)), Money.fromHryvnia(17.99));
    });

    test('абсолютна знижка у грн: retail − грн', () {
      // -32 грн від 100,00 → 68,00
      final r = StopPriceRule(kol: 1, praviloup: 'r:-32.00:1:');
      expect(r.promoPriceMoney(Money.fromHryvnia(100)), Money.fromHryvnia(68));
    });

    test('грн-знижка не опускає ціну нижче нуля', () {
      final r = StopPriceRule(kol: 1, praviloup: 'r:-150.00:1:');
      expect(r.promoPriceMoney(Money.fromHryvnia(100)), Money.zero);
    });

    test('нульова/некоректна роздрібна → null', () {
      final r = StopPriceRule(kol: 1, praviloup: 'r:-20.00%:1:');
      expect(r.promoPriceMoney(Money.zero), isNull);
    });

    test('без знижки → null', () {
      final r = StopPriceRule(kol: 1, praviloup: 'adddisk:0%:1:');
      expect(r.promoPriceMoney(Money.fromHryvnia(100)), isNull);
    });

    test('double-делегат узгоджений з Money-версією', () {
      final r = StopPriceRule(kol: 1, praviloup: 'r:-20.00%:1:');
      expect(r.promoPrice(100), 80.0);
    });
  });
}
