import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/loyalty_service.dart';
import 'package:pharmacy_app/services/receipt_print_rule.dart';

/// Реальні відповіді `customer/find` із листа Андрія Попова (03.09.2026),
/// тестове середовище `demo.spartaloyalty.com/TestAnc2`. Скорочено до полів,
/// що стосуються анкети; `cashreceipt` лишено дослівно.
const _yesPerson = '''
{"cardNo":"TS00000103","firstName":"Андрей","mobile":"+380676178812",
 "addonsList":[
  {"code":"children","value":null,"valueAsDictLabel":null},
  {"code":"ControlGroupDate","value":"2026-08-27T11:30:53.000+02:00","valueAsDictLabel":"Thu Aug 27 11:30:53 CEST 2026"},
  {"code":"cashreceiptlastdate","value":"24.01.2025","valueAsDictLabel":"24.01.2025"},
  {"code":"cashreceipt","value":"yes","valueAsDictLabel":"yes"},
  {"code":"pickupfromlikomat","value":"yes","valueAsDictLabel":"yes"},
  {"code":"chronic","value":["CHRON1","CHRON2"],"valueAsDictLabel":["CHRON1","CHRON2"]}
 ]}''';

const _noPerson = '''
{"cardNo":"12345678","birthYear":1972,"mobile":"+380991367026",
 "addonsList":[
  {"code":"children","value":1,"valueAsDictLabel":"1"},
  {"code":"cashreceiptlastdate","value":"","valueAsDictLabel":""},
  {"code":"cashreceipt","value":"no","valueAsDictLabel":"no"},
  {"code":"chronic","value":["CHRON1","CHRON2"],"valueAsDictLabel":["CHRON1","CHRON2"]}
 ]}''';

Map<String, dynamic> _p(String raw) => jsonDecode(raw) as Map<String, dynamic>;

void main() {
  group('addonsFrom', () {
    test('витягує cashreceipt із живої відповіді Спарти', () {
      expect(LoyaltyService.addonsFrom(_p(_yesPerson))['cashreceipt'], 'yes');
      expect(LoyaltyService.addonsFrom(_p(_noPerson))['cashreceipt'], 'no');
    });

    test('зберігає різнотипні значення як є', () {
      final a = LoyaltyService.addonsFrom(_p(_noPerson));
      expect(a['children'], 1);
      expect(a['chronic'], ['CHRON1', 'CHRON2']);
      // Порожній рядок — це заповнене поле з порожнім значенням, не відсутнє.
      expect(a['cashreceiptlastdate'], '');
    });

    test('null-значення потрапляють у мапу — ключ є, значення немає', () {
      final a = LoyaltyService.addonsFrom(_p(_yesPerson));
      expect(a.containsKey('children'), isTrue);
      expect(a['children'], isNull);
    });

    test('немає addonsList, не той тип, null person — порожньо, без винятку', () {
      expect(LoyaltyService.addonsFrom(null), isEmpty);
      expect(LoyaltyService.addonsFrom(const {}), isEmpty);
      expect(LoyaltyService.addonsFrom(const {'addonsList': 'нісенітниця'}),
          isEmpty);
      expect(LoyaltyService.addonsFrom(const {'addonsList': []}), isEmpty);
    });

    test('елементи без code пропускаються', () {
      final a = LoyaltyService.addonsFrom(const {
        'addonsList': [
          {'value': 'no'},
          {'code': '', 'value': 'no'},
          {'code': 'cashreceipt', 'value': 'no'},
        ]
      });
      expect(a, {'cashreceipt': 'no'});
    });
  });

  group('анкета → рішення про друк', () {
    PrintDecision decide(String raw) => ReceiptPrintRule.decide(
          mandatoryProgram: false,
          internetOrder: false,
          customerGetsElectronic: ReceiptPrintRule.electronicFromAnketa(
            LoyaltyService.addonsFrom(_p(raw))['cashreceipt']?.toString(),
          ),
        );

    test('cashreceipt=yes — електронний, паперу немає', () {
      expect(decide(_yesPerson),
          const PrintDecision(false, PrintReason.customerElectronic));
    });

    test('cashreceipt=no — друкуємо', () {
      expect(decide(_noPerson),
          const PrintDecision(true, PrintReason.customerOptedOut));
    });

    test('клієнта без поля cashreceipt трактуємо як без анкети', () {
      final flag = LoyaltyService.addonsFrom(const {
        'addonsList': [
          {'code': 'children', 'value': 1}
        ]
      })['cashreceipt'];
      expect(ReceiptPrintRule.electronicFromAnketa(flag?.toString()), isNull);
    });
  });
}
