import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/prro_service.dart';

/// A1 — ідемпотентність фіскалізації.
///
/// Перевіряємо матчер, за яким вирішується «чек уже зареєстровано → повтор НЕ
/// робимо». Помилка тут = або дубль чека в ПРРО, або пропущена фіскалізація,
/// тож кожен кейс тут про гроші.
void main() {
  PrroShiftCheck check({
    required String type,
    required String orderNum,
    int? localNumber,
    double sum = 100,
    String? datetime,
  }) =>
      PrroShiftCheck(
        type: type,
        orderNum: orderNum,
        sum: sum,
        datetime: datetime,
        localNumber: localNumber,
      );

  group('PrroService.matchCheck', () {
    test('знаходить чек продажу за local_number', () {
      final checks = [
        check(type: 'Z_SALE', orderNum: '101', localNumber: 5001),
        check(type: 'Z_SALE', orderNum: '102', localNumber: 5002),
      ];
      final hit = PrroService.matchCheck(checks, localNumber: 5002);
      expect(hit, isNotNull);
      expect(hit!.orderNum, '102');
    });

    test('немає збігу → null (чек треба створювати)', () {
      final checks = [check(type: 'Z_SALE', orderNum: '101', localNumber: 5001)];
      expect(PrroService.matchCheck(checks, localNumber: 5999), isNull);
    });

    test('порожня зміна → null', () {
      expect(PrroService.matchCheck(const [], localNumber: 5001), isNull);
    });

    test('чеки без local_number ніколи не матчаться', () {
      final checks = [
        check(type: 'Z_SALE', orderNum: '101'),
        check(type: 'Z_SALE', orderNum: '102'),
      ];
      expect(PrroService.matchCheck(checks, localNumber: 5001), isNull);
    });

    test('повернення з тим самим local_number не рахується за продаж', () {
      final checks = [
        check(type: 'Z_RETURN', orderNum: '200', localNumber: 5001),
      ];
      expect(PrroService.matchCheck(checks, localNumber: 5001), isNull);
      expect(
        PrroService.matchCheck(checks, localNumber: 5001, isReturn: true),
        isNotNull,
      );
    });

    test('продаж не приймається за повернення', () {
      final checks = [check(type: 'Z_SALE', orderNum: '201', localNumber: 5001)];
      expect(
        PrroService.matchCheck(checks, localNumber: 5001, isReturn: true),
        isNull,
      );
    });

    test('обидва типи в зміні → кожен знаходить свій', () {
      final checks = [
        check(type: 'Z_SALE', orderNum: '301', localNumber: 7000),
        check(type: 'Z_RETURN', orderNum: '302', localNumber: 7000),
      ];
      expect(
        PrroService.matchCheck(checks, localNumber: 7000)!.orderNum,
        '301',
      );
      expect(
        PrroService.matchCheck(checks, localNumber: 7000, isReturn: true)!
            .orderNum,
        '302',
      );
    });

    test('тип у нижньому регістрі теж розпізнається', () {
      final checks = [
        check(type: 'z_return', orderNum: '303', localNumber: 7001),
      ];
      expect(
        PrroService.matchCheck(checks, localNumber: 7001, isReturn: true),
        isNotNull,
      );
    });
  });

  group('PrroShiftCheck.fromJson', () {
    test('local_number читається з відповіді X-звіту', () {
      final c = PrroShiftCheck.fromJson({
        'type': 'Z_SALE',
        'order_num': '4000952779-1',
        'datetime': '26.08.2026 14:31:02',
        'local_number': 5001,
        'sum': 123.45,
      });
      expect(c.localNumber, 5001);
      expect(c.orderNum, '4000952779-1');
      expect(c.sum, 123.45);
    });

    test('тип читається з ключа `type_` — реальний payload CashDesk', () {
      // Точний елемент `checks_list` з X-звіту тестової каси (01.09.2026,
      // прислав Андрій Попов). Ключ саме `type_`, з підкресленням.
      // Ми читали `type`, тому поле було завжди порожнім — а на ньому тримався
      // відсів протилежного типу в `matchCheck`, тож звірка дублів A1 для
      // повернень не спрацьовувала жодного разу.
      final c = PrroShiftCheck.fromJson({
        'datetime': '01.09.2026 09:51:26',
        'local_number': '668',
        'order_num': 'Mh-PJdyDWjU',
        'payments': [],
        'sum': 27483.80,
        'tax': [],
        'type_': 'SERVICE_INPUT',
      });
      expect(c.type, 'SERVICE_INPUT');
      expect(c.localNumber, 668);
      expect(c.sum, 27483.80);
    });

    test('старий ключ `type` теж читається (запасний варіант)', () {
      final c = PrroShiftCheck.fromJson({'type': 'Z_SALE', 'sum': 10});
      expect(c.type, 'Z_SALE');
    });

    test('повернення з `type_` матчиться, а продаж під нього НЕ підпадає', () {
      final checks = [
        PrroShiftCheck.fromJson({
          'type_': 'Z_RETURN',
          'order_num': '200',
          'local_number': 5001,
          'sum': 50,
        }),
      ];
      // До виправлення ключа тут завжди був null: порожній `type` не містив
      // 'RETURN', і повернення відсівалось власною ж умовою.
      expect(
        PrroService.matchCheck(checks, localNumber: 5001, isReturn: true),
        isNotNull,
      );
      expect(
        PrroService.matchCheck(checks, localNumber: 5001, isReturn: false),
        isNull,
      );
    });

    test('відсутній local_number → null (звірка неможлива, не 0)', () {
      final c = PrroShiftCheck.fromJson({'type': 'Z_SALE', 'sum': 10});
      expect(c.localNumber, isNull);
    });

    test('local_number РЯДКОМ — реальна відповідь каси 1334', () {
      // Точний формат із живого X-звіту: local_number рядком, sum числом.
      // Жорсткий каст `as num?` кидав виняток і валив розбір УСЬОГО X-звіту —
      // звірка дублікатів A1 через це мовчки не працювала.
      final c = PrroShiftCheck.fromJson({
        'type': 'Z_SALE',
        'order_num': 'lubcs0eFvXU',
        'datetime': '26.08.2026 22:01:06',
        'local_number': '2900661785',
        'sum': 93,
      });
      expect(c.localNumber, 2900661785);
      expect(c.sum, 93);
    });

    test('sum рядком теж переживається', () {
      final c = PrroShiftCheck.fromJson({'type': 'Z_SALE', 'sum': '0.5'});
      expect(c.sum, 0.5);
    });

    test('sum рядком із комою → double', () {
      final c = PrroShiftCheck.fromJson({'type': 'Z_SALE', 'sum': '11700,3'});
      expect(c.sum, 11700.3);
    });

    test('local_number рядком → int', () {
      final c = PrroShiftCheck.fromJson({
        'type': 'Z_SALE',
        'local_number': '2900661785',
        'sum': 10,
      });
      expect(c.localNumber, 2900661785);
    });

    test('сміття в sum → 0, розбір не падає', () {
      final c = PrroShiftCheck.fromJson({'type': 'Z_SALE', 'sum': 'н/д'});
      expect(c.sum, 0);
    });
  });

  group('PrroXReport.fromJson — числа рядками', () {
    test('увесь звіт розбирається, коли суми прийшли рядками', () {
      final r = PrroXReport.fromJson({
        'shift_state': true,
        'cash_in_box': '11700,3',
        'cash_in_box_start': '0',
        'service_input': '11700.3',
        'real': {'orders_count': '2', 'sum': '0,5'},
        'checks_list': [
          {
            'type': 'Z_SALE',
            'order_num': 'lubcs0eFvXU',
            'local_number': '2900661785',
            'sum': 93,
          },
        ],
      });
      expect(r.shiftOpen, isTrue);
      expect(r.cashInBox, 11700.3);
      expect(r.serviceInput, 11700.3);
      expect(r.ordersCount, 2);
      expect(r.ordersSum, 0.5);
      expect(r.checks, hasLength(1));
      // Головне: чек доїхав до матчера, а не загубився разом із розбором.
      expect(
        PrroService.matchCheck(r.checks, localNumber: 2900661785),
        isNotNull,
      );
    });
  });

  group('PrroResult.recovered', () {
    test('звичайний успіх — не recovered', () {
      const r = PrroResult(success: true, orderNum: '101');
      expect(r.recovered, isFalse);
    });

    test('failure — не recovered', () {
      const r = PrroResult.failure(
        error: 'Таймаут',
        errorKind: PrroErrorKind.connection,
      );
      expect(r.recovered, isFalse);
      expect(r.success, isFalse);
    });
  });
}
