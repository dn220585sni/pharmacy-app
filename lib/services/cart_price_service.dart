import 'package:flutter/foundation.dart';
import '../models/cart_item.dart';
import '../models/customer_loyalty.dart';
import 'cache_api_client.dart';

/// Ціна однієї позиції кошика, як її розрахував сервер.
class CartItemPricing {
  /// Індекс позиції в кошику (узгоджено з порядком cart).
  final int index;

  /// Кількість (для блістера може бути дробовою).
  final double quantity;

  /// Ціна за одиницю після всіх знижок.
  final double unitPrice;

  /// Підсумок по позиції (`unitPrice * quantity`, з округленням).
  final double cost;

  /// Сума знижки на позицію (інформативно — для відображення).
  final double? lineDiscount;

  const CartItemPricing({
    required this.index,
    required this.quantity,
    required this.unitPrice,
    required this.cost,
    this.lineDiscount,
  });
}

/// Авторитетна калькуляція кошика — повертається сервером (`GetSumSkid`).
class CartPricing {
  /// Per-item калькуляція.
  final List<CartItemPricing> items;

  /// Сума цін до знижок.
  final double subtotal;

  /// Сумарна знижка.
  final double discount;

  /// Підсумок до оплати (без cash withdrawal).
  final double total;

  /// Чи це відповідь сервера (`true`) чи локальна калькуляція-фолбек (`false`).
  final bool fromServer;

  /// Час обчислення — для діагностики race conditions.
  final DateTime computedAt;

  CartPricing({
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.fromServer,
    DateTime? computedAt,
  }) : computedAt = computedAt ?? DateTime.now();

  CartItemPricing? itemAt(int index) =>
      index >= 0 && index < items.length ? items[index] : null;

  /// Порожня калькуляція — для пустого кошика.
  factory CartPricing.empty({bool fromServer = false}) => CartPricing(
        items: const [],
        subtotal: 0,
        discount: 0,
        total: 0,
        fromServer: fromServer,
      );
}

/// Запит до сервера на правильні ціни кошика з урахуванням усіх знижок.
///
/// Поточна реалізація — **скелет**: повертає клієнтську калькуляцію з
/// невеликою затримкою (для перевірки UI loading state). Коли отримаємо
/// API contract `GetSumSkid` (Caché endpoint від Карпенко Катерини) —
/// підмінити внутрішню реалізацію на реальний HTTP-виклик. Сигнатура
/// методу `fetchTotals` має лишитись стабільною.
///
/// Реальний endpoint:
/// ```
/// GET {ApiConfig.cacheBaseUrl}?ServiceName=GetSumSkid&sessionId={...}&...
/// ```
/// Сирий response від `GetSumSkid` — типізована модель JSON.
class GetSumSkidResponse {
  final bool ok;
  final String? errorMessage;
  /// Фінальна сума до сплати з усіма знижками + округленням.
  final double sumCheck;
  /// Знижка на чек (зазвичай від'ємна — "віднімається" від суми).
  final double discount;
  /// Знижка від округлення (skidka_sumcheck) — копійки.
  final double roundingDiscount;
  final List<GetSumSkidItem> goods;

  const GetSumSkidResponse({
    required this.ok,
    required this.sumCheck,
    required this.discount,
    required this.roundingDiscount,
    required this.goods,
    this.errorMessage,
  });

  factory GetSumSkidResponse.fromJson(Map<String, dynamic> j) {
    final ok = j['Status'] == 'OK';
    if (!ok) {
      return GetSumSkidResponse(
        ok: false,
        sumCheck: 0,
        discount: 0,
        roundingDiscount: 0,
        goods: const [],
        errorMessage: j['Result']?.toString() ?? j['TextError']?.toString(),
      );
    }
    final raw = j['Goods'];
    final items = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(GetSumSkidItem.fromJson)
            .toList(growable: false)
        : const <GetSumSkidItem>[];
    return GetSumSkidResponse(
      ok: true,
      sumCheck: _toDouble(j['SumCheck']),
      discount: _toDouble(j['discount']),
      roundingDiscount: _toDouble(j['skidka_sumcheck']),
      goods: items,
    );
  }
}

