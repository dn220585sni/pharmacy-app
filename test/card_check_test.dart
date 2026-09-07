import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/card_check_service.dart';

void main() {
  group('CardCheckResult', () {
    test('canPay — жорсткий гейт: є PAN, значить платимо', () {
      // Катерина, 04.09: «якщо мій метод поверне PAN у відповіді, то
      // можна платити, інакше — ні, в Result причина чому ні».
      const ok = CardCheckResult(pan: '4054248631234567', result: 'ок');
      const no = CardCheckResult(pan: '', result: 'Товар не з переліку');
      expect(ok.canPay, isTrue);
      expect(no.canPay, isFalse);
      // Причину показуємо дослівно — вона належить серверу.
      expect(no.result, 'Товар не з переліку');
    });

    test('успіх — саме за наявністю PAN, а не за Status', () {
      // Катерина, 03.09: «якщо все ок PAN є у відповіді, інакше пусто і
      // Result пише причину». Status=OK буває й у відмові, тож на нього
      // спиратись не можна.
      const ok = CardCheckResult(
          pan: '405424863', result: 'Перевірка номера картки');
      expect(ok.isOk, isTrue);
    });

    test('порожній PAN — відмова, навіть із приязним Result', () {
      const bad =
          CardCheckResult(pan: '', result: 'Картка не належить програмі');
      expect(bad.isOk, isFalse);
      expect(bad.toString(), contains('Картка не належить програмі'));
    });

    test('у рядку результату номер маскується', () {
      const ok = CardCheckResult(pan: '6769659308590307', result: 'ок');
      expect(ok.toString(), 'OK pan=676965******0307');
      expect(ok.toString(), isNot(contains('6769659308590307')));
    });
  });

  group('maskPan', () {
    test('повний номер із ReadBonusCard — видно BIN і останні чотири', () {
      expect(CardCheckService.maskPan('6769659308590307'), '676965******0307');
    });

    test('розділювачі не ламають маску', () {
      expect(CardCheckService.maskPan('6769 6593 0859 0307'),
          '676965******0307');
    });

    test('короткий рядок ховається повністю — не вгадуємо, де що', () {
      // Приклад Катерини «405424863» це 9 цифр: не номер картки, і робити
      // вигляд, що ми знаємо його структуру, не варто.
      expect(CardCheckService.maskPan('405424863'), '*********');
      expect(CardCheckService.maskPan(''), '');
    });

    test('19-значний номер (Maestro) теж коректний', () {
      expect(CardCheckService.maskPan('6769659308590307123'),
          '676965*********7123');
    });
  });
}
