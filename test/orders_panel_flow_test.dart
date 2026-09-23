import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/internet_order.dart';
import 'package:pharmacy_app/widgets/orders_panel.dart';
import 'package:pharmacy_app/services/order_extras_service.dart';

InternetOrder _order(String id, String reserve,
        {String phone = '380671234567',
        String name = 'Іваненко Іван',
        OrderStatus status = OrderStatus.collected,
        OrderType type = OrderType.tabletkiUA,
        double total = 200}) =>
    InternetOrder(
      id: id,
      reserveNumber: reserve,
      dateTime: DateTime.now().subtract(const Duration(hours: 2)),
      total: total,
      status: status,
      type: type,
      customerPhone: phone,
      customerName: name,
      items: [
        OrderItem(
            sku: 's$id',
            name: 'ТОВАР $id ДОВГА НАЗВА ПРЕПАРАТУ',
            manufacturer: 'Виробник',
            quantity: 1,
            price: total,
            total: total),
      ],
    );

Future<void> _pump(WidgetTester t, List<InternetOrder> orders,
    {Size size = const Size(420, 900)}) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: OrdersPanel(onClose: () {}, debugOrders: orders),
        ),
      ),
    ),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  final orders = [
    _order('1', '164431111'),
    _order('2', '164441111'),
    _order('3', '164450002', phone: '380509998877', name: 'Петренко Ольга'),
  ];

  testWidgets('пошук: телефон і П.І.Б. знаходять, назва товару — ні',
      (t) async {
    await _pump(t, orders);
    expect(find.text('164431111'), findsOneWidget);
    expect(find.text('164450002'), findsOneWidget);

    await t.enterText(find.byType(TextField), '0509998877');
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('164450002'), findsOneWidget);
    expect(find.text('164431111'), findsNothing);

    await t.enterText(find.byType(TextField), 'петренко');
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('164450002'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'довга назва');
    await t.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('серед Не оплачених не знайдено'),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('не знайдено серед Не оплачених → «Шукати» переходить на Всі',
      (t) async {
    await _pump(t, [
      _order('1', '164431111', status: OrderStatus.newOrder),
      _order('2', '164442222', status: OrderStatus.paidOnline),
    ]);
    await t.enterText(find.byType(TextField), '164442222');
    await t.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('серед Не оплачених не знайдено'),
        findsOneWidget);
    await t.tap(find.text('Шукати'));
    await t.pump(const Duration(milliseconds: 50));
    // Поле пошуку + рядок списку.
    expect(find.text('164442222'), findsNWidgets(2));
    expect(find.textContaining('серед Не оплачених'), findsNothing);
  });

  testWidgets('«Останній №» підставляє номер, введений раніше в сесії',
      (t) async {
    await _pump(t, orders);
    await t.enterText(find.byType(TextField), '0509998877');
    await t.pump(const Duration(milliseconds: 50));
    await t.enterText(find.byType(TextField), '');
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('Останній №'));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('164450002'), findsOneWidget);
    expect(find.text('164431111'), findsNothing);
  });

  testWidgets('4 цифри з дублем → вікно уточнення; повний номер — без нього',
      (t) async {
    await _pump(t, orders);
    await t.enterText(find.byType(TextField), '1111');
    await t.pump(const Duration(milliseconds: 800));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Уточнення замовлення'), findsOneWidget);
    await t.tap(find.text('Скасувати'));
    await t.pumpAndSettle();
    expect(find.text('Уточнення замовлення'), findsNothing);

    await t.enterText(find.byType(TextField).first, '0002');
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text('Уточнення замовлення'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('фільтр статусів — один вибір, за замовчуванням Не оплачені',
      (t) async {
    await _pump(t, [
      _order('1', '164431111', status: OrderStatus.newOrder),
      _order('2', '164442222', status: OrderStatus.paidOnline),
    ]);
    expect(find.text('164431111'), findsOneWidget);
    expect(find.text('164442222'), findsNothing);
    await t.ensureVisible(find.text('Оплачені'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Оплачені'));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('164431111'), findsNothing);
    expect(find.text('164442222'), findsOneWidget);
  });

  testWidgets('Не оплачені: Glovo і Нова пошта (не зібрані) — угорі',
      (t) async {
    await _pump(t, [
      _order('1', '164431111', status: OrderStatus.newOrder),
      _order('2', '164442222', status: OrderStatus.collected),
      _order('3', '164453333',
          status: OrderStatus.newOrder, type: OrderType.glovo),
      _order('4', '164464444',
          status: OrderStatus.inProgress, type: OrderType.novaPoshta),
      _order('5', '164475555',
          status: OrderStatus.collected, type: OrderType.glovo),
    ]);
    double y(String n) => t.getTopLeft(find.text(n)).dy;
    expect(y('164453333'), lessThan(y('164464444')));
    expect(y('164464444'), lessThan(y('164431111')));
    expect(y('164464444'), lessThan(y('164475555')));
  });

  testWidgets('лічильник на кнопці = підняті вгору «Не оплачених»',
      (t) async {
    // id підібрані під мок-хеш: 'S' і 'I' — з непрочитаним повідомленням.
    await _pump(t, [
      _order('S', '164400001', status: OrderStatus.newOrder),
      _order('h', '164400002',
          status: OrderStatus.newOrder, type: OrderType.glovo),
      _order('2', '164400003', status: OrderStatus.newOrder),
      _order('k', '164400004',
          status: OrderStatus.collected, type: OrderType.glovo),
      _order('I', '164400005', status: OrderStatus.paidOnline),
    ]);
    final s = OrdersAlerts.state.value;
    expect(s.count, 2);
    expect(s.hasUnread, isTrue);
  });

  testWidgets('об\'єднання: різні клієнти — відмова; один клієнт — один чек',
      (t) async {
    await _pump(t, orders);
    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(3));

    await t.tap(boxes.at(0));
    await t.pump();
    await t.tap(boxes.at(2));
    await t.pump();
    await t.tap(find.text('Об\'єднати (2)'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('належать різним клієнтам'), findsOneWidget);

    await t.tap(find.text('Зняти позначки'));
    await t.pump();
    await t.tap(boxes.at(0));
    await t.pump();
    await t.tap(boxes.at(1));
    await t.pump();
    await t.tap(find.text('Об\'єднати (2)'));
    await t.pumpAndSettle();
    expect(
        find.textContaining('Ви дійсно бажаєте об\'єднати обрані інтернет '
            'замовлення в один чек ? Клієнт має надати згоду.'),
        findsOneWidget);
    await t.tap(find.text('Так'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Об\'єднане замовлення · 2 шт.'), findsOneWidget);
    expect(find.text('№ резерву 164431111'), findsOneWidget);
    expect(find.text('№ резерву 164441111'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('повноекранний режим показує таблицю', (t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OrdersPanel(
          onClose: () {},
          debugOrders: orders,
          layout: OrdersPanelLayout.fullscreen,
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Перелік товарів'), findsOneWidget);
    expect(find.text('Статус замовлення'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
