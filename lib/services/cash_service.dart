import 'package:flutter/foundation.dart';
import '../models/cash_operation.dart';
import '../models/money.dart';
import 'api_config.dart';
import 'cache_api_client.dart';
import 'fiscal_log.dart';

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
      FiscalLog.log('GetOperKassa(${direction.param}) FAIL: ${r.result}');
    } catch (e) {
      debugPrint('CashService getReasons ERROR: $e');
      FiscalLog.log('GetOperKassa(${direction.param}) ERROR: $e');
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
      // Слід у release-журналі обов'язковий: 01.09 Катерина повідомила, що
      // операції вносів-виносів перестали з'являтися в базі, а перевірити це
      // з нашого боку було НІЧИМ — результат жив лише в debugPrint.
      FiscalLog.log('SaveSumDay(${direction.param}, "$reason", '
          '${sum.format()}, ekkKodKli=${ApiConfig.ekkKodKli}): '
          '${r.isOk ? "OK" : "FAIL"} result="${r.result}"');
      if (r.isOk) {
        debugPrint(
            'CashService: ${direction.param} "$reason" ${sum.format()} OK');
        return true;
      }
      debugPrint('CashService saveOperation FAIL: ${r.result}');
    } catch (e) {
      debugPrint('CashService saveOperation ERROR: $e');
      FiscalLog.log('SaveSumDay(${direction.param}, "$reason", '
          '${sum.format()}) ERROR: $e');
    }
    return false;
  }
}
