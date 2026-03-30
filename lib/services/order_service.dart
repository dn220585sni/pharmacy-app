import 'package:flutter/foundation.dart';
import '../models/internet_order.dart';
import 'api_config.dart';
import 'cache_api_client.dart';

/// Сервіс інтернет-замовлень — працює з GetOrders API Caché.
class OrderService {
  static final _api = CacheApiClient();

  /// Завантажити замовлення за період та статусом.
  ///
  /// [status] — "all", "new", "apteka make", "apteka pay", тощо.
  /// [dateFrom], [dateTo] — формат "dd.MM.yyyy".
  static Future<List<InternetOrder>> fetchOrders({
    String status = 'all',
    String? dateFrom,
    String? dateTo,
  }) async {
    if (ApiConfig.useMock) return [];

    final now = DateTime.now();
    final today =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    final response = await _api.call('GetOrders', params: {
      'status': status,
      'dateFrom': dateFrom ?? today,
      'dateTo': dateTo ?? today,
    });

    if (!response.isOk) {
      debugPrint('GetOrders error: ${response.result}');
      return [];
    }

    final ordersJson = response.data['Orders'] as List<dynamic>?;
    if (ordersJson == null) return [];

    return ordersJson
        .map((e) => InternetOrder.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
