import 'package:flutter/foundation.dart';
import 'api_config.dart';
import 'cache_api_client.dart';

/// Сервіси серверного сеансу обслуговування (накладна).
///   NewClient — повний reset сеансу/кошика (після продажу / при відмові);
///   IdentSPL  — зберегти клієнта ЛАЙК у сеансі (для накладної).
/// Усі fire-and-forget; помилки логуються, продаж не блокують.
class SessionService {
  /// Скинути серверний сеанс: видалити накопичені дані + очистити серверний кошик.
  static Future<bool> newClient() async {
    if (ApiConfig.useMock) return true;
    try {
      final r = await CacheApiClient().call('NewClient');
      if (r.isOk) {
        debugPrint('SessionService: NewClient OK');
        return true;
      }
      debugPrint('SessionService NewClient FAIL: ${r.result}');
    } catch (e) {
      debugPrint('SessionService NewClient ERROR: $e');
    }
    return false;
  }

  /// Ідентифікація клієнта ЛАЙК для накладної.
  /// Онлайн: [phone] + [card] зі Sparta. Офлайн (card відсутній): SpartaCard=SpartaPhone.
  static Future<bool> identSPL({required String phone, String? card}) async {
    if (ApiConfig.useMock || phone.isEmpty) return false;
    try {
      final r = await CacheApiClient().call('IdentSPL', params: {
        'SpartaPhone': phone,
        'SpartaCard': (card != null && card.isNotEmpty) ? card : phone,
      });
      if (r.isOk) {
        debugPrint('SessionService: IdentSPL OK');
        return true;
      }
      debugPrint('SessionService IdentSPL FAIL: ${r.result}');
    } catch (e) {
      debugPrint('SessionService IdentSPL ERROR: $e');
    }
    return false;
  }
}
