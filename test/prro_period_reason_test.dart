import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/prro_service.dart';

void main() {
  group('explainPrroBody', () {
    test('реальна відповідь SmartConnect від 04.09.2026', () {
      const body =
          '{"message":"Присутні невигружені чеки за вказаний період",'
          '"type":"WARNING"}';
      expect(PrroService.explainPrroBody(body),
          'Присутні невигружені чеки за вказаний період');
    });

    test('type ігнорується — фармацевту потрібен текст, а не рівень', () {
      expect(
        PrroService.explainPrroBody('{"message":"Зміна відкрита","type":"ERROR"}'),
        'Зміна відкрита',
      );
    });

    test('не JSON — віддаємо як є, це все одно краще за здогадку', () {
      expect(PrroService.explainPrroBody('Bad Gateway'), 'Bad Gateway');
    });

    test('довгий текст вкорочується, щоб не рвати діалог', () {
      final long = 'x' * 300;
      final out = PrroService.explainPrroBody(long);
      expect(out.length, 161);
      expect(out.endsWith('…'), isTrue);
    });

    test('порожнє тіло — чесно кажемо, що пояснення немає', () {
      expect(PrroService.explainPrroBody(''),
          'ПРРО відповів помилкою без пояснення');
      expect(PrroService.explainPrroBody('   '),
          'ПРРО відповів помилкою без пояснення');
    });

    test('JSON без message — не вигадуємо, віддаємо тіло', () {
      expect(PrroService.explainPrroBody('{"type":"WARNING"}'),
          '{"type":"WARNING"}');
    });

    test('порожній message трактуємо як відсутній', () {
      expect(PrroService.explainPrroBody('{"message":"   ","type":"W"}'),
          '{"message":"   ","type":"W"}');
    });
  });

  group('PrroPeriodResult', () {
    test('ok несе звіт і не несе причини', () {
      final r = PrroPeriodResult.ok(PrroXReport.fromJson(const {}));
      expect(r.isOk, isTrue);
      expect(r.issue, isNull);
    });

    test('failed несе причину і не несе звіту', () {
      const r = PrroPeriodResult.failed('Присутні невигружені чеки');
      expect(r.isOk, isFalse);
      expect(r.report, isNull);
      expect(r.issue, 'Присутні невигружені чеки');
    });
  });
}
