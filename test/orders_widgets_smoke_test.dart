import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/internet_order.dart';
import 'package:pharmacy_app/models/order_extras.dart';
import 'package:pharmacy_app/widgets/orders/order_duplicate_dialog.dart';
import 'package:pharmacy_app/widgets/orders/order_indicators.dart';
import 'package:pharmacy_app/widgets/orders/order_issue_block.dart';
import 'package:pharmacy_app/widgets/orders/order_messages_dialog.dart';
import 'package:pharmacy_app/widgets/orders/orders_grid.dart';

InternetOrder _order(String id, String reserve,
        {double total = 1500,
        OrderStatus status = OrderStatus.newOrder,
        OrderType type = OrderType.ancSite}) =>
    InternetOrder(
      id: id,
      reserveNumber: reserve,
      dateTime: DateTime(2026, 9, 21, 10, 5),
      total: total,
      status: status,
      type: type,
      customerPhone: '380671234567',
      customerName: 'Іваненко Іван',
      items: [
        OrderItem(
            sku: '26993528',
            name: 'ПАРАЦЕТАМОЛ ТАБЛЕТКИ 0,2 Г №10',
            manufacturer: 'Дарниця',
            quantity: 1,
            price: 10,
            total: 10),
      ],
    );

Widget _host(Widget child, {Size size = const Size(1400, 900)}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    );

void main() {
  testWidgets('таблиця замовлень: усі колонки ТЗ §3 і позначки', (t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final a = _order('a', '164431111');
    final b = _order('b', '164441111', status: OrderStatus.collected);
    final checked = <String>{};
    await t.pumpWidget(_host(OrdersGrid(
      orders: [a, b],
      extras: {
        'a': OrderExtras(sla: OrderSla.overdue, autoConfirm: false, messages: [
          OrderMessage(
              fromPharmacy: false,
              author: 'Кол-центр',
              text: 'Питання',
              time: DateTime(2026, 9, 21, 10, 30)),
        ], hasUnread: true),
        'b': const OrderExtras(autoConfirm: true),
      },
      checkedIds: checked,
      canCheck: (_) => true,
      onToggleCheck: (o) => checked.add(o.id),
      onOpen: (_) {},
      onOpenMessages: (_) {},
    )));
    await t.pump(const Duration(milliseconds: 300));
    for (final head in [
      'Дата та час',
      'Резерв',
      'Сума',
      'Статус замовлення',
      'Комірка',
      'Тип',
      'Перелік товарів',
    ]) {
      expect(find.text(head), findsOneWidget, reason: head);
    }
    expect(find.text('Час вийшов'), findsOneWidget);
    expect(find.byType(AutoConfirmMark), findsOneWidget);
    expect(find.byType(MessageEnvelope), findsOneWidget);
    expect(find.text('ПАРАЦЕТАМОЛ ТАБ'), findsNWidgets(2));
    await t.tap(find.byType(Checkbox).first);
    expect(checked, {'a'});
    expect(t.takeException(), isNull);
  });

  testWidgets('уточнення номера: невірний → помилка, вірний → закриває',
      (t) async {
    String? result = 'none';
    final dups = [_order('a', '164431111'), _order('b', '164441111')];
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => result = await showOrderDuplicateDialog(ctx,
              lastDigits: '1111', duplicates: dups),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Уточнення замовлення'), findsOneWidget);
    await t.enterText(find.byType(TextField), '999');
    await t.tap(find.text('ОК'));
    await t.pump();
    expect(find.text('Замовлення не знайдено. Введіть коректний номер'),
        findsOneWidget);
    await t.enterText(find.byType(TextField), '164441111');
    await t.tap(find.text('ОК'));
    await t.pumpAndSettle();
    expect(result, '164441111');
  });

  testWidgets('повідомлення: до 1000 грн писати не можна', (t) async {
    final cheap = _order('cheap', '164430001', total: 300);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => showOrderMessagesDialog(ctx, cheap),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Надіслати'), findsNothing);
    expect(find.textContaining('лише по замовленнях на суму понад'),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('передоплата: попередження, код видачі, SMS повтор', (t) async {
    final o = _order('p', '164435516', status: OrderStatus.collected);
    var verified = false;
    final ctrl = TextEditingController();
    await t.pumpWidget(_host(
      StatefulBuilder(
        builder: (ctx, setState) => SingleChildScrollView(
          child: OrderIssueBlock(
            order: o,
            extras: const OrderExtras(prepaid: true),
            paidOnlineConfirmed: false,
            verified: verified,
            onVerifiedChanged: (ok) => setState(() => verified = ok),
            prescriptionController: ctrl,
          ),
        ),
      ),
      size: const Size(380, 800),
    ));
    expect(
        find.text('Зверніть увагу. Дане замовлення не потребує оплати на місці'),
        findsOneWidget);
    expect(find.text('SMS повтор'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '5516');
    await t.tap(find.text('Перевірити'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    expect(verified, isTrue);
    expect(find.text('Код підтверджено'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
