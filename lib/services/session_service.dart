import 'package:flutter/foundation.dart';
import 'api_config.dart';
import 'cache_api_client.dart';

/// Готові дані для фіскального чека з `GetDataRRO` — сирий проброс у
/// CashDesk `/check/sale` без парсингу в типізовані моделі (нечутливо до
/// `pay_terminal`/`uktzed`/нових полів).
class RroData {
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> payments;
  const RroData({required this.products, required this.payments});
}

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

  /// Отримати готові products/payments для ПРРО-чека за номером накладної
  /// (`GetDataRRO`, Задача 30). Caché проставляє tax_prc/letters/cost/sum_discount
  /// і вже округлену payments.sum. Повертає `null` при помилці/порожньому —
  /// викликач падає на клієнтську збірку (fallback).
  static Future<RroData?> getDataRRO(String numNakl) async {
    if (ApiConfig.useMock || numNakl.isEmpty) return null;
    try {
      final r = await CacheApiClient().call('GetDataRRO', params: {
        'NumNakl': numNakl,
      });
      if (!r.isOk) {
        debugPrint('SessionService GetDataRRO FAIL: ${r.result}');
        return null;
      }
      final products = _mapList(r.data['products']);
      final payments = _mapList(r.data['payments']);
      if (products.isEmpty || payments.isEmpty) {
        debugPrint('SessionService GetDataRRO: порожні products/payments');
        return null;
      }
      return RroData(products: products, payments: payments);
    } catch (e) {
      debugPrint('SessionService GetDataRRO ERROR: $e');
      return null;
    }
  }

  static List<Map<String, dynamic>> _mapList(dynamic v) => v is List
      ? v.whereType<Map<String, dynamic>>().toList()
      : const [];

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
