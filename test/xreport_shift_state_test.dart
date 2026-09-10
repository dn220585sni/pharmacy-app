import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/prro_service.dart';

PrroXReport _x(Object? state) => PrroXReport.fromJson({'shift_state': state});

void main() {
  group('shift_state', () {
    test('булеве true — відкрита (так відповідає ПРРО, docs/action_plan.md)', () {
      expect(_x(true).shiftOpen, isTrue);
      expect(_x(true).rawShiftState, 'true');
    });

    test('сире значення зберігається навіть коли його не розпізнано', () {
      // Саме заради цього поле й зʼявилось: 10.09 вікно Z при виході не
      // показалось, і треба бачити, ЩО прислав ПРРО, а не лише наш висновок.
      final x = _x('OPENED');
      expect(x.shiftOpen, isFalse);
      expect(x.rawShiftState, 'OPENED');
    });

    test('поля немає — raw теж null, а не рядок «null»', () {
      final x = PrroXReport.fromJson(const {});
      expect(x.shiftOpen, isFalse);
      expect(x.rawShiftState, isNull);
    });
  });
}
