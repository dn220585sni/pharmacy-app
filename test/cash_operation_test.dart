import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/cash_operation.dart';

// Реальні відповіді GetOperKassa, 2026-06-18.
const _out = '''
{"Status":"OK","Reasons":[{"name":"Инкассация"},{"name":"Ошибка вноса выноса"},
{"name":"Кража"},{"name":"Инкассация в кассу предприятия"},
{"name":"Инкассация-обналичивание Приват"},{"name":"Инкассация-обналичивание Ощад"},
{"name":"Инкассация-обналичивание Пумб"}]}
''';

const _all = '''
{"Status":"OK","Reasons":[{"name":"Служебное внесение"},{"name":"Инкассация"},
{"name":"Ошибка вноса выноса"},{"name":"Возврат суммы по инкассации"},
{"name":"Возврат украденных средств"},{"name":"Кража"},
{"name":"Инкассация в кассу предприятия"},{"name":"Внесение разменных купюр"},
{"name":"Инкассация-обналичивание Приват"},{"name":"Инкассация-обналичивание Ощад"},
{"name":"Инкассация-обналичивание Пумб"}]}
''';

// In з прапорцем morning (2026-06-19).
const _in = '''
{"Status":"OK","Reasons":[{"name":"Служебное внесение","morning":"1"},
{"name":"Ошибка вноса выноса","morning":"0"},
{"name":"Возврат суммы по инкассации","morning":"0"},
{"name":"Возврат украденных средств","morning":"0"},
{"name":"Внесение разменных купюр","morning":"0"}]}
''';

void main() {
  test('CashDirection.param відповідає бекенду', () {
    expect(CashDirection.cashIn.param, 'In');
    expect(CashDirection.cashOut.param, 'Out');
  });

  group('parseCashReasons', () {
    test('Out → 7 причин', () {
      final r = parseCashReasons(jsonDecode(_out));
      expect(r.length, 7);
      expect(r.first.name, 'Инкассация');
    });

    test('усі → містить службове внесення і внесення розмінних', () {
      final names = parseCashReasons(jsonDecode(_all)).map((e) => e.name);
      expect(names, contains('Служебное внесение'));
      expect(names, contains('Внесение разменных купюр'));
    });

    test('morning=1 позначає причину ранкового внесення', () {
      final r = parseCashReasons(jsonDecode(_in));
      final m = morningReason(r);
      expect(m, isNotNull);
      expect(m!.name, 'Служебное внесение');
      // решта — не ранкові
      expect(r.where((e) => e.morning).length, 1);
    });

    test('некоректна відповідь → порожньо', () {
      expect(parseCashReasons(null), isEmpty);
      expect(parseCashReasons({'Status': 'BAD'}), isEmpty);
    });
  });

  group('cashReasonUa', () {
    test('мапить відомі причини на українську', () {
      expect(cashReasonUa('Инкассация'), 'Інкасація');
      expect(cashReasonUa('Служебное внесение'), 'Службове внесення');
      expect(cashReasonUa('Кража'), 'Крадіжка');
    });
    test('невідому причину повертає як є (fallback)', () {
      expect(cashReasonUa('Щось нове'), 'Щось нове');
    });
  });
}
