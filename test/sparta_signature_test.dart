import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/sparta_signature.dart';

void main() {
  group('SpartaSignature.compute (doc 1.6.3 example)', () {
    // Приклад із документації Sparta (розділ 1.6.3 Requests signing):
    // chain = PARTNER1 + PLACE1 + '' + 1672575255000 + 1111 + '' + '' + '' + 9990000000012
    const chain = 'PARTNER1PLACE1167257525500011119990000000012';
    const posKey = 'SECRET1';

    test('повертає очікуваний signature', () {
      expect(
        SpartaSignature.compute(chain, posKey),
        'e08dbe34fbfe6bc6ee8b85f97b594995bb91b287091ed150d2d37b9e8be06b30',
      );
    });

    test('ланцюг збирається з частин (із «доковим» ms) дає той самий підпис', () {
      // Док рахує 13:14:15+02:00 → 1672575255000 (фактично 12:14:15 UTC, тобто
      // інтерпретація +01:00 — приклад згенеровано в зоні CET). Підставляємо
      // саме доковий ms, щоб перевірити складання ланцюга під відомий підпис.
      final built = SpartaSignature.chain([
        SpartaSignature.encodeString('PARTNER1'), // partnerCode
        SpartaSignature.encodeString('PLACE1'), // placeCode
        SpartaSignature.encodeString(''), // posCode (порожній)
        '1672575255000', // date (доковий ms)
        SpartaSignature.encodeString('1111'), // no
        SpartaSignature.encodeString(''), // documentNo
        SpartaSignature.encodeBool(false), // reverse
        SpartaSignature.encodeBool(null), // checkOnly (відсутній)
        SpartaSignature.encodeString('9990000000012'), // cardNo
      ]);
      expect(built, chain);
      expect(SpartaSignature.compute(built, posKey),
          'e08dbe34fbfe6bc6ee8b85f97b594995bb91b287091ed150d2d37b9e8be06b30');
    });

    // TZ розвʼязано: стандартний ISO→UTC ms — ПРАВИЛЬНИЙ (demo-сервер Спарти
    // прийняв tx/order, підписаний цим значенням, errorCode=0). Приклад у доку
    // (1672575255000, +01:00/CET) — хиба доку; реальний сервер чекає коректний UTC.
    test('encodeDateMs — стандартний ISO→UTC timestamp', () {
      expect(
        SpartaSignature.encodeDateMs(DateTime.parse('2023-01-01T13:14:15+02:00')),
        '1672571655000',
      );
    });
  });

  group('SpartaSignature.encodeNumber (×100, обрізання)', () {
    test('приклади з документації', () {
      expect(SpartaSignature.encodeNumber(20), '2000');
      expect(SpartaSignature.encodeNumber(20.56), '2056');
      expect(SpartaSignature.encodeNumber(20.1678), '2016'); // обрізання, не округлення
      expect(SpartaSignature.encodeNumber(-20.96), '-2096');
      expect(SpartaSignature.encodeNumber(10), '1000');
      expect(SpartaSignature.encodeNumber(-10), '-1000');
    });

    test('нуль і null', () {
      expect(SpartaSignature.encodeNumber(0), '0');
      expect(SpartaSignature.encodeNumber(null), '');
    });

    test('типова сума чека (79.5)', () {
      expect(SpartaSignature.encodeNumber(79.5), '7950');
    });
  });

  group('SpartaSignature.encodeBool / encodeString', () {
    test('bool: true→1, false/null→порожньо', () {
      expect(SpartaSignature.encodeBool(true), '1');
      expect(SpartaSignature.encodeBool(false), '');
      expect(SpartaSignature.encodeBool(null), '');
    });

    test('string: null→порожньо', () {
      expect(SpartaSignature.encodeString(null), '');
      expect(SpartaSignature.encodeString('ABC'), 'ABC');
    });
  });
}
