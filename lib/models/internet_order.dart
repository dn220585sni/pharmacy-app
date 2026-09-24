// ─────────────────────────────────────────────────────────────────────────────
// Internet order model — for online orders (TabletkiUA, ANCSite, apps, etc.)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../services/fiscal_log.dart';

/// Статус замовлення. Сервер (GetOrders, переписаний Катею 16.09.2026) віддає
/// його як текст українською з пробілом на початку (" Зібране"); старий
/// контракт — коди "apteka make" тощо. Парсер приймає обидва.
enum OrderStatus {
  newOrder,           // "" (пусто) / "Нове" — ще не оброблялося
  inProgress,         // "apteka got" / "apteka read" / "В обробці"
  collected,          // "apteka make" / "Зібране" — зібране в резерв
  atWork,             // "apteka work" / "В роботі" — є питання по замовленню
  paidOnline,         // "apteka pay" / "Відпущено" — оплачено в аптеці
  dispensed,          // LEGACY — keep for local checkout flow
  refused,            // LEGACY — keep for backward compat
  customerRefusal,    // "client otkaz" — Відмова клієнта (або 2 доби без приходу)
  pharmacyRefusal,    // "apteka otkaz" — Відмова аптеки
}

enum OrderType {
  tabletkiUA,   // tabletkiua — Таблетки
  ancSite,      // ANCSite — Сайт АНЦ
  iosApp,       // iosApp — Додаток АНЦ
  androidApp,   // androidApp — Додаток АНЦ
  likTas,       // lik-tas — Страхові
  otherShop,    // othershop — Інші
  optimTabl,    // optimtabl — замовлення Таблетки (Оптима)
  glovo,        // legacy — Glovo
  novaPoshta,   // legacy — Нова Пошта
  unknown,
}

class OrderItem {
  /// s-код партії (поле `skod` GetOrders, з 16.09.2026). Це код приходу, на
  /// якому тримаються GetSKUprice (стелажі), резерв і чек. Якщо сервер поле не
  /// віддав — сюди лягає `ids` (старий контракт), щоб нічого не зламати.
  final String sku;
  /// Код СЦ («сервер цін», поле `ids` GetOrders) = id товару на anc.ua.
  /// Саме він іде в GetSKUdetail і у фото/властивості з сайту. null, якщо
  /// `ids` порожній або містить «*» (тоді це ukod).
  final String? kodSc;
  final String? ukod;
  final String name;
  final String? manufacturer;
  final double quantity;
  final String? fraction; // e.g. "1/2"
  final double price;
  final double total;
  final String? expiryDate;
  final String? refusalReason;

  /// Позицію викреслено з замовлення (`StrikeOut` = "1", контракт 22.09).
  final bool strikeOut;

  // ── Enriched fields (populated from GetSKUdetail / GetSKUprice) ──────────
  String? enrichedImageUrl;
  String? enrichedSeries;
  String? enrichedExpiryDate;
  String? enrichedStorageLocation; // e.g. "Ст.А-12 / Вт.3"
  bool isEnriched = false;

  OrderItem({
    required this.sku,
    this.kodSc,
    this.ukod,
    required this.name,
    this.manufacturer,
    required this.quantity,
    this.fraction,
    required this.price,
    required this.total,
    this.expiryDate,
    this.refusalReason,
    this.strikeOut = false,
  });

  /// Приймає обидва контракти GetOrders:
  /// - 16.09: `skod`/`ids`/`ukod`/`name`;
  /// - 22.09 (Катя переписала під поля старого роздрібу): `SKod`/`Name`/
  ///   `Maker`/`ExpireDate`/`Refusal`/`Drob`/`StrikeOut` — кодів СЦ і ukod
  ///   у ньому НЕМАЄ, тож [kodSc]/[ukod] лишаються null, а [detailIds]
  ///   падає на s-код.
  factory OrderItem.fromJson(Map<String, dynamic> json) {
    String s(String a, [String? b]) =>
        (json[a] ?? (b == null ? null : json[b]))?.toString().trim() ?? '';
    final qty = double.tryParse(s('qty')) ?? 0;
    final ids = s('ids');
    final skod = s('skod', 'SKod');
    final ukodRaw = s('ukod');
    final maker = s('Maker');
    final expire = s('ExpireDate');
    final refusal = s('Refusal');
    final drob = s('Drob');
    return OrderItem(
      sku: skod.isNotEmpty ? skod : ids,
      kodSc: ids.isNotEmpty && !ids.contains('*') ? ids : null,
      ukod: ukodRaw.isNotEmpty ? ukodRaw : null,
      name: s('name', 'Name'),
      manufacturer: maker.isEmpty ? null : maker,
      quantity: qty,
      // `Drob` = "1" — ціла упаковка; інше ("1/2") — частка.
      fraction: drob.isEmpty || drob == '1' ? null : drob,
      price: double.tryParse(s('price')) ?? 0,
      total: double.tryParse(s('total')) ?? 0,
      expiryDate: expire.isEmpty ? null : expire,
      refusalReason: refusal.isEmpty ? null : refusal,
      strikeOut: s('StrikeOut') == '1',
    );
  }

