import 'package:flutter/foundation.dart';

import '../models/internet_order.dart';
import '../models/order_extras.dart';
import 'fiscal_log.dart';

/// Додаткові ознаки інтернет-замовлень — **МОК** (ТЗ Юлії від 21.09.2026).
///
/// Сервісів Каті для переписки з кол-центром, автопідтвердження, прапорця
/// часу на збір, номера Glovo й коду видачі ще немає. Щоб UI можна було
/// показати й протестувати, ознаки роздаються ДЕТЕРМІНОВАНО за id замовлення
/// (одне й те саме замовлення завжди має ті самі ознаки), а надіслані
/// повідомлення живуть у памʼяті до закриття програми.
///
/// Інтеграція: замінити тіла методів на виклики Caché; сигнатури, модель
/// [OrderExtras] і весь UI лишаються. Поки [isMock] == true, UI підписує
/// такі дані словом «демо», щоб тестувальник не сприйняв їх за справжні.
class OrderExtrasService {
  static const bool isMock = true;

  /// Роздавати вигадані ознаки (повідомлення, передоплата, Glovo №, код
  /// видачі…) за хешем номера. Вимкнено 25.09 (Микола): Катя робить сервіс
  /// повідомлень, а «демо»-переписка й ознаки вводили в оману. Поки
  /// `false` — усі замовлення без ознак; те, що надіслали в сесії, живе в
  /// пам'яті, як і раніше. Тести вмикають назад через [demoData].
  static bool demoData = false;

  /// Вихідне повідомлення від аптеки дозволене лише для замовлень на суму
  /// понад цю (обмеження передачі персональних даних Tabletki.ua, ТЗ §5).
  static const double outgoingMinTotal = 1000;

  static final Map<String, OrderExtras> _store = {};

