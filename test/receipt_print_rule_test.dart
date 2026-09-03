import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/internet_order.dart';
import 'package:pharmacy_app/services/receipt_print_rule.dart';

void main() {
  group('electronicFromAnketa', () {
    test('«no» у будь-якому регістрі — клієнт електронного чека не отримує', () {
      expect(ReceiptPrintRule.electronicFromAnketa('no'), isFalse);
      expect(ReceiptPrintRule.electronicFromAnketa('NO'), isFalse);
      expect(ReceiptPrintRule.electronicFromAnketa(' No '), isFalse);
    });

    test('будь-яке інше непорожнє значення — отримує', () {
      expect(ReceiptPrintRule.electronicFromAnketa('yes'), isTrue);
      expect(ReceiptPrintRule.electronicFromAnketa('sms'), isTrue);
      expect(ReceiptPrintRule.electronicFromAnketa('email'), isTrue);
      // Саме тут ховається пастка назви поля: «1» це НЕ «друкувати».
      expect(ReceiptPrintRule.electronicFromAnketa('1'), isTrue);
    });

    test('порожньо або null — анкети немає, а не «не отримує»', () {
      expect(ReceiptPrintRule.electronicFromAnketa(null), isNull);
      expect(ReceiptPrintRule.electronicFromAnketa(''), isNull);
      expect(ReceiptPrintRule.electronicFromAnketa('   '), isNull);
    });
  });

  group('isMandatoryProgram', () {
    test('lik-tas — страхове замовлення', () {
      expect(ReceiptPrintRule.isMandatoryProgram(OrderType.likTas, const {}),
          isTrue);
    });

    test('поле реімбурсації робить звичайне ІЗ програмним', () {
      expect(
        ReceiptPrintRule.isMandatoryProgram(
            OrderType.ancSite, const {'Номер реімбурсації': '12345'}),
        isTrue,
      );
    });

    test('соцкартка й медпрограма теж', () {
      expect(
        ReceiptPrintRule.isMandatoryProgram(
            OrderType.tabletkiUA, const {'Соціальна картка': 'SC-7'}),
        isTrue,
      );
      expect(
        ReceiptPrintRule.isMandatoryProgram(
            OrderType.iosApp, const {'Медична програма': 'Доступні ліки'}),
        isTrue,
      );
    });

    test('порожнє значення поля не рахується за ознаку', () {
      expect(
        ReceiptPrintRule.isMandatoryProgram(
            OrderType.ancSite, const {'Номер реімбурсації': '  '}),
        isFalse,
      );
    });

    test('звичайне замовлення з магазину — не програмне', () {
      expect(
        ReceiptPrintRule.isMandatoryProgram(
            OrderType.tabletkiUA, const {'Спосіб оплати': 'LiqPay'}),
        isFalse,
      );
    });
  });

  group('decide — пріоритет умов', () {
    PrintDecision d({
      bool mandatory = false,
      bool iz = false,
      bool? electronic,
    }) =>
        ReceiptPrintRule.decide(
          mandatoryProgram: mandatory,
          internetOrder: iz,
          customerGetsElectronic: electronic,
        );

    test('типовий продаж: анкета дозволяє електронний — не друкуємо', () {
      expect(d(electronic: true),
          const PrintDecision(false, PrintReason.customerElectronic));
    });

    test('анкета = no — друкуємо', () {
      expect(d(electronic: false),
          const PrintDecision(true, PrintReason.customerOptedOut));
    });

    test('без картки ЖУК — друкуємо, бо каналу для електронного немає', () {
      expect(d(), const PrintDecision(true, PrintReason.noAnketa));
    });

    test('ІЗ не друкуємо, навіть якщо клієнт відмовився від електронного', () {
      expect(d(iz: true, electronic: false),
          const PrintDecision(false, PrintReason.internetOrder));
    });

    test('програмний чек б\'є ІЗ — саме заради цього потрібен пріоритет', () {
      expect(d(mandatory: true, iz: true, electronic: true),
          const PrintDecision(true, PrintReason.mandatoryProgram));
    });

    test('програмний чек б\'є й анкету', () {
      expect(d(mandatory: true, electronic: true),
          const PrintDecision(true, PrintReason.mandatoryProgram));
    });
  });

  group('частка друку', () {
    // Андрій: липень — 64 % без друку, серпень на 17.08 — 62 %. Якщо правило
    // колись почне друкувати майже все або майже нічого, цей тест не впаде —
    // але сама пропорція лишається головною перевіркою на живих даних.
    test('на змішаній вибірці друкується меншість', () {
      final sample = [
        for (var i = 0; i < 63; i++)
          ReceiptPrintRule.decide(
              mandatoryProgram: false,
              internetOrder: false,
              customerGetsElectronic: true),
        for (var i = 0; i < 37; i++)
          ReceiptPrintRule.decide(
              mandatoryProgram: false,
              internetOrder: false,
              customerGetsElectronic: false),
      ];
      final printed = sample.where((x) => x.shouldPrint).length;
      expect(printed, 37);
    });
  });
}