  /// Службовий рядок («Знижка на чек» тощо): без кодів товару або з від'ємною
  /// сумою. Такі не збагачуємо, не скануємо й не резервуємо.
  bool get isServiceLine =>
      total < 0 || (sku.isEmpty && kodSc == null && ukod == null);

  /// Що слати в GetSKUdetail (`ids`): код СЦ, інакше ukod, інакше s-код.
  /// За спекою Каті `ids` без «*» — код серверу цін, з «*» — ukod.
  String get detailIds => kodSc ?? ukod ?? sku;
}

/// Замовлення, що увійшло до об'єднаного чека (ТЗ §9).
class MergedOrderRef {
  final String id;
  final String reserveNumber;
  final double total;
  const MergedOrderRef({
    required this.id,
    required this.reserveNumber,
    required this.total,
  });
}

class InternetOrder {
  final String id;
  final String reserveNumber;
  final DateTime dateTime;
  final double total;
  final OrderStatus status;
  final int? lockerCell;
  final OrderType type;
  final List<OrderItem> items;
  final String? customerPhone;
  final String? customerName;

  /// Marked by external service — urgent orders (Glovo, locker deadline, etc.)
  final bool isUrgent;

  /// Замовлення МОЖНА покласти в лікомат. Катя (23.09): поле сервісу
  /// `isLockerEligible` = "1" означає ПРОТИЛЕЖНЕ — «в лікомат класти не
  /// треба» (старий опис був помилковий), тож тут `!lockerForbidden`.
  /// Це дозвіл на дію, а не ознака «це замовлення з лікомата» — для неї є
  /// [isLockerOrder] (комірка вже призначена).
  final bool isLockerEligible;

  /// Сирий прапорець сервісу: "1" — у лікомат не класти.
  final bool lockerForbidden;

  /// Замовлення з лікомата: сервер дав комірку (`Likomat`).
  bool get isLockerOrder => lockerCell != null;

  /// Reason for pharmacy refusal (set when status == pharmacyRefusal).
  final String? refusalReason;

  /// Непорожній — це об'єднання кількох замовлень одного клієнта в один чек
  /// (включно з цим); [total] та [items] уже зведені.
  final List<MergedOrderRef> mergedFrom;

  bool get isMerged => mergedFrom.length > 1;

  // ── Поля контракту GetOrders від 22.09.2026 (Катя переписала сервіс під
  // те, що показує старий роздріб). У старому контракті їх немає → дефолти.

  /// Накладні за замовленням (`NumNaklList`, через ";").
  final List<String> nakladnaNumbers;

  /// Короткий перелік товарів (`GoodList`, через ", ").
  final String goodList;

  /// Сервер забороняє відкривати замовлення в інтерфейсі (`IsOpenDisabled`).
  final bool isOpenDisabled;

  /// Рядок для пошуку замовлення (`SearchData`) — що саме в ньому, Катя ще
  /// не описала; шукаємо по ньому як по підрядку.
  final String searchData;

  /// Автозбірка/автозамовлення (`Auto`).
  final bool isAuto;

  /// Чат із клієнтом (`Chat`: посилання або ознака), доставка (`Delivery`),
  /// строк готовності (`Timesrok`) — сирі рядки, поки контракт не уточнено.
  final String chat;
  final String delivery;
  final String timesrok;

  /// Сервер уже об'єднав це замовлення з іншими (`isMerge`).
  final bool isMergedOnServer;

  /// Потрібна ідентифікація клієнта Лайк перед відкриттям (`needSPLIdent`,
  /// перший токен "0"/"1"; далі сервер дописує підказку клавіші).
  final bool needSplIdent;

  /// Сирий тип/джерело з нового контракту (`TypeZ`, напр. "Глово") — для
  /// журналу й для випадків, коли [type] його не розпізнав.
  final String rawType;

