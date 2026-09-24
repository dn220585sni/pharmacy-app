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
      // Катя 23.09: "1" = у лікомат НЕ класти (старий опис був навпаки).
      expect(o.lockerForbidden, isTrue);
      expect(o.isLockerEligible, isFalse);
      expect(orders[0].lockerForbidden, isFalse);
      expect(orders[0].isLockerEligible, isTrue);
      // Без комірки це не замовлення з лікомата і не термінове.
      expect(o.isLockerOrder, isFalse);
      expect(o.isUrgent, isFalse);
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

  // Контракт 22.09.2026: Катя переписала GetOrders під поля старого роздрібу
  // (приклад з її коментаря в доку сервісів). Ключі інші, `orderId`, `ids`,
  // `ukod` і `customerPhone` зникли.
  group('GetOrders (контракт 22.09 — поля старого роздрібу)', () {
    const sample = r'''
{"Status":"OK","Orders":[{"orderNumber":"184550439","DateTime":"08.08.2026 19:29:21","Sum":"193.10","Status":" Зібране","Likomat":"","TypeZ":"Глово","NumNaklList":"2900661479","GoodList":"ПАКЕТ МАЙКА 30Х, АЛЕРЗИН ТАБЛ. 5","IsOpenDisabled":"1","SearchData":"101737513773","EditPhone":"","Auto":"0","Chat":"","Delivery":"","Timesrok":"","isMerge":"0","needSPLIdent":"0 Alt+0","isLockerEligible":"1","items":[{"SKod":"25233709","Name":"ПАКЕТ МАЙКА 30Х50 ФИРМЕННЫЙ (ЛІКИ-ЦЕ АНЦ)","Maker":"Україна","qty":1.000,"price":3.10,"total":3.10,"ExpireDate":"01.10.2040","Refusal":"","Drob":"1","StrikeOut":"0"},{"SKod":"26140464","Name":"АЛЕРЗИН ТАБЛ. 5МГ №14","Maker":"Egis, Угорщина","qty":1.000,"price":190.00,"total":190.00,"ExpireDate":"01.02.2031","Refusal":"","Drob":"1","StrikeOut":"0"},{"SKod":"","Name":"Знижка на чек","Maker":"","qty":1.000,"price":-0.10,"total":-0.10,"ExpireDate":"","Refusal":"","Drob":"","StrikeOut":""}]}]}
''';
    final raw = (jsonDecode(sample)['Orders'] as List).first as Map<String, dynamic>;
    final o = InternetOrder.fromJson(raw);

    test('розпізнається як новий контракт', () {
      expect(InternetOrder.isNewContract(raw), isTrue);
      expect(InternetOrder.isNewContract({'status': 'x'}), isFalse);
    });

    test('шапка: id = номер, дата з DateTime, сума з Sum, статус зі Status', () {
      expect(o.id, '184550439');
      expect(o.reserveNumber, '184550439');
      expect(o.dateTime, DateTime(2026, 8, 8, 19, 29, 21));
      expect(o.total, 193.10);
      expect(o.status, OrderStatus.collected);
      expect(o.type, OrderType.glovo);
      expect(o.rawType, 'Глово');
      expect(o.typeLabel, 'Glovo');
    });

    test('нові поля: накладні, перелік, заборона відкриття, пошук, SPL', () {
      expect(o.nakladnaNumbers, ['2900661479']);
      expect(o.goodList, 'ПАКЕТ МАЙКА 30Х, АЛЕРЗИН ТАБЛ. 5');
      expect(o.isOpenDisabled, isTrue);
      expect(o.searchData, '101737513773');
      expect(o.isAuto, isFalse);
      expect(o.isMergedOnServer, isFalse);
      expect(o.needSplIdent, isFalse); // "0 Alt+0" → перший токен 0
      expect(o.lockerForbidden, isTrue); // "1" = не класти в лікомат
      expect(o.isLockerEligible, isFalse);
      expect(o.lockerCell, isNull); // Likomat порожній
      expect(o.isLockerOrder, isFalse);
      expect(o.customerPhone, isNull); // EditPhone порожній
    });

    test('позиції: SKod → sku, без коду СЦ, виробник/термін/дріб', () {
      final first = o.items.first;
      expect(first.sku, '25233709');
      expect(first.kodSc, isNull);
      expect(first.ukod, isNull);
      expect(first.detailIds, '25233709'); // падає на s-код
      expect(first.name, 'ПАКЕТ МАЙКА 30Х50 ФИРМЕННЫЙ (ЛІКИ-ЦЕ АНЦ)');
      expect(first.manufacturer, 'Україна');
      expect(first.expiryDate, '01.10.2040');
      expect(first.fraction, isNull); // Drob "1" = ціла упаковка
      expect(first.strikeOut, isFalse);
      expect(first.isServiceLine, isFalse);
      expect(o.items[1].name, 'АЛЕРЗИН ТАБЛ. 5МГ №14');
    });

    test('«Знижка на чек» лишається службовим рядком', () {
      final d = o.items.last;
      expect(d.isServiceLine, isTrue);
      expect(d.total, -0.10);
      expect(d.manufacturer, isNull);
    });

    test('needSPLIdent "1 Alt+0" → потрібна ідентифікація; Likomat → комірка', () {
      final o2 = InternetOrder.fromJson({
        ...raw,
        'needSPLIdent': '1 Alt+0',
        'Likomat': '12',
        'EditPhone': '(067)1112233',
        'NumNaklList': '1;2; 3',
        'TypeZ': 'Нова Пошта',
      });
      expect(o2.needSplIdent, isTrue);
      expect(o2.lockerCell, 12);
      expect(o2.isLockerOrder, isTrue);
      expect(o2.isUrgent, isTrue);
      expect(o2.customerPhone, '(067)1112233');
      expect(o2.nakladnaNumbers, ['1', '2', '3']);
      expect(o2.type, OrderType.novaPoshta);
    });
  });
}
