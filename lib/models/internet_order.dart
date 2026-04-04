// ─────────────────────────────────────────────────────────────────────────────
// Internet order model — for online orders (TabletkiUA, ANCSite, apps, etc.)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

enum OrderStatus {
  newOrder,           // "" (пусто) — Нове, ще не оброблялося
  inProgress,         // "apteka got" / "apteka read" — В обробці
  collected,          // "apteka make" — Зібране в резерв
  atWork,             // "apteka work" — В роботі (є питання по замовленню)
  paidOnline,         // "apteka pay" — Оплачено онлайн (клієнт сплатив через еквайрінг)
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
  final String sku;     // ids (s-код)
  final String? ukod;
  final String name;
  final String? manufacturer;
  final double quantity;
  final String? fraction; // e.g. "1/2"
  final double price;
  final double total;
  final String? expiryDate;
  final String? refusalReason;

  const OrderItem({
    required this.sku,
    this.ukod,
    required this.name,
    this.manufacturer,
    required this.quantity,
    this.fraction,
    required this.price,
    required this.total,
    this.expiryDate,
    this.refusalReason,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final qty = double.tryParse(json['qty']?.toString() ?? '') ?? 0;
    return OrderItem(
      sku: json['ids']?.toString() ?? '',
      ukod: json['ukod']?.toString(),
      name: json['name']?.toString() ?? '',
      quantity: qty,
      price: double.tryParse(json['price']?.toString() ?? '') ?? 0,
      total: double.tryParse(json['total']?.toString() ?? '') ?? 0,
    );
  }
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

  /// Whether this order can be placed into a locker (parameter from service).
  final bool isLockerEligible;

  /// Reason for pharmacy refusal (set when status == pharmacyRefusal).
  final String? refusalReason;

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
    this.refusalReason,
  });

  // ── JSON parsing from GetOrders API ──────────────────────────────────────

  factory InternetOrder.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>?)
            ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final status = _parseStatus(json['status']?.toString() ?? '');
    final type = _parseType(json['orderType']?.toString() ?? '');
    final isLocker = json['isLockerEligible']?.toString() == '1';

    // Parse date "09.03.2026 20:25:06"
    DateTime dateTime;
    try {
      final parts = (json['createdAt']?.toString() ?? '').split(' ');
      final dateParts = parts[0].split('.');
      final timePart = parts.length > 1 ? parts[1] : '00:00:00';
      dateTime = DateTime.parse(
        '${dateParts[2]}-${dateParts[1]}-${dateParts[0]}T$timePart',
      );
    } catch (_) {
      dateTime = DateTime.now();
    }

    return InternetOrder(
      id: json['orderId']?.toString() ?? '',
      reserveNumber: json['orderNumber']?.toString() ?? '',
      dateTime: dateTime,
      total: double.tryParse(json['totalAmount']?.toString() ?? '') ?? 0,
      status: status,
      type: type,
      items: items,
      customerPhone: json['customerPhone']?.toString(),
      customerName: _cleanName(json['customerName']?.toString()),
      isUrgent: isLocker, // locker-eligible orders are automatically urgent
      isLockerEligible: isLocker,
    );
  }

  static OrderStatus _parseStatus(String raw) {
    switch (raw.toLowerCase().trim()) {
      // ── New API contract ──
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
      default:
        debugPrint('Unknown order type: $raw');
        return OrderType.unknown;
    }
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
      case OrderStatus.paidOnline:      return 'Оплачено онлайн';
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
    );
  }
}