  const InternetOrder({
    required this.id,
    required this.reserveNumber,
    required this.dateTime,
    required this.total,
    required this.status,
    this.lockerCell,
    required this.type,
    required this.items,
    this.customerPhone,
    this.customerName,
    this.isUrgent = false,
    this.isLockerEligible = false,
    this.lockerForbidden = false,
    this.refusalReason,
    this.mergedFrom = const [],
    this.nakladnaNumbers = const [],
    this.goodList = '',
    this.isOpenDisabled = false,
    this.searchData = '',
    this.isAuto = false,
    this.chat = '',
    this.delivery = '',
    this.timesrok = '',
    this.isMergedOnServer = false,
    this.needSplIdent = false,
    this.rawType = '',
  });

  // ── JSON parsing from GetOrders API ──────────────────────────────────────

  /// Приймає обидва контракти: 16.09 (`orderId`/`orderType`/`status`/
  /// `createdAt`/`totalAmount`/`customer*`) і 22.09 (`orderNumber`/`TypeZ`/
  /// `Status`/`DateTime`/`Sum`/`EditPhone`/…). У новому немає `orderId` —
  /// ідентифікатором стає номер замовлення (ним же живуть UpdateOrderStatus і
  /// GetOrderData, поки Катя не скаже інакше).
  factory InternetOrder.fromJson(Map<String, dynamic> json) {
    String s(String a, [String? b]) =>
        (json[a] ?? (b == null ? null : json[b]))?.toString() ?? '';
    final items = (json['items'] as List<dynamic>?)
            ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final status = _parseStatus(s('status', 'Status'));
    final rawType = s('orderType', 'TypeZ').trim();
    final type = _parseType(rawType);
    // "1" = у лікомат НЕ класти (Катя, 23.09) — в обох контрактах.
    final lockerForbidden = s('isLockerEligible').trim() == '1';

    // Parse date "09.03.2026 20:25:06"
    DateTime dateTime;
    try {
      final parts = s('createdAt', 'DateTime').trim().split(' ');
      final dateParts = parts[0].split('.');
      final timePart = parts.length > 1 ? parts[1] : '00:00:00';
      dateTime = DateTime.parse(
        '${dateParts[2]}-${dateParts[1]}-${dateParts[0]}T$timePart',
      );
    } catch (_) {
      dateTime = DateTime.now();
    }

    final orderNumber = s('orderNumber').trim();
    final orderId = s('orderId').trim();
    final editPhone = s('EditPhone').trim();
    final phone = s('customerPhone').trim();
    final likomat = s('Likomat').trim();
    final needSpl = s('needSPLIdent').trim();
    final lockerCell = int.tryParse(likomat);

    return InternetOrder(
      id: orderId.isNotEmpty ? orderId : orderNumber,
      reserveNumber: orderNumber,
      dateTime: dateTime,
      total: double.tryParse(s('totalAmount', 'Sum').trim()) ?? 0,
      status: status,
      type: type,
      items: items,
      lockerCell: lockerCell,
      customerPhone: phone.isNotEmpty
          ? phone
          : editPhone.isNotEmpty
              ? editPhone
              : null,
      customerName: _cleanName(json['customerName']?.toString()),
      // Терміновість — лише для замовлень із комірки лікомата; дозвіл
      // класти в лікомат є майже в усіх і терміновості не означає.
      isUrgent: lockerCell != null,
      isLockerEligible: !lockerForbidden,
      lockerForbidden: lockerForbidden,
      nakladnaNumbers: s('NumNaklList')
          .split(';')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
      goodList: s('GoodList').trim(),
      isOpenDisabled: s('IsOpenDisabled').trim() == '1',
      searchData: s('SearchData').trim(),
      isAuto: s('Auto').trim() == '1',
      chat: s('Chat').trim(),
      delivery: s('Delivery').trim(),
      timesrok: s('Timesrok').trim(),
      isMergedOnServer: s('isMerge').trim() == '1',
      needSplIdent: needSpl.isNotEmpty && needSpl.split(' ').first == '1',
      rawType: rawType,
    );
  }

  /// Контракт 22.09 — за наявністю ключів нового формату.
  static bool isNewContract(Map<String, dynamic> json) =>
      json.containsKey('Status') || json.containsKey('TypeZ');

  static final _loggedUnknownStatuses = <String>{};

