import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/drug.dart';

Drug _row(String sku, int stock, {String? exp, String name = 'СМЕКТА №10'}) =>
    Drug(
      id: 'srv_$sku',
      name: name,
      manufacturer: '',
      category: '',
      price: 100,
      stock: stock,
      unit: 'шт',
      skuCode: sku,
      expiryDate: exp,
    );

List<String> _order(List<Drug> rows) =>
    (List.of(rows)..sort(Drug.compareSearchRows)).map((d) => d.skuCode!).toList();

void main() {
  group('порядок рядків пошуку', () {
    test('зміна залишку (продаж на іншій касі) не переставляє партії', () {
      final before = [
        _row('300', 10, exp: '01.05.2027'),
        _row('100', 5, exp: '01.05.2027'),
        _row('200', 8, exp: '01.05.2027'),
      ];
      // Сервер віддав у іншому порядку й з іншими залишками.
      final after = [
        _row('200', 8, exp: '01.05.2027'),
        _row('300', 10, exp: '01.05.2027'),
        _row('100', 2, exp: '01.05.2027'),
      ];
      expect(_order(before), ['100', '200', '300']);
      expect(_order(after), ['100', '200', '300']);
    });

    test('FEFO: коротший термін вище, незалежно від s-коду', () {
      expect(
        _order([
          _row('100', 5, exp: '01.09.2028'),
          _row('200', 5, exp: '01.03.2027'),
        ]),
        ['200', '100'],
      );
    });

    test('термін у форматі ММ/РР теж дає FEFO', () {
      expect(
        _order([
          _row('100', 5, exp: '08/28'),
          _row('200', 5, exp: '03/27'),
        ]),
        ['200', '100'],
      );
      expect(Drug.parseExpiryDate('02/27'), DateTime(2027, 2, 28));
      expect(Drug.parseExpiryDate('15.06.2027'), DateTime(2027, 6, 15));
      expect(Drug.parseExpiryDate('abc'), isNull);
    });

    test('рядок без залишку — нижче за наявні', () {
      expect(
        _order([
          _row('100', 0, exp: '01.03.2027'),
          _row('200', 5, exp: '01.09.2028'),
        ]),
        ['200', '100'],
      );
    });
  });
}
