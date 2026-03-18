// ─────────────────────────────────────────────────────────────────────────────
// Internet order model — for online orders (TabletkiUA, Glovo, etc.)
// ─────────────────────────────────────────────────────────────────────────────

enum OrderStatus {
  newOrder,           // Нове
  inProgress,         // В обробці
  collected,          // Зібране
  dispensed,          // Видане
  refused,            // Розформоване (disbanded — items returned to shelves)
  customerRefusal,    // Відмова клієнта
  pharmacyRefusal,    // Відмова аптеки
}

enum OrderType {
  tabletkiUA,
  glovo,
  novaPoshta,
}

class OrderItem {
  final String sku;
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
    required this.name,
    this.manufacturer,
    required this.quantity,
    this.fraction,
    required this.price,
    required this.total,
    this.expiryDate,
    this.refusalReason,
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

  /// Marked by external service — urgent orders (Glovo, locker deadline, etc.)
  final bool isUrgent;

  /// Whether this order can be placed into a locker (parameter from service).
  /// Locker-eligible orders are automatically urgent.
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
    this.isUrgent = false,
    this.isLockerEligible = false,
    this.refusalReason,
  });

  String get statusLabel {
    switch (status) {
      case OrderStatus.newOrder:
        return 'Нове';
      case OrderStatus.inProgress:
        return 'В обробці';
      case OrderStatus.collected:
        return 'Зібране';
      case OrderStatus.dispensed:
        return 'Видане';
      case OrderStatus.refused:
        return 'Розформоване';
      case OrderStatus.customerRefusal:
        return 'Відмова клієнта';
      case OrderStatus.pharmacyRefusal:
        return 'Відмова аптеки';
    }
  }

  String get typeLabel {
    switch (type) {
      case OrderType.tabletkiUA:
        return 'TabletkiUA';
      case OrderType.glovo:
        return 'Glovo';
      case OrderType.novaPoshta:
        return 'Нова Пошта';
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
      isUrgent: isUrgent,
      isLockerEligible: isLockerEligible,
      refusalReason:
          clearRefusalReason ? null : (refusalReason ?? this.refusalReason),
    );
  }
}
