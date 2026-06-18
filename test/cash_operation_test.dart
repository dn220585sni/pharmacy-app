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

void main() {
  test('CashDirection.param відповідає бекенду', () {
    expect(CashDirection.cashIn.param, 'In');
    expect(CashDirection.cashOut.param, 'Out');
  });

  group('parseCashReasons', () {
    test('Out → 7 причин', () {
      final r = parseCashReasons(jsonDecode(_out));
      expect(r.length, 7);
      expect(r.first, 'Инкассация');
    });

    test('усі → містить службове внесення і внесення розмінних', () {
      final r = parseCashReasons(jsonDecode(_all));
      expect(r.length, 11);
      expect(r, contains('Служебное внесение'));
      expect(r, contains('Внесение разменных купюр'));
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
