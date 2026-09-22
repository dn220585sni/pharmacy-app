import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/internet_order.dart';

/// Живий приклад відповіді GetOrders після того, як Катя переписала сервіс
/// (16.09.2026): додано `skod` (s-код партії), статус — текст українською
/// з пробілом на початку, «Знижка на чек» — окремий рядок без кодів.
const _kSample = r'''
{"Status":"OK","Orders":[{"orderId":"187405319","orderNumber":"187405319","orderType":"androidApp","status":" Зібране","createdAt":"31.08.2026 08:59:07","customerName":"Default User","customerPhone":"(067)7614500","totalAmount":"185.53","isLockerEligible":"","items":[{"ids":"1035702","ukod":"1275.999*49*452*10**20*10*","skod":"26324726","name":"НИКСАР ТАБЛ. 20МГ №10","qty":1.000,"price":185.53,"total":185.53},{"ids":"","ukod":"","skod":"","name":"Знижка на чек","qty":1.000,"price":-0.03,"total":-0.03}]},{"orderId":"187469211","orderNumber":"187469211","orderType":"othershop","status":" Зібране","createdAt":"31.08.2026 18:37:51","customerName":" Default User ","customerPhone":"(097)3117000","totalAmount":"369.08","isLockerEligible":"1","items":[{"ids":"4697","ukod":"1561*12*211**30***","skod":"25820053","name":"ТАНАКАН Р-Р 30 МЛ","qty":1.000,"price":369.08,"total":369.08},{"ids":"","ukod":"","skod":"","name":"Знижка на чек","qty":1.000,"price":-0.08,"total":-0.08}]}]}
''';

void main() {
  group('GetOrders (переписаний 16.09.2026)', () {
    final orders = (jsonDecode(_kSample)['Orders'] as List)
        .map((e) => InternetOrder.fromJson(e as Map<String, dynamic>))
        .toList();

    test('skod → sku (s-код партії), ids → kodSc (код СЦ), ukod окремо', () {
      final item = orders.first.items.first;
      expect(item.sku, '26324726');
      expect(item.kodSc, '1035702');
      expect(item.ukod, '1275.999*49*452*10**20*10*');
      expect(item.detailIds, '1035702');
      expect(item.isServiceLine, isFalse);
      expect(item.quantity, 1);
      expect(item.price, 185.53);
    });

    test('«Знижка на чек» — службовий рядок без кодів', () {
      final discount = orders.first.items.last;
      expect(discount.name, 'Знижка на чек');
      expect(discount.sku, '');
      expect(discount.kodSc, isNull);
      expect(discount.ukod, isNull);
      expect(discount.isServiceLine, isTrue);
      expect(discount.total, -0.03);
    });

    test('статус " Зібране" (з пробілом) → collected', () {
      expect(orders[0].status, OrderStatus.collected);
      expect(orders[1].status, OrderStatus.collected);
    });

    test('шапка: тип, дата, сума, Default User → без імені, постамат', () {
      final o = orders[1];
      expect(o.id, '187469211');
      expect(o.reserveNumber, '187469211');
      expect(o.type, OrderType.otherShop);
      expect(o.dateTime, DateTime(2026, 8, 31, 18, 37, 51));
      expect(o.total, 369.08);
      expect(o.customerName, isNull);
      expect(o.customerPhone, '(097)3117000');
      expect(o.isLockerEligible, isTrue);
      expect(orders[0].isLockerEligible, isFalse);
    });
  });

  group('OrderItem.fromJson — сумісність зі старим контрактом', () {
    test('без skod → sku бере ids (як було)', () {
      final item = OrderItem.fromJson({
        'ids': '26993528',
        'ukod': '762*1*47*6****',
        'name': 'ЦИТРАМОН',
        'qty': '1',
        'price': '10.00',
        'total': '10.00',
      });
      expect(item.sku, '26993528');
      expect(item.kodSc, '26993528');
      expect(item.detailIds, '26993528');
    });

    test('ids з «*» — це ukod, не код СЦ', () {
      final item = OrderItem.fromJson({
        'ids': '5511*3*14',
        'skod': '26140458',
        'name': 'X',
      });
      expect(item.sku, '26140458');
      expect(item.kodSc, isNull);
      expect(item.detailIds, '26140458');
    });
  });

  group('Статуси: старі коди й новий текст', () {
    OrderStatus parse(String s) =>
        InternetOrder.fromJson({'status': s, 'items': []}).status;

    test('коди старого контракту', () {
      expect(parse(''), OrderStatus.newOrder);
      expect(parse('apteka got'), OrderStatus.inProgress);
      expect(parse('apteka make'), OrderStatus.collected);
      expect(parse('apteka work'), OrderStatus.atWork);
      expect(parse('apteka pay'), OrderStatus.paidOnline);
      expect(parse('apteka otkaz'), OrderStatus.pharmacyRefusal);
      expect(parse('client otkaz'), OrderStatus.customerRefusal);
    });

    test('текст українською, регістр і пробіли не важливі', () {
      expect(parse(' Зібране'), OrderStatus.collected);
      expect(parse('НОВЕ'), OrderStatus.newOrder);
      expect(parse(' В обробці '), OrderStatus.inProgress);
      expect(parse('В роботі'), OrderStatus.atWork);
      expect(parse('Відпущено'), OrderStatus.paidOnline);
      expect(parse('Відмова аптеки'), OrderStatus.pharmacyRefusal);
      expect(parse('Відмова клієнта'), OrderStatus.customerRefusal);
    });
  });
}
