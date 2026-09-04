import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/cash_register.dart';

void main() {
  /// Реальна відповідь GetKlient із опису Задачі 25.
  const items = [
    {'name': 'КАССА 1, Шевченко б-р, 71 (Копійка)', 'id': '1334'},
    {'name': 'КАССА 2, Шевченко б-р, 71 (Копійка)', 'id': '1335'},
    {'name': 'КАССА 3, Шевченко б-р, 71 (Копійка)', 'id': '1336'},
    {'name': 'КАССА 4, Шевченко б-р, 71 (Копійка) (поштомат)', 'id': '1525'},
  ];

  List<CashRegister> parseAll() => items
      .map((e) => CashRegister.fromJson(Map<String, dynamic>.from(e)))
      .whereType<CashRegister>()
      .toList();

  group('fromJson', () {
    test('розбирає всі чотири каси з прикладу', () {
      final regs = parseAll();
      expect(regs, hasLength(4));
      expect(regs.first.id, '1334');
      expect(regs.last.id, '1525');
    });

    test('рядок без id або без назви відкидається', () {
      expect(CashRegister.fromJson(const {'name': 'КАССА 1'}), isNull);
      expect(CashRegister.fromJson(const {'id': '1334'}), isNull);
      expect(CashRegister.fromJson(const {'id': ' ', 'name': 'X'}), isNull);
      expect(CashRegister.fromJson(const {}), isNull);
    });

    test('рівність — за id, бо саме він іде в KodKli', () {
      const a = CashRegister(id: '1334', name: 'КАССА 1');
      const b = CashRegister(id: '1334', name: 'зовсім інша назва');
      expect(a, b);
      expect({a, b}, hasLength(1));
    });
  });

  group('shortName', () {
    test('відкидає адресу й назву аптеки — у списку вони в усіх однакові', () {
      final regs = parseAll();
      expect(regs[0].shortName, 'КАССА 1');
      expect(regs[1].shortName, 'КАССА 2');
      expect(regs[2].shortName, 'КАССА 3');
    });

    test('друга дужка лишається — саме нею відрізняється поштомат', () {
      expect(parseAll()[3].shortName, 'КАССА 4 (поштомат)');
    });

    test('назва без коми віддається як є', () {
      expect(const CashRegister(id: '1', name: 'КАССА 1').shortName, 'КАССА 1');
    });

    test('назва, що починається з коми, не перетворюється на порожнечу', () {
      const r = CashRegister(id: '1', name: ', Шевченко б-р, 71');
      expect(r.shortName, ', Шевченко б-р, 71');
    });
  });
}
