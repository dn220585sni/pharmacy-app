import 'package:flutter/foundation.dart';
import 'api_config.dart';
import 'cache_api_client.dart';
import 'fiscal_log.dart';

/// Готові дані для фіскального чека з `GetDataRRO` — сирий проброс у
/// CashDesk `/check/sale` без парсингу в типізовані моделі (нечутливо до
/// `pay_terminal`/`uktzed`/нових полів).
class RroData {
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> payments;
  const RroData({required this.products, required this.payments});
}

/// Готові масиви для Sparta `tx/order` з `GetDataSPL` — сирий проброс у
/// `SpartaService.order()`.
class SplData {
  final List<Map<String, dynamic>> basket;
  final List<Map<String, dynamic>> mops;
  final List<Map<String, dynamic>> params;
  final List<Map<String, dynamic>> coupons;
  const SplData({
    required this.basket,
    required this.mops,
    required this.params,
    this.coupons = const [],
  });
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
        if (numNakl == null || numNakl.isEmpty) {
          FiscalLog.log('SavesgVNakl OK але NumNakl порожній: '
              'ключі=${r.data.keys.join(",")}');
        }
        return numNakl;
      }
      FiscalLog.log('SavesgVNakl FAIL (KodKli=$kodKli TypeNakl=$typeNakl): '
          '${r.result}');
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
        FiscalLog.log('GetDataRRO FAIL nakl=$numNakl: ${r.result}');
        return null;
      }
      final products = _mapList(r.data['products']);
      final payments = _mapList(r.data['payments']);
      if (products.isEmpty || payments.isEmpty) {
        FiscalLog.log('GetDataRRO nakl=$numNakl порожні: '
            'products=${products.length} payments=${payments.length} '
            'ключі=${r.data.keys.join(",")}');
        return null;
      }
      return RroData(products: products, payments: payments);
    } catch (e) {
      FiscalLog.log('GetDataRRO ERROR nakl=$numNakl: $e');
      return null;
    }
  }

  /// Готовий Sparta-кошик для `tx/order` (`GetDataSPL`, Задача 28) за номером
  /// накладної. basket/mops/params (coupons — якщо є). null при помилці/порожньому.
  static Future<SplData?> getDataSPL(String numNakl) async {
    if (ApiConfig.useMock || numNakl.isEmpty) return null;
    try {
      final r = await CacheApiClient().call('GetDataSPL', params: {
        'NumNakl': numNakl,
      });
      if (!r.isOk) {
        FiscalLog.log('GetDataSPL FAIL nakl=$numNakl: ${r.result}');
        return null;
      }
      final basket = _mapList(r.data['basket']);
      final mops = _mapList(r.data['mops']);
      if (basket.isEmpty || mops.isEmpty) {
        FiscalLog.log('GetDataSPL nakl=$numNakl порожні: '
            'basket=${basket.length} mops=${mops.length} '
            'ключі=${r.data.keys.join(",")}');
        return null;
      }
      return SplData(
        basket: basket,
        mops: mops,
        params: _mapList(r.data['params']),
        coupons: _mapList(r.data['coupons']),
      );
    } catch (e) {
      FiscalLog.log('GetDataSPL ERROR nakl=$numNakl: $e');
      return null;
    }
  }

  /// Зафіксувати статус транзакції ЛАЙК у сеансі (`PutKasaSPL`, Задача 29).
  /// [prSPL]: «-1» проміжне (після order pending), «1» успішна (після
  /// orderStatusChange D), «2» офлайн. [prId] — id транзакції зі Sparta order.
  /// Best-effort: збій НЕ скасовує вже проведене.
  static Future<bool> putKasaSPL(
      String numNakl, String prSPL, String prId) async {
    if (ApiConfig.useMock || numNakl.isEmpty) return false;
    try {
      final r = await CacheApiClient().call('PutKasaSPL', params: {
        'NumNakl': numNakl,
        'PrSPL': prSPL,
        'PrId': prId,
      });
      if (r.isOk) return true;
      FiscalLog.log('PutKasaSPL FAIL nakl=$numNakl PrSPL=$prSPL: ${r.result}');
    } catch (e) {
      FiscalLog.log('PutKasaSPL ERROR nakl=$numNakl: $e');
    }
    return false;
  }

  /// Зафіксувати чек ПРРО в накладній (`PutKasa`, Задача 31 = пост-фіскалізація
  /// A3) після успіху `/check/sale`. [fiscN] — ORDERNUM, [urlN] — link чека,
  /// [flPend] — прапорець pending/offline. Best-effort.
  static Future<bool> putKasa(
      String numNakl, String fiscN, String flPend, String urlN) async {
    if (ApiConfig.useMock || numNakl.isEmpty) return false;
    try {
      final r = await CacheApiClient().call('PutKasa', params: {
        'NumNakl': numNakl,
        'fiscN': fiscN,
        'flPend': flPend,
        'urlN': urlN,
      });
      if (!r.isOk) {
        FiscalLog.log('PutKasa FAIL nakl=$numNakl fiscN=$fiscN: ${r.result}');
      }
      return r.isOk;
    } catch (e) {
      FiscalLog.log('PutKasa ERROR nakl=$numNakl: $e');
    }
    return false;
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