  /// Стабільний хеш (String.hashCode між запусками не гарантований).
  static int _hash(String s) {
    var h = 7;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x3fffffff;
    }
    return h;
  }

  /// Ознаки для списку замовлень. Уже відомі (зі змінами сесії) не
  /// перезаписуються.
  static Future<Map<String, OrderExtras>> fetchExtras(
      List<InternetOrder> orders) async {
    for (final o in orders) {
      _store.putIfAbsent(
          o.id, () => demoData ? _mockFor(o) : OrderExtras.empty);
    }
    return {for (final o in orders) o.id: _store[o.id]!};
  }

  static OrderExtras of(String orderId) => _store[orderId] ?? OrderExtras.empty;

  static OrderExtras _mockFor(InternetOrder o) {
    final h = _hash(o.id.isEmpty ? o.reserveNumber : o.id);
    final isNew = o.status == OrderStatus.newOrder;
    final autoConfirm = h % 7 == 3;
    final sla = !isNew || autoConfirm
        ? OrderSla.none
        : switch (h % 4) { 1 => OrderSla.expiring, 2 => OrderSla.overdue, _ => OrderSla.none };

    final messages = <OrderMessage>[];
    var unread = false;
    if (h % 5 == 0) {
      final t = o.dateTime.add(const Duration(minutes: 25));
      messages.add(OrderMessage(
        fromPharmacy: false,
        author: 'Кол-центр',
        text: 'Клієнт просить уточнити наявність і термін придатності '
            'по замовленню №${o.reserveNumber}.',
        time: t,
      ));
      if (h % 10 == 0) {
        unread = true;
      } else {
        messages.add(OrderMessage(
          fromPharmacy: true,
          author: 'Аптека',
          text: 'Усе в наявності, термін придатності понад рік. Збираємо.',
          time: t.add(const Duration(minutes: 7)),
        ));
      }
    }

    final isGlovo = o.type == OrderType.glovo;
    final isInsurance = o.type == OrderType.likTas;
    final prepaid = !isGlovo &&
        !isInsurance &&
        (o.type == OrderType.ancSite ||
            o.type == OrderType.iosApp ||
            o.type == OrderType.androidApp) &&
        h % 3 == 0;
    final collected = o.status == OrderStatus.collected;

    return OrderExtras(
      autoConfirm: autoConfirm,
      sla: sla,
      messages: messages,
      hasUnread: unread,
      glovoNumber: isGlovo ? 'GL${100000 + h % 900000}' : null,
      prepaid: prepaid,
      franchisePercent: isInsurance ? const [0, 10, 20, 30][h % 4] : null,
      collectedBy: collected ? 'Карпенко О.' : null,
      collectedAt: collected ? o.dateTime.add(const Duration(minutes: 40)) : null,
      promoCode: h % 9 == 0 ? 'ANC${h % 1000}' : null,
    );
  }

  /// Чи діє тривога часу на збір: знімається після взяття в роботу, зміни
  /// статусу на «Зібране» або відмови; автопідтверджені не тривожать (ТЗ §6).
  static OrderSla slaFor(InternetOrder o, OrderExtras e) {
    if (e.autoConfirm) return OrderSla.none;
    if (o.status != OrderStatus.newOrder) return OrderSla.none;
    return e.sla;
  }

  /// Чи може аптека написати першою / відповісти по цьому замовленню.
  static bool canSend(InternetOrder o) => o.total > outgoingMinTotal;

  /// Надіслати повідомлення кол-центру.
  static Future<OrderExtras> sendMessage(
      InternetOrder order, String text, String author) async {
    final cur = of(order.id);
    final next = cur.copyWith(
      messages: [
        ...cur.messages,
        OrderMessage(
          fromPharmacy: true,
          author: author.isEmpty ? 'Аптека' : author,
          text: text,
          time: DateTime.now(),
        ),
      ],
      hasUnread: false,
    );
    _store[order.id] = next;
    FiscalLog.log('ІЗ №${order.reserveNumber}: повідомлення кол-центру '
        '(${text.length} симв.)${isMock ? ' [демо, нікуди не надіслано]' : ''}');
    return next;
  }

  /// Позначити вхідні прочитаними (відкрили переписку).
  static OrderExtras markRead(String orderId) {
    final cur = of(orderId);
    if (!cur.hasUnread) return cur;
    final next = cur.copyWith(hasUnread: false);
    _store[orderId] = next;
    return next;
  }

  // ── Код видачі передоплаченого замовлення (ТЗ §10) ────────────────────────

  /// Демо-код = останні 4 цифри номера замовлення.
  static String _mockIssueCode(InternetOrder o) {
    final digits = o.reserveNumber.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 4 ? digits.substring(digits.length - 4) : '0000';
  }

  static Future<bool> verifyIssueCode(InternetOrder order, String code) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final ok = code.trim() == _mockIssueCode(order);
    FiscalLog.log('ІЗ №${order.reserveNumber}: перевірка коду видачі → '
        '${ok ? 'OK' : 'невірний'}${isMock ? ' [демо]' : ''}');
    return ok;
  }

  static Future<void> resendIssueSms(InternetOrder order) async {
    await Future.delayed(const Duration(milliseconds: 250));
    FiscalLog.log('ІЗ №${order.reserveNumber}: SMS повтор коду видачі'
        '${isMock ? ' [демо, SMS не надіслано]' : ''}');
    debugPrint('resendIssueSms mock: ${order.reserveNumber}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Сигнал для кнопки «Інтернет-замовлення» на бічній панелі головного екрана.
// ─────────────────────────────────────────────────────────────────────────────

class OrdersAlertState {
  /// Скільки замовлень потребують реакції фармацевта — ті, що підняті вгору
  /// «Не оплачених»: Glovo, Лікомат, Нова пошта (ще не зібрані) і з новими
  /// повідомленнями.
  final int count;

  /// Є замовлення з вичерпаним часом — значок миготить.
  final bool pulse;

  /// Є непрочитане повідомлення — лічильник кожні 3 с на 1 с змінюється
  /// синім конвертом.
  final bool hasUnread;

  const OrdersAlertState(
      {this.count = 0, this.pulse = false, this.hasUnread = false});

  // Публікуємо на кожне оновлення списку — рівність, щоб кнопка не
  // перебудовувалась без змін.
  @override
  bool operator ==(Object other) =>
      other is OrdersAlertState &&
      other.count == count &&
      other.pulse == pulse &&
      other.hasUnread == hasUnread;

  @override
  int get hashCode => Object.hash(count, pulse, hasUnread);
}

class OrdersAlerts {
  static final ValueNotifier<OrdersAlertState> state =
      ValueNotifier(const OrdersAlertState());
}
