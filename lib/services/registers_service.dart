import 'package:flutter/foundation.dart';
import '../models/cash_register.dart';
import 'api_config.dart';
import 'cache_api_client.dart';
import 'fiscal_log.dart';

/// Список кас — `GetKlient` (Задача 25).
///
/// `Kab.Service.cls?ServiceName=GetKlient&sessionId={sessionId}&prim={prim}`
/// → `{"Status":"OK","Items":[{"name":"КАССА 1, …","id":"1334"}, …]}`
///
/// Навіщо: клієнт може прийти по резерв або з поверненням не на ту касу, де
/// його обслуговували. Без списку кас панель «Витрати по касі» бачить лише
/// власні накладні — `GetNaklKas` вимагає конкретний `KodKli`.
class RegistersService {
  /// Значення `prim` за описом Катерини (04.09.2026).
  static const primAll = '';           // всі клієнти
  static const primWarehouses = 'RRO'; // каси по складах без факту закриття
  static const primPharmacy = 'RROApt'; // всі каси аптеки

  /// Каси поточної аптеки.
  ///
  /// Порожній список = або сервіс не відповів, або кас немає. Виклику
  /// достатньо знати, що вибирати нема з чого — у такому разі лишається
  /// поточна каса з реєстру.
  static Future<List<CashRegister>> pharmacyRegisters() =>
      _fetch(primPharmacy);

  static Future<List<CashRegister>> _fetch(String prim) async {
    if (ApiConfig.useMock) return const [];
    try {
      final r = await CacheApiClient().call('GetKlient', params: {'prim': prim});
      if (!r.isOk) {
        FiscalLog.log('GetKlient FAIL (prim="$prim"): ${r.result}');
        return const [];
      }
      final raw = (r.data['Items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>();
      final list = raw
          .map(CashRegister.fromJson)
          .whereType<CashRegister>()
          .toList(growable: false);
      debugPrint('GetKlient prim="$prim": ${list.length} кас');
      return list;
    } catch (e) {
      FiscalLog.log('GetKlient ERROR (prim="$prim"): $e');
      return const [];
    }
  }
}
