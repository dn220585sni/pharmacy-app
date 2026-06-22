import 'package:flutter/foundation.dart';
import '../models/cash_operation.dart';
import '../models/money.dart';
import 'api_config.dart';
import 'cache_api_client.dart';

/// Службові операції каси: внесення / винесення.
///   GetOperKassa(NameWorkRRO) → список причин;
///   SaveSumDay(NameWorkRRO, Reason, Sum, ekkKodKli) → зберегти операцію.
/// Службове внесення на старті зміни = cashIn + «Служебное внесение».
class CashService {
  /// Перелік причин для напряму [direction] (для випадайки).
  static Future<List<CashReason>> getReasons(CashDirection direction) async {
    try {
      final r = await CacheApiClient().call(
        'GetOperKassa',
        params: {'NameWorkRRO': direction.param},
      );
      if (r.isOk) return parseCashReasons(r.data);
      debugPrint('CashService getReasons FAIL: ${r.result}');
    } catch (e) {
      debugPrint('CashService getReasons ERROR: $e');
    }
    return const [];
  }

  /// Зберегти операцію внесення/винесення. `true` — успіх.
  static Future<bool> saveOperation({
    required CashDirection direction,
    required String reason,
    required Money sum,
  }) async {
    try {
      final r = await CacheApiClient().call(
        'SaveSumDay',
        params: {
          'NameWorkRRO': direction.param,
          'Reason': reason,
          'Sum': sum.toApiString(),
          'ekkKodKli': ApiConfig.ekkKodKli,
        },
      );
      if (r.isOk) {
        debugPrint(
            'CashService: ${direction.param} "$reason" ${sum.format()} OK');
        return true;
      }
      debugPrint('CashService saveOperation FAIL: ${r.result}');
    } catch (e) {
      debugPrint('CashService saveOperation ERROR: $e');
    }
    return false;
  }
}
