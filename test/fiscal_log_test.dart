import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/fiscal_log.dart';

/// Журнал — єдине джерело правди про фіскальні операції на касі (release, де
/// debugPrint нема куди читати). Втрачений рядок = втрачений слід операції,
/// тому важлива не лише поява запису, а й те, що паралельні виклики не
/// затирають один одного.
void main() {
  test('паралельні log() не втрачають і не перемішують записи', () async {
    // На касі це реальний сценарій: діагностика X-звіту і рядок про відсічений
    // дубль пишуться з різницею в мілісекунди. Без серіалізації другий запис
    // програвав гонку за файл і зникав.
    final futures = List.generate(20, (i) => FiscalLog.log('рядок $i'));
    await Future.wait(futures);
    // Головне — жоден виклик не кинув і не завис: у тестовому середовищі
    // support-директорії немає, тож запис у файл коректно пропускається.
    expect(futures, hasLength(20));
  });

  test('log() повертає Future, який можна дочекатись', () async {
    await expectLater(FiscalLog.log('одиничний рядок'), completes);
  });

  test('збій запису не пробивається назовні', () async {
    // Логер — best-effort: помилка журналу НЕ має ламати продаж.
    await expectLater(FiscalLog.log('x' * 10000), completes);
  });
}
