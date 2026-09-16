import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/cart_price_service.dart';

void main() {
  group('GetSumSkid: sumoplbonus (Катя, 16.09)', () {
    test('поле є — bonusPaid читається напряму', () {
      final r = GetSumSkidResponse.fromJson({
        'Status': 'OK',
        'SumCheck': '442',
        'discount': '-8.3881',
        'skidka_sumcheck': '40.47',
        'sumoplbonus': '40.00',
        'Goods': [],
      });
      expect(r.ok, isTrue);
      expect(r.bonusPaid, 40.0);
      expect(r.roundingDiscount, 40.47);
    });

    test('поля немає або порожнє — bonusPaid null (старий сервер → фолбек)',
        () {
      final none = GetSumSkidResponse.fromJson({
        'Status': 'OK',
        'SumCheck': '442',
        'skidka_sumcheck': '40.47',
        'Goods': [],
      });
      expect(none.bonusPaid, isNull);
      final empty = GetSumSkidResponse.fromJson({
        'Status': 'OK',
        'SumCheck': '442',
        'skidka_sumcheck': '0.47',
        'sumoplbonus': '',
        'Goods': [],
      });
      expect(empty.bonusPaid, isNull);
    });

    test('варіанти регістру ключа і кома як десятковий роздільник', () {
      final r = GetSumSkidResponse.fromJson({
        'Status': 'OK',
        'SumCheck': '100',
        'skidka_sumcheck': '10,5',
        'SumOplBonus': '10,5',
        'Goods': [],
      });
      expect(r.bonusPaid, 10.5);
    });
  });
}
