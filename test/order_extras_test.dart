import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/internet_order.dart';
import 'package:pharmacy_app/models/order_extras.dart';
import 'package:pharmacy_app/services/order_extras_service.dart';
import 'package:pharmacy_app/widgets/orders/orders_grid.dart';

InternetOrder _order({
  String id = '1',
  String reserve = '164435516',
  double total = 500,
  OrderStatus status = OrderStatus.newOrder,
  OrderType type = OrderType.tabletkiUA,
  List<OrderItem>? items,
}) =>
    InternetOrder(
      id: id,
      reserveNumber: reserve,
      dateTime: DateTime(2026, 9, 21, 10),
      total: total,
      status: status,
      type: type,
      items: items ?? [],
    );

void main() {
  group('Час на збір (ТЗ §6)', () {
    const expiring = OrderExtras(sla: OrderSla.expiring);

    test('нове замовлення з ознакою — тривога діє', () {
      expect(OrderExtrasService.slaFor(_order(), expiring), OrderSla.expiring);
    });

    test('взяте в роботу / зібране / відмова — тривога знімається', () {
      for (final s in [
        OrderStatus.inProgress,
        OrderStatus.atWork,
        OrderStatus.collected,
        OrderStatus.pharmacyRefusal,
      ]) {
        expect(OrderExtrasService.slaFor(_order(status: s), expiring),
            OrderSla.none,
            reason: '$s');
      }
    });

    test('автопідтвердження не тривожить навіть із ознакою', () {
      const e = OrderExtras(sla: OrderSla.overdue, autoConfirm: true);
      expect(OrderExtrasService.slaFor(_order(), e), OrderSla.none);
    });
  });

  group('Повідомлення кол-центру (ТЗ §5)', () {
    test('писати можна лише по замовленнях понад 1000 грн', () {
      expect(OrderExtrasService.canSend(_order(total: 1000)), isFalse);
      expect(OrderExtrasService.canSend(_order(total: 1000.01)), isTrue);
      expect(OrderExtrasService.canSend(_order(total: 999)), isFalse);
    });

    test('надіслане зберігається в переписці й знімає «непрочитане»',
        () async {
      final o = _order(id: 'msg-1', total: 1500);
      await OrderExtrasService.fetchExtras([o]);
      final next = await OrderExtrasService.sendMessage(o, 'Збираємо', 'Іра');
      expect(next.messages.last.text, 'Збираємо');
      expect(next.messages.last.fromPharmacy, isTrue);
      expect(next.hasUnread, isFalse);
      expect(OrderExtrasService.of('msg-1').messages.last.text, 'Збираємо');
    });
  });

  test('мок-ознаки детерміновані: те саме замовлення — ті самі ознаки',
      () async {
    final a = await OrderExtrasService.fetchExtras([_order(id: 'det-7')]);
    final b = await OrderExtrasService.fetchExtras([_order(id: 'det-7')]);
    expect(a['det-7']!.autoConfirm, b['det-7']!.autoConfirm);
    expect(a['det-7']!.sla, b['det-7']!.sla);
  });

  test('код видачі (демо) = останні 4 цифри номера замовлення', () async {
    final o = _order(reserve: '164435516');
    expect(await OrderExtrasService.verifyIssueCode(o, '5516'), isTrue);
    expect(await OrderExtrasService.verifyIssueCode(o, '0000'), isFalse);
  });

  test('прев\'ю складу: перші 15 символів кожної назви, без «Знижки на чек»',
      () {
    final o = _order(items: [
      OrderItem(
          sku: '1',
          name: 'ПАРАЦЕТАМОЛ ТАБЛЕТКИ 0,2 Г №10',
          quantity: 1,
          price: 10,
          total: 10),
      OrderItem(sku: '2', name: 'НО-ШПА', quantity: 1, price: 5, total: 5),
      OrderItem(
          sku: '', name: 'Знижка на чек', quantity: 1, price: -1, total: -1),
    ]);
    expect(orderItemsPreview(o), 'ПАРАЦЕТАМОЛ ТАБ, НО-ШПА');
  });

  test('тип glovo з GetOrders розпізнається', () {
    final o = InternetOrder.fromJson({
      'orderId': '9',
      'orderNumber': '900001',
      'orderType': 'glovo',
      'status': ' Нове',
      'createdAt': '21.09.2026 10:00:00',
      'totalAmount': '120.5',
      'items': [],
    });
    expect(o.type, OrderType.glovo);
  });
}
