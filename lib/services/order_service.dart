import 'package:flutter/foundation.dart';
import '../models/internet_order.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'cache_api_client.dart';
import 'fiscal_log.dart';

/// Сервіс інтернет-замовлень — працює з GetOrders / UpdateOrderStatus API Caché.
class OrderService {
  static final _api = CacheApiClient();
  static bool _itemKeysLogged = false;

  /// Завантажити замовлення за період та статусом.
  ///
  /// Контракт 22.09.2026 (Катя переписала GetOrders під поля старого
  /// роздрібу): параметра `status` більше немає; за замовчуванням сервер
  /// віддає лише НЕЗАВЕРШЕНІ (нові / в роботі / зібрані), а оплачені й
  /// відмови — окремими прапорцями [onlyPay] / [onlyRefusal]; [onlyNotColl]
  /// — лише незібрані. [editPhone] / [editNumber] / [editGoods] — серверний
  /// пошук (телефон; номер, Glovo, ПІБ; товар).
  ///
  /// [status] лишаємо для старого контракту (сервер до 22.09 без нього
  /// віддавав лише частину) — новий його ігнорує.
  /// [dateFrom], [dateTo] — формат "dd.MM.yyyy".
  static Future<List<InternetOrder>> fetchOrders({
    String status = 'all',
    String? dateFrom,
    String? dateTo,
    bool onlyNotColl = false,
    bool onlyRefusal = false,
    bool onlyPay = false,
    bool onlyChat = false,
    String? editPhone,
    String? editNumber,
    String? editGoods,
  }) async {
    if (ApiConfig.useMock) return [];

    final now = DateTime.now();
    final today =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    final flags = [
      if (onlyNotColl) 'onlyNotColl',
      if (onlyRefusal) 'onlyRefusal',
      if (onlyPay) 'onlyPay',
      if (onlyChat) 'Chat',
    ].join(',');
    final response = await _api.call('GetOrders', params: {
      'status': status,
      'dateFrom': dateFrom ?? today,
      'dateTo': dateTo ?? today,
      if (onlyNotColl) 'onlyNotColl': '1',
      if (onlyRefusal) 'onlyRefusal': '1',
      if (onlyPay) 'onlyPay': '1',
      // Катя 25.09: Chat=1 — лише замовлення з активною перепискою.
      if (onlyChat) 'Chat': '1',
      if (editPhone != null && editPhone.isNotEmpty) 'editPhone': editPhone,
      if (editNumber != null && editNumber.isNotEmpty) 'editNumber': editNumber,
      if (editGoods != null && editGoods.isNotEmpty) 'editGoods': editGoods,
    });

    if (!response.isOk) {
      debugPrint('GetOrders error: ${response.result}');
      return [];
    }

    final ordersJson = response.data['Orders'] as List<dynamic>?;
    if (ordersJson == null) {
      FiscalLog.log('GetOrders $dateFrom–$dateTo: без масиву Orders');
      return [];
    }

    final orders = ordersJson
        .map((e) => InternetOrder.fromJson(e as Map<String, dynamic>))
        .toList();
    // Один рядок у журнал, щоб бачити реальні коди й статуси з сервера
    // (16.09 контракт: skod = s-код, ids = код СЦ, статус — текст;
    // 22.09 — поля старого роздрібу, без ids/ukod).
    final first = orders.isEmpty ? null : orders.first;
    final firstJson = ordersJson.isEmpty ? null : ordersJson.first as Map;
    final isNew = firstJson != null &&
        InternetOrder.isNewContract(firstJson.cast<String, dynamic>());
    final firstItem = first?.items.where((i) => !i.isServiceLine).firstOrNull;
    FiscalLog.log(
      'GetOrders $dateFrom–$dateTo${flags.isEmpty ? '' : ' [$flags]'}: '
      '${orders.length} замовл.'
      '${firstJson == null ? '' : ' (контракт ${isNew ? "22.09" : "16.09"})'}'
      '${first == null ? '' : '; перше №${first.reserveNumber} '
          'статус "${firstJson!['status'] ?? firstJson['Status']}" → '
          '${first.statusLabel}'
          '${first.rawType.isEmpty ? '' : ', тип "${first.rawType}" → ${first.typeLabel}'}'}'
      '${firstItem == null ? '' : ', товар s-код ${firstItem.sku} '
          'код СЦ ${firstItem.kodSc ?? '—'} ukod ${firstItem.ukod ?? '—'}'}',
    );
    // Новий контракт без коду СЦ у позиції → один раз показати сирі ключі
    // позиції: щоб бачити, як саме Катя назвала поле (24.09: «додала ids»).
    if (isNew && firstItem != null && firstItem.kodSc == null && !_itemKeysLogged) {
      _itemKeysLogged = true;
      final rawItems = (firstJson!['items'] as List?) ?? const [];
      final firstRaw = rawItems.whereType<Map>().firstWhere(
          (m) => '${m['SKod'] ?? m['skod'] ?? ''}'.isNotEmpty,
          orElse: () => const {});
      FiscalLog.log('GetOrders: позиція без коду СЦ, ключі позиції: '
          '${firstRaw.keys.join(", ")}');
    }
    // Розподіл статусів (23.09): чи віддає сервер оплачені/відмовлені взагалі.
    // Сирий текст статусу → скільки + як ми його розпізнали.
    if (orders.isNotEmpty) {
      final counts = <String, int>{};
      final labels = <String, String>{};
      for (var i = 0; i < orders.length; i++) {
        final m = ordersJson[i] as Map;
        final raw = '${m['status'] ?? m['Status'] ?? ''}'.trim();
        counts[raw] = (counts[raw] ?? 0) + 1;
        labels[raw] = orders[i].statusLabel;
      }
      final summary = counts.entries
          .map((e) => '"${e.key}"→${labels[e.key]} ${e.value}')
          .join(', ');
      FiscalLog.log('GetOrders статуси (status=$status'
          '${flags.isEmpty ? '' : ', $flags'}): $summary');
    }
    return orders;
  }

  /// Змінити статус замовлення.
  ///
  /// Caché: `GET ?ServiceName=UpdateOrderStatus&orderId=...&newStatus=...&user=...&sessionId=...`
  /// Response: `{"Status":"OK","Result":"...","orderId":"...","newStatus":"...","updatedAt":"..."}`
  ///
  /// [orderId] — ідентифікатор замовлення
  /// [newStatus] — новий статус ("apteka make", "apteka pay", "apteka otkaz", тощо)
  /// [user] — ім'я фармацевта (напр. "Карпенко")
  static Future<CacheResponse> updateOrderStatus({
    required String orderId,
    required String newStatus,
    required String user,
  }) async {
    if (ApiConfig.useMock) {
      return CacheResponse.fromJson({
        'Status': 'OK',
        'Result': 'Статус змінено (mock)',
        'orderId': orderId,
        'newStatus': newStatus,
        'updatedAt': DateTime.now().toString(),
      });
    }

    final sessionId = AuthService.sessionId;
    if (sessionId == null) {
      return CacheResponse.error('Немає активної сесії — виконайте вхід');
    }

    final response = await _api.call('UpdateOrderStatus', params: {
      'orderId': orderId,
      'newStatus': newStatus,
      'user': '"$user"',
    });

    debugPrint(
      'UpdateOrderStatus orderId=$orderId newStatus=$newStatus → '
      '${response.isOk ? "OK" : "FAIL"}: ${response.result}',
    );

    return response;
  }
}
