// ─────────────────────────────────────────────────────────────────────────────
// Додаткові ознаки інтернет-замовлення, яких GetOrders ще НЕ віддає
// (ТЗ Юлії від 21.09.2026, розділи 5–8, 10): переписка з кол-центром,
// автопідтвердження, прапорець закінчення часу на збір, номер Glovo,
// передоплата з кодом видачі, атрибути збору.
//
// Зараз їх наповнює мок (`OrderExtrasService`). Коли Катя дасть сервіс —
// міняється лише джерело, модель і UI лишаються.
// ─────────────────────────────────────────────────────────────────────────────

/// Стан нормативного часу на збір замовлення (ТЗ §6).
enum OrderSla {
  /// Часу достатньо або замовлення вже взяте в роботу.
  none,

  /// Сервер передав ознаку «час спливає» — індикатор червоніє.
  expiring,

  /// Час вичерпано — індикатор миготить.
  overdue,
}

/// Одне повідомлення переписки аптека ↔ кол-центр.
class OrderMessage {
  /// true — написала аптека, false — кол-центр.
  final bool fromPharmacy;
  final String author;
  final String text;
  final DateTime time;

  const OrderMessage({
    required this.fromPharmacy,
    required this.author,
    required this.text,
    required this.time,
  });
}

class OrderExtras {
  /// Замовлення з автопідтвердженням: не вимагає термінового збору, можна
  /// зібрати при клієнтові; у тривогу SLA не потрапляє.
  final bool autoConfirm;

  /// Ознака від сервера. Чи показувати тривогу — вирішує [slaFor].
  final OrderSla sla;

  /// Переписка з кол-центром (порожня — переписки не було).
  final List<OrderMessage> messages;

  /// Є непрочитане вхідне від кол-центру.
  final bool hasUnread;

  /// Номер замовлення доставки (Glovo) — для пошуку.
  final String? glovoNumber;

  /// Оплачено онлайн (LiqPay): на місці оплата не потрібна, видача за кодом.
  final bool prepaid;

  /// Франшиза страхової, % (лише для страхових замовлень).
  final int? franchisePercent;

  /// Хто і коли зібрав замовлення.
  final String? collectedBy;
  final DateTime? collectedAt;

  /// Промокод замовлення.
  final String? promoCode;

  const OrderExtras({
    this.autoConfirm = false,
    this.sla = OrderSla.none,
    this.messages = const [],
    this.hasUnread = false,
    this.glovoNumber,
    this.prepaid = false,
    this.franchisePercent,
    this.collectedBy,
    this.collectedAt,
    this.promoCode,
  });

  static const empty = OrderExtras();

  bool get hasMessages => messages.isNotEmpty;

  OrderExtras copyWith({
    List<OrderMessage>? messages,
    bool? hasUnread,
  }) =>
      OrderExtras(
        autoConfirm: autoConfirm,
        sla: sla,
        messages: messages ?? this.messages,
        hasUnread: hasUnread ?? this.hasUnread,
        glovoNumber: glovoNumber,
        prepaid: prepaid,
        franchisePercent: franchisePercent,
        collectedBy: collectedBy,
        collectedAt: collectedAt,
        promoCode: promoCode,
      );
}
