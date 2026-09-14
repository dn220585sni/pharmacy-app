import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/drug.dart';
import 'package:pharmacy_app/models/edk_offer.dart';

/// Кнопки панелі ЄДК залежать від реального залишку партії заміни.
/// Випадок Ремесуліду (14.09.2026): 0,2 уп. = 2 саше з 10 — «Упаковку»
/// ховаємо, «Блістер» лишаємо.
void main() {
  EdkOffer offer({double? stockRaw, int? units}) => EdkOffer(
        drug: Drug(
          id: 'srv_26015831',
          name: 'РЕМЕСУЛІД',
          manufacturer: '',
          category: '',
          price: 186,
          stock: stockRaw == null ? 1 : stockRaw.floor(),
          stockRaw: stockRaw,
          unit: 'шт',
          unitsPerPackage: units,
        ),
        donorDrugId: 'x',
        description: '',
        script: '',
      );

  test('0,2 уп. з 10 саше → упаковки немає, 2 саше є', () {
    final o = offer(stockRaw: 0.2, units: 10);
    expect(o.hasWholePackage, isFalse);
    expect(o.looseUnits, 2);
    expect(o.hasLooseUnit, isTrue);
  });

  test('залишок невідомий (рядка в таблиці нема) → кнопки лишаємо', () {
    final o = offer(stockRaw: null, units: 10);
    expect(o.hasWholePackage, isTrue);
    expect(o.looseUnits, isNull);
    expect(o.hasLooseUnit, isTrue);
  });

  test('8 цілих → упаковка є, підказки про саше немає', () {
    final o = offer(stockRaw: 8, units: 10);
    expect(o.hasWholePackage, isTrue);
    expect(o.looseUnits, isNull);
  });

  test('0,2 уп. товару, що не ділиться → ні упаковки, ні блістера', () {
    final o = offer(stockRaw: 0.2, units: null);
    expect(o.hasWholePackage, isFalse);
    expect(o.hasLooseUnit, isFalse);
  });

  test('нуль → нічого', () {
    final o = offer(stockRaw: 0, units: 10);
    expect(o.hasWholePackage, isFalse);
    expect(o.looseUnits, isNull);
    expect(o.hasLooseUnit, isFalse);
  });
}