/// Один товар з відповіді `GetSumSkid`.
class GetSumSkidItem {
  final String skod;
  final String name;
  final String nameUkr;
  final String manufacture;
  final double qty;
  /// Ціна за одиницю (вже з урахуванням позиційних знижок).
  final double price;
  /// Підсумок по позиції (`price * qty`, з округленням сервера).
  final double total;
  /// % знижки на позицію (від'ємний для знижки). Інформативно.
  final double discPercent;
  /// Закодоване правило знижки — для tooltip/audit. Приклад:
  /// `stop-price:41202:0:0,00{r:-20.00%:1:}`
  final String pravilo;

  const GetSumSkidItem({
    required this.skod,
    required this.name,
    required this.nameUkr,
    required this.manufacture,
    required this.qty,
    required this.price,
    required this.total,
    required this.discPercent,
    required this.pravilo,
  });

  factory GetSumSkidItem.fromJson(Map<String, dynamic> j) => GetSumSkidItem(
        skod: j['skod']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        nameUkr: j['nameukr']?.toString() ?? '',
        manufacture: j['manufacture']?.toString() ?? '',
        qty: _toDouble(j['qty']),
        price: _toDouble(j['price']),
        total: _toDouble(j['total']),
        discPercent: _toDouble(j['disc']),
        pravilo: j['pravilo']?.toString() ?? '',
      );
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
}

class CartPriceService {
  /// Поки `true` — `fetchTotals` повертається миттєво з клієнтською
  /// калькуляцією, а UI не показує loading/debounce. Перемкнути на `false`
  /// → debounce 500ms і loading state у `cart_panel` активуються автоматично.
  ///
  /// Add-to-cart на сервер відбувається через `sgVRoznSetLock` — він уже
  /// викликається в pos_screen на add/inc/dec/remove, тож server-side кошик
  /// синхронізується автоматично. На clear cart — `sgVRoznSetLock(qty=0)`
  /// для кожної позиції.
  static const isStubMode = false;

  /// Отримати правильні ціни кошика.
  ///
  /// [cart] — поточний вміст кошика.
  /// [loyalty] — клієнтська лояльність (бонусна карта/телефон), якщо є.
  /// [personalDiscountPercent] — активована персональна знижка (%).
  /// [bonusAmount] — сума списання бонусів.
  /// [socialProgramCode] — тег активованої соц-програми (`nameProject`).
  /// [orderId] — ID інтернет-замовлення (для онлайн-кошиків).
  /// [helsiNumber] — номер електронного рецепту з Helsi/eHealth.
  /// [typeProject] — тег спец-проекту (наприклад "Malyuk" для Пакунка Малюка).
  static Future<CartPricing> fetchTotals({
    required List<CartItem> cart,
    CustomerLoyalty? loyalty,
    double personalDiscountPercent = 0,
    double bonusAmount = 0,
    String? socialProgramCode,
    String? orderId,
    String? helsiNumber,
    String? typeProject,
  }) async {
    if (cart.isEmpty) {
      return CartPricing.empty();
    }
    if (isStubMode) {
      return _stubPricing(
        cart: cart,
        loyalty: loyalty,
        personalDiscountPercent: personalDiscountPercent,
        bonusAmount: bonusAmount,
        socialProgramCode: socialProgramCode,
      );
    }
    return _fetchFromServer(
      cart: cart,
      socialProgramCode: socialProgramCode,
      orderId: orderId,
      helsiNumber: helsiNumber,
      typeProject: typeProject,
    );
  }

  // ── STUB ───────────────────────────────────────────────────────────────────

