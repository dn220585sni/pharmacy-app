import 'api_config.dart';
import 'cache_api_client.dart';
import 'fiscal_log.dart';

/// Глобальні параметри аптеки (`GetGlobParam`, Катя 13.10): чи є робот
/// (`exRobot`) і лікомат (`exLikomat`). Вантажимо після входу; результат —
/// у [ApiConfig.hasRobot] / [ApiConfig.hasLikomat].
class GlobParamService {
  static bool _flag(dynamic v) {
    final s = v?.toString().trim().toLowerCase() ?? '';
    return s == '1' || s == 'true';
  }

  static Future<void> load() async {
    if (ApiConfig.useMock) return;
    try {
      final r = await CacheApiClient().call('GetGlobParam');
      if (!r.isOk) {
        FiscalLog.log('GetGlobParam FAIL: ${r.result} — '
            'робот=${ApiConfig.hasRobot}, лікомат=${ApiConfig.hasLikomat} (як були)');
        return;
      }
      if (r.data.containsKey('exRobot')) {
        ApiConfig.hasRobot = _flag(r.data['exRobot']);
      }
      if (r.data.containsKey('exLikomat')) {
        ApiConfig.hasLikomat = _flag(r.data['exLikomat']);
      }
      FiscalLog.log('GetGlobParam: exRobot="${r.data['exRobot']}" '
          'exLikomat="${r.data['exLikomat']}" → робот=${ApiConfig.hasRobot}, '
          'лікомат=${ApiConfig.hasLikomat}');
    } catch (e) {
      FiscalLog.log('GetGlobParam помилка: $e');
    }
  }
}
