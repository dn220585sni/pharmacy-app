import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/shift_service.dart';

void main() {
  group('isShiftAlreadyOpenError', () {
    test('дослівна відповідь ПРРО — «Зміна відкрита»', () {
      // Саме цей текст приходив 09.09 і 10.09 (журнали Кудрявської й user).
      // Стара звірка шукала «вже відкрита» / «не закрили зміну» — і гілка
      // відновлення не спрацьовувала ЖОДНОГО разу: каса застрягала без зміни.
      expect(ShiftService.isShiftAlreadyOpenError('Зміна відкрита'), isTrue);
    });

    test('старі формулювання теж лишаються розпізнаними', () {
      expect(ShiftService.isShiftAlreadyOpenError('Зміна вже відкрита'), isTrue);
      expect(
          ShiftService.isShiftAlreadyOpenError(
              'Ви не закрили зміну за попередній день'),
          isTrue);
    });

    test('регістр і пробіли не мають значення', () {
      expect(ShiftService.isShiftAlreadyOpenError('  ЗМІНА ВІДКРИТА  '), isTrue);
    });

    test('інші відмови — не «вже відкрита»', () {
      // Помилково впізнати тут відмову означало б зайвий авто-Z.
      expect(ShiftService.isShiftAlreadyOpenError('Помилка авторизації ПРРО'),
          isFalse);
      expect(ShiftService.isShiftAlreadyOpenError('Немає зʼєднання з ПРРО'),
          isFalse);
      expect(ShiftService.isShiftAlreadyOpenError('Зміну закрито'), isFalse);
      expect(ShiftService.isShiftAlreadyOpenError(''), isFalse);
    });
  });

  group('isPrroBusy', () {
    test('дослівна відмова ПРРО на паралельний запит', () {
      // 10.09 09:57:44: відновлення A3 і стану зміни смикнули xReport разом.
      expect(
          ShiftService.isPrroBusy('Виконується попередній запит для '
              '"4000952779". Повторіть запит через 5-30 секунд.'),
          isTrue);
    });

    test('звичайні помилки не вважаються «зайнято»', () {
      // На них повтор лише затягнув би старт: ПРРО справді недоступний.
      expect(ShiftService.isPrroBusy('Немає зʼєднання з ПРРО'), isFalse);
      expect(ShiftService.isPrroBusy('таймаут'), isFalse);
      expect(ShiftService.isPrroBusy(''), isFalse);
    });
  });
}
