import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/card_check_service.dart';

void main() {
  group('CardCheckResult', () {
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

    test('у рядку успіху видно номер — його шукатимуть у журналі', () {
      const ok = CardCheckResult(pan: '405424863', result: 'ок');
      expect(ok.toString(), 'OK pan=405424863');
    });
  });
}
