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

  /// Зберегти накладну перед фіскалізацією (SaveSgVNakl). Повертає `NumNakl`
  /// (внутрішній номер накладної) або `null` при помилці.
  /// [kodKli]: готівка → код каси (ekkKodKli); картка → код банку (kodterm).
  /// [typeNakl]: готівка='2', картка='5'.
  static Future<String?> saveNakladna({
    required String kodKli,
    required String typeNakl,
  }) async {
    if (ApiConfig.useMock) return null;
    try {
      final r = await CacheApiClient().call('SavesgVNakl', params: {
        'orderId': '',
        'NumIzmNakl': '',
        'KodKli': kodKli,
        'TypeNakl': typeNakl,
      });
      if (r.isOk) {
        final numNakl = r.data['NumNakl']?.toString();
        debugPrint('SessionService: SaveSgVNakl NumNakl=$numNakl');
        return numNakl;
      }
      debugPrint('SessionService SaveSgVNakl FAIL: ${r.result}');
    } catch (e) {
      debugPrint('SessionService SaveSgVNakl ERROR: $e');
    }
    return null;
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