  static OrderStatus _parseStatus(String raw) {
    switch (raw.toLowerCase().trim()) {
      // ── Текст українською (GetOrders з 16.09.2026, напр. " Зібране") ──
      case 'нове':
      case 'новий':
        return OrderStatus.newOrder;
      case 'в обробці':
      case 'обробляється':
      case 'прочитане':
        return OrderStatus.inProgress;
      case 'зібране':
      case 'зібрано':
        return OrderStatus.collected;
      case 'в роботі':
        return OrderStatus.atWork;
      case 'відпущено':
      case 'оплачено':
      case 'оплачене':
        return OrderStatus.paidOnline;
      case 'відмова аптеки':
        return OrderStatus.pharmacyRefusal;
      case 'відмова клієнта':
      case 'відмова':
        return OrderStatus.customerRefusal;

      // ── Коди старого контракту ──
      case '':
        return OrderStatus.newOrder;
      case 'apteka got':
      case 'apteka read':
        return OrderStatus.inProgress;
      case 'apteka make':
        return OrderStatus.collected;
      case 'apteka work':
        return OrderStatus.atWork;
      case 'apteka pay':
        return OrderStatus.paidOnline;
      case 'apteka otkaz':
        return OrderStatus.pharmacyRefusal;
      case 'client otkaz':
        return OrderStatus.customerRefusal;

      // ── Legacy fallbacks (old API strings) ──
      case 'new':
        debugPrint('Legacy order status "new" → newOrder');
        return OrderStatus.newOrder;
      case 'dispensed':
      case 'done':
        debugPrint('Legacy order status "$raw" → dispensed');
        return OrderStatus.dispensed;
      case 'refused':
      case 'disbanded':
        debugPrint('Legacy order status "$raw" → refused');
        return OrderStatus.refused;
      case 'customer_refusal':
        debugPrint('Legacy order status "customer_refusal" → customerRefusal');
        return OrderStatus.customerRefusal;
      case 'pharmacy_refusal':
        debugPrint('Legacy order status "pharmacy_refusal" → pharmacyRefusal');
        return OrderStatus.pharmacyRefusal;

      default:
        debugPrint('Unknown order status: "$raw"');
        if (_loggedUnknownStatuses.add(raw)) {
          FiscalLog.log('GetOrders: невідомий статус "$raw" → показуємо як «Нове»');
        }
        return OrderStatus.newOrder;
    }
  }

  static OrderType _parseType(String raw) {
    switch (raw.toLowerCase()) {
      case 'tabletkiua':
        return OrderType.tabletkiUA;
      case 'ancsite':
        return OrderType.ancSite;
      case 'iosapp':
        return OrderType.iosApp;
      case 'androidapp':
        return OrderType.androidApp;
      case 'lik-tas':
        return OrderType.likTas;
      case 'othershop':
        return OrderType.otherShop;
      case 'optimtabl':
        return OrderType.optimTabl;
      case 'glovo':
        return OrderType.glovo;
      case 'novaposhta':
      case 'nova-poshta':
        return OrderType.novaPoshta;
      default:
        return _parseTypeText(raw);
    }
  }

  static final _loggedUnknownTypes = <String>{};

  /// Тип із нового контракту (`TypeZ`) — текст як у старому роздрібі
  /// ("Глово" тощо). Повний перелік значень Катя не дала → збіг за
  /// підрядком, невідоме — в журнал один раз.
  static OrderType _parseTypeText(String raw) {
    final t = raw.toLowerCase().trim();
    if (t.isEmpty) return OrderType.unknown;
    if (t.contains('глово') || t.contains('glovo')) return OrderType.glovo;
    if (t.contains('нова') && t.contains('пошт')) return OrderType.novaPoshta;
    if (t.contains('оптим')) return OrderType.optimTabl;
    if (t.contains('таблет')) return OrderType.tabletkiUA;
    if (t.contains('страх')) return OrderType.likTas;
    if (t.contains('додат') || t.contains('android') || t.contains('ios')) {
      return OrderType.androidApp;
    }
    if (t.contains('сайт')) return OrderType.ancSite;
    if (t.contains('інш')) return OrderType.otherShop;
    if (_loggedUnknownTypes.add(t)) {
      FiscalLog.log('GetOrders: невідомий тип/джерело "$raw" → «Інше»');
    }
    return OrderType.unknown;
  }

