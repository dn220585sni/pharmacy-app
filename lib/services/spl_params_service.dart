import 'package:flutter/foundation.dart';
import '../models/spl_params.dart';
import 'api_config.dart';
import 'cache_api_client.dart';

/// Завантаження параметрів ЛАЙК/Спарта з Caché (`GetSPLParam`, Задача 26).
///
/// `GET ?ServiceName=GetSPLParam&sessionId={sessionId}` → per-аптека креди
/// (posKey/placeCode/apiToken/URL/GlobId тощо). Кешується в памʼяті на сесію;
/// при зміні фармацевта/логіні скидати через [clear].
class SplParamsService {
  static SplParams? _cache;

  /// Останній завантажений конфіг (або null, якщо ще не вантажили / помилка).
  static SplParams? get cached => _cache;

  /// Завантажити параметри Спарти. На помилку — null (Sparta-флоу не активуємо).
  static Future<SplParams?> fetch({bool forceRefresh = false}) async {
    if (ApiConfig.useMock) return null;
    if (!forceRefresh && _cache != null) return _cache;
    try {
      final r = await CacheApiClient().call('GetSPLParam');
      if (r.isOk) {
        final params = SplParams.fromJson(r.data);
        debugPrint('SplParamsService: $params');
        return _cache = params;
      }
      debugPrint('SplParamsService FAIL: ${r.result}');
    } catch (e) {
      debugPrint('SplParamsService ERROR: $e');
    }
    return null;
  }

  /// Скинути кеш (при зміні фармацевта / новій сесії).
  static void clear() => _cache = null;
}
