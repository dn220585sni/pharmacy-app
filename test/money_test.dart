import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/money.dart';

void main() {
  final nbsp = String.fromCharCode(0x00A0);

  group('Money — конструювання й округлення', () {
    test('fromKopiykas зберігає копійки точно', () {
      expect(const Money.fromKopiykas(12599).kopiykas, 12599);
      expect(Money.zero.kopiykas, 0);
    });

    test('fromHryvnia округлює до копійки (half-away-from-zero)', () {
      expect(Money.fromHryvnia(125.99).kopiykas, 12599);
      expect(Money.fromHryvnia(0.005).kopiykas, 1); // 0.5 коп → 1
      expect(Money.fromHryvnia(-0.005).kopiykas, -1);
      expect(Money.fromHryvnia(10).kopiykas, 1000);
    });
  });

  group('Money — арифметика без float-похибок (суть міграції)', () {
    test('0.10 + 0.20 == 0.30 (double тут бреше, Money — ні)', () {
      // Контроль: на double ця рівність хибна.
      expect(0.1 + 0.2 == 0.3, isFalse);
      // На Money — точно.
      final sum = Money.fromHryvnia(0.10) + Money.fromHryvnia(0.20);
      expect(sum, Money.fromHryvnia(0.30));
      expect(sum.kopiykas, 30);
    });

    test('накопичення багатьох позицій не дрейфує', () {
      var total = Money.zero;
      for (var i = 0; i < 10; i++) {
        total = total + Money.fromHryvnia(0.10);
      }
      expect(total, Money.fromHryvnia(1.00));
      expect(total.kopiykas, 100);
    });

    test('множення на кількість — точне', () {
      expect((Money.fromHryvnia(19.99) * 3).kopiykas, 5997);
    });

    test('відсоткова знижка округлюється детерміновано', () {
      // 100,00 грн × 12.5% = 12,50
      expect(Money.fromHryvnia(100).percent(12.5), Money.fromHryvnia(12.50));
      // 19,99 × 10% = 2,00 (1,999 → 2,00)
      expect(Money.fromHryvnia(19.99).percent(10), Money.fromHryvnia(2.00));
    });

    test('дробова позиція (блістери): ціна паковки × частина', () {
      // Паковка 84,00 грн, 10 блістерів, продаємо 3 → 25,20
      final perPack = Money.fromHryvnia(84.00);
      expect(perPack.fraction(3, 10), Money.fromHryvnia(25.20));
    });

    test('clamp обмежує діапазоном', () {
      final v = Money.fromHryvnia(50);
      expect(v.clampMoney(Money.zero, Money.fromHryvnia(30)),
          Money.fromHryvnia(30));
      expect(v.clampMoney(Money.fromHryvnia(60), Money.fromHryvnia(100)),
          Money.fromHryvnia(60));
    });

    test('abs і унарний мінус', () {
      expect((-Money.fromHryvnia(5)).kopiykas, -500);
      expect(Money.fromHryvnia(-5).abs, Money.fromHryvnia(5));
    });
  });

  group('Money — рівність і порівняння (прибирає == баги)', () {
    test('рівність за значенням, не за посиланням', () {
      expect(Money.fromHryvnia(12.34) == Money.fromHryvnia(12.34), isTrue);
      expect(Money.fromHryvnia(12.34).hashCode,
          Money.fromHryvnia(12.34).hashCode);
    });

    test('порядкові оператори', () {
      expect(Money.fromHryvnia(5) < Money.fromHryvnia(10), isTrue);
      expect(Money.fromHryvnia(10) >= Money.fromHryvnia(10), isTrue);
      expect(Money.zero.isZero, isTrue);
      expect(Money.fromHryvnia(-1).isNegative, isTrue);
    });

    test('придатний як ключ Set/Map', () {
      final s = {
        Money.fromHryvnia(1),
        Money.fromHryvnia(1),
        Money.fromHryvnia(2),
      };
      expect(s.length, 2);
    });
  });

  group('Money — парсинг', () {
    test('кома, крапка, групування тисяч (звичайний пробіл і nbsp)', () {
      expect(Money.tryParse('125,99'), Money.fromHryvnia(125.99));
      expect(Money.tryParse('125.99'), Money.fromHryvnia(125.99));
      expect(Money.tryParse('1 234,56'), Money.fromHryvnia(1234.56));
      expect(Money.tryParse('1${nbsp}234,56'), Money.fromHryvnia(1234.56));
    });

    test('порожнє/сміття → null (а не мовчазний 0)', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('   '), isNull);
      expect(Money.tryParse('abc'), isNull);
    });

    test('parse повертає zero для невалідного', () {
      expect(Money.parse('xyz'), Money.zero);
    });
  });

  group('Money — конвертація назовні', () {
    test('toHryvnia', () {
      expect(Money.fromHryvnia(125.99).toHryvnia(), 125.99);
    });

    test('toApiString — завжди 2 знаки з крапкою', () {
      expect(Money.fromHryvnia(125.5).toApiString(), '125.50');
      expect(Money.fromHryvnia(7).toApiString(), '7.00');
    });

    test('format — кома, символ, групування', () {
      expect(Money.fromHryvnia(125.99).format(), '125,99');
      expect(Money.fromHryvnia(125.99).format(symbol: true),
          '125,99 ${String.fromCharCode(0x20B4)}');
      expect(Money.fromHryvnia(7).format(), '7,00');
      expect(Money.fromHryvnia(1234.56).format(grouped: true), '1${nbsp}234,56');
      expect(Money.fromHryvnia(-5.5).format(), '-5,50');
    });
  });
}