  /// Clean customer name — remove "Default User" and trim.
  static String? _cleanName(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == 'Default User') return null;
    return trimmed;
  }

  // ── Labels ────────────────────────────────────────────────────────────────

  String get statusLabel {
    switch (status) {
      case OrderStatus.newOrder:        return 'Нове';
      case OrderStatus.inProgress:      return 'В обробці';
      case OrderStatus.collected:       return 'Зібране';
      case OrderStatus.atWork:          return 'В роботі';
      case OrderStatus.paidOnline:      return 'Відпущено';
      case OrderStatus.dispensed:       return 'Видане';           // legacy
      case OrderStatus.refused:         return 'Розформоване';     // legacy
      case OrderStatus.customerRefusal: return 'Відмова клієнта';
      case OrderStatus.pharmacyRefusal: return 'Відмова аптеки';
    }
  }

  String get typeLabel {
    switch (type) {
      case OrderType.tabletkiUA:
        return 'Таблетки';
      case OrderType.ancSite:
        return 'Сайт АНЦ';
      case OrderType.iosApp:
      case OrderType.androidApp:
        return 'Додаток АНЦ';
      case OrderType.likTas:
        return 'Страхові';
      case OrderType.otherShop:
        return 'Інші';
      case OrderType.optimTabl:
        return 'Таблетки (Оптима)';
      case OrderType.glovo:
        return 'Glovo';
      case OrderType.novaPoshta:
        return 'Нова Пошта';
      case OrderType.unknown:
        return 'Інше';
    }
  }

  /// Whether this order is "stale" — older than 3 days and not in a final status.
  bool get isStale {
    final age = DateTime.now().difference(dateTime).inDays;
    if (age < 3) return false;
    return status != OrderStatus.dispensed &&
        status != OrderStatus.refused &&
        status != OrderStatus.customerRefusal &&
        status != OrderStatus.pharmacyRefusal;
  }

  /// Human-readable age label for stale orders.
  String get staleLabel {
    final days = DateTime.now().difference(dateTime).inDays;
    return '$days дн.';
  }

  InternetOrder copyWith({
    OrderStatus? status,
    int? lockerCell,
    String? refusalReason,
    bool clearRefusalReason = false,
  }) {
    return InternetOrder(
      id: id,
      reserveNumber: reserveNumber,
      dateTime: dateTime,
      total: total,
      status: status ?? this.status,
      lockerCell: lockerCell ?? this.lockerCell,
      type: type,
      items: items,
      customerPhone: customerPhone,
      customerName: customerName,
      isUrgent: isUrgent,
      isLockerEligible: isLockerEligible,
      refusalReason:
          clearRefusalReason ? null : (refusalReason ?? this.refusalReason),
      mergedFrom: mergedFrom,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order data model — extended order info from GetOrderData API
// ─────────────────────────────────────────────────────────────────────────────

class OrderData {
  /// Non-empty fields: Ukrainian label → value
  final Map<String, String> fields;

  /// True when order was paid online via LiqPay (internet acquiring).
  final bool isPaidOnline;

  const OrderData(this.fields, {this.isPaidOnline = false});

  bool get isEmpty => fields.isEmpty;

  /// Human-readable labels for extra fields that ADD value for the pharmacist.
  /// Basic header fields (source, sum, phone, name, date, time, address)
  /// are intentionally excluded — they are already shown in the order header.
  /// Only these are displayed — everything already in the header is skipped.
  static const _labels = <String, String>{
    // Payment
    'payment_method': 'Спосіб оплати',
    'is_paid': 'Оплачено',
    'paidByPoints': 'Оплата балами',
    'coupon': 'Купон',
    // LiqPay
    'liqpay_status': 'LiqPay статус',
    'liqpay_amount': 'LiqPay сума',
    // Binance
    'binance_amount': 'Binance сума',
    // Delivery
    'delivery_uk': 'Доставка',
    // Delivery — Nova Poshta
    'newpost_RecipientName': 'НП отримувач',
    'newpost_RecipientsPhone': 'НП телефон',
    'newpost_recipientAddressName': 'НП адреса',
    'newpost_ServiceType': 'НП тип послуги',
    // Delivery — other
    'wD_service': 'Служба доставки',
    'wD_meest_name': 'Meest отримувач',
    'wD_meest_phone': 'Meest телефон',
    // Insurance
    'insur_org_name': 'Страхова компанія',
    'insur_user_name': 'Застрахована особа',
    // Medical / social
    'medical_program': 'Медична програма',
    'trusted_person': 'Довірена особа',
    'police_number': 'Номер поліса',
    'socialProgramCard': 'Соціальна картка',
    // Reimbursement
    'reimbursement_request_number': 'Номер реімбурсації',
  };

  factory OrderData.fromJson(Map<String, dynamic> json) {
    final data = json['Data'];
    if (data == null || data is! List || data.isEmpty) {
      return const OrderData({});
    }
    final raw = data[0] as Map<String, dynamic>;
    final fields = <String, String>{};
    for (final entry in _labels.entries) {
      final value = raw[entry.key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        fields[entry.value] = value;
      }
    }
    // Determine online payment: any of is_paid, liqpay_status, payment_method non-empty
    final isPaid = (raw['is_paid']?.toString().trim() ?? '').isNotEmpty ||
        (raw['liqpay_status']?.toString().trim() ?? '').isNotEmpty ||
        (raw['payment_method']?.toString().trim() ?? '').isNotEmpty;
    return OrderData(fields, isPaidOnline: isPaid);
  }
}