  static CartPricing _stubPricing({
    required List<CartItem> cart,
    CustomerLoyalty? loyalty,
    double personalDiscountPercent = 0,
    double bonusAmount = 0,
    String? socialProgramCode,
  }) {
    final items = <CartItemPricing>[];
    var subtotal = 0.0;
    for (var i = 0; i < cart.length; i++) {
      final item = cart[i];
      final qty = item.isFractional
          ? item.fractionalQty! / item.drug.unitsPerPackage!
          : item.quantity.toDouble();
      final cost = _round2(item.total);
      items.add(CartItemPricing(
        index: i,
        quantity: qty,
        unitPrice: item.effectivePrice,
        cost: cost,
      ));
      subtotal += cost;
    }
    subtotal = _round2(subtotal);

    final pctDiscount = _round2(subtotal * personalDiscountPercent / 100);
    final totalDiscount = _round2(pctDiscount + bonusAmount);
    final total = _round2((subtotal - totalDiscount).clamp(0, double.infinity));

    debugPrint('CartPriceService STUB: subtotal=$subtotal '
        'discount=$totalDiscount total=$total '
        '(cart=${cart.length}, loyalty=${loyalty?.cardNo}, '
        'social=$socialProgramCode)');

    return CartPricing(
      items: items,
      subtotal: subtotal,
      discount: totalDiscount,
      total: total,
      fromServer: false,
    );
  }

  // ── REAL: GetSumSkid ───────────────────────────────────────────────────────

  /// Реальний виклик `GetSumSkid`. Передбачає що кошик уже синхронізовано
  /// з server-side state (через окремий "add to cart" API — поки невідомо
  /// як саме). Якщо server повертає `Goods` що не співпадає з локальним
  /// `cart` — fallback на локальну калькуляцію з логом.
  static Future<CartPricing> _fetchFromServer({
    required List<CartItem> cart,
    String? socialProgramCode,
    String? orderId,
    String? helsiNumber,
    String? typeProject,
  }) async {
    final params = <String, String>{
      if (socialProgramCode != null && socialProgramCode.isNotEmpty)
        'nameProject': socialProgramCode,
      if (orderId != null && orderId.isNotEmpty) 'orderId': orderId,
      if (helsiNumber != null && helsiNumber.isNotEmpty)
        'HelsiNUM': helsiNumber,
      if (typeProject != null && typeProject.isNotEmpty)
        'TypeProject': typeProject,
    };

    final response = await CacheApiClient().call('GetSumSkid', params: params);
    if (!response.isOk) {
      debugPrint('GetSumSkid FAIL: ${response.result}');
      return _stubPricing(cart: cart);
    }

    final parsed = GetSumSkidResponse.fromJson(response.data);
    if (!parsed.ok) {
      debugPrint('GetSumSkid bad payload: ${parsed.errorMessage}');
      return _stubPricing(cart: cart);
    }

    return _mapServerResponse(cart: cart, response: parsed);
  }

  /// Замапити server response → CartPricing.
  /// Прив'язує `Goods[].skod` до позиції кошика за `drug.skuCode` (або id).
  static CartPricing _mapServerResponse({
    required List<CartItem> cart,
    required GetSumSkidResponse response,
  }) {
    final byCode = <String, int>{};
    for (var i = 0; i < cart.length; i++) {
      final code = cart[i].drug.skuCode ?? cart[i].drug.id;
      byCode[code] = i;
    }

    final items = <CartItemPricing>[];
    var subtotal = 0.0;
    for (final g in response.goods) {
      final idx = byCode[g.skod] ?? items.length;
      final lineDiscountUah = g.discPercent != 0
          ? _round2((g.price * g.qty) * (g.discPercent.abs() / 100))
          : null;
      items.add(CartItemPricing(
        index: idx,
        quantity: g.qty,
        unitPrice: g.price,
        cost: g.total,
        lineDiscount: lineDiscountUah,
      ));
      subtotal += g.total;
    }
    subtotal = _round2(subtotal);

    // SumCheck — фінальна сума з усіма знижками + округленням.
    // discount/skidka_sumcheck — інформативні поля.
    final total = _round2(response.sumCheck);
    final discount = _round2((subtotal - total).clamp(0, double.infinity));

    return CartPricing(
      items: items,
      subtotal: subtotal,
      discount: discount,
      total: total,
      fromServer: true,
    );
  }

  static double _round2(num v) => (v * 100).round() / 100;
}
