import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/cart_item.dart';
import 'package:pharmacy_app/models/drug.dart';
import 'package:pharmacy_app/models/money.dart';

Drug _drug({double price = 0, int? unitsPerPackage}) => Drug(
      id: 'x',
      name: 'Test',
      manufacturer: 'M',
      category: 'C',
      price: price,
      stock: 100,
      unit: 'шт',
      unitsPerPackage: unitsPerPackage,
    );

void main() {
  group('CartItem.totalMoney', () {
    test('ціла кількість — точне множення', () {
      final item = CartItem(drug: _drug(price: 19.99), quantity: 3);
      expect(item.totalMoney, Money.fromHryvnia(59.97));
      expect(item.total, 59.97);
    });

    test('накопичення копійок не дрейфує', () {
      final item = CartItem(drug: _drug(price: 0.10), quantity: 3);
      expect(item.totalMoney.kopiykas, 30);
    });

    test('discountPrice має пріоритет над ціною препарату', () {
      final item =
          CartItem(drug: _drug(price: 100), quantity: 2, discountPrice: 80);
      expect(item.totalMoney, Money.fromHryvnia(160));
    });

    test('дробова позиція: частка ціни паковки, округлена', () {
      // Паковка 84,00 грн, 10 блістерів, 3 блістери → 25,20
      final item = CartItem(
        drug: _drug(price: 84.00, unitsPerPackage: 10),
        quantity: 1,
        fractionalQty: 3,
      );
      expect(item.totalMoney, Money.fromHryvnia(25.20));
    });
  });
}
