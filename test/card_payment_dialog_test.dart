import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/money.dart';
import 'package:pharmacy_app/models/payment_terminal.dart';
import 'package:pharmacy_app/widgets/card_payment_dialog.dart';

void main() {
  const terminal = PaymentTerminal(
    kodterm: '1103',
    name: 'КАСА 1, Шевченко 71',
    bank: 'PrivatBank',
    bankCode: 'PRIVAT',
    isMain: true,
    termIP: '10.10.123.72',
    termPort: '2000',
  );

  Future<void> pumpDialog(WidgetTester tester, String outcome) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => CardPaymentDialog.show(
                ctx,
                terminal: terminal,
                amount: Money.fromHryvnia(199.99),
                demoOutcome: outcome,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(); // показати діалог
  }

  testWidgets('демо-успіх: проходить стани до «Оплата успішна»',
      (tester) async {
    await pumpDialog(tester, 'success');
    // Заголовок і сума одразу.
    expect(find.text('Оплата банк.карткою'), findsOneWidget);
    expect(find.textContaining('ОЧІКУЮ КАРТКУ'), findsNothing);

    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('ОЧІКУЮ КАРТКУ'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Виконується підтвердження оплати'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Оплата успішна'), findsOneWidget);

    // Дочекатись авто-закриття, щоб не лишити активний таймер.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  });

  testWidgets('демо-відхилення: показує кнопки повтору/готівки',
      (tester) async {
    await pumpDialog(tester, 'declined');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('ОПЕРАЦІЯ ВІДХИЛЕНА!'), findsOneWidget);
    expect(find.text('Повторити спробу оплати карткою'), findsOneWidget);
    expect(find.text('Відміна БГ / оплата готівкою'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  // Невідомий результат (таймаут після Purchase) — НЕ відмова: звичайних
  // кнопок «Повторити/готівка» немає, а новий платіж лише після того, як
  // касир підтвердить, що перевірив термінал.
  testWidgets('демо-невідомо: новий платіж лише через підтвердження',
      (tester) async {
    // Три кнопки + пояснення не вміщаються у типовий 800×600 тест-екран.
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDialog(tester, 'unknown');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Перевіряю результат на терміналі…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('РЕЗУЛЬТАТ ОПЛАТИ НЕВІДОМИЙ'), findsOneWidget);
    expect(find.text('Повторити спробу оплати карткою'), findsNothing);
    expect(find.text('Відміна БГ / оплата готівкою'), findsNothing);
    expect(find.text('Оплати не було — повторити карткою'), findsOneWidget);
    expect(find.text('Оплати не було — оплата готівкою'), findsOneWidget);

    // Кнопка готівки НЕ закриває вікно сама — спершу підтвердження.
    await tester.tap(find.text('Оплати не було — оплата готівкою'));
    await tester.pumpAndSettle();
    expect(find.text('Перевірте термінал'), findsOneWidget);
    expect(find.text('Оплата банк.карткою'), findsOneWidget);

    // «Назад» — лишаємось у вікні з невідомим результатом.
    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('РЕЗУЛЬТАТ ОПЛАТИ НЕВІДОМИЙ'), findsOneWidget);

    // Підтвердили — вікно закривається як «готівка» (null).
    await tester.tap(find.text('Оплати не було — оплата готівкою'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Так, оплати не було'));
    await tester.pumpAndSettle();
    expect(find.text('Оплата банк.карткою'), findsNothing);
  });
}
