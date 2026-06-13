import 'package:flutter/foundation.dart';
import '../models/stop_price_action.dart';
import 'cache_api_client.dart';

/// Кеш активних акцій на товари (per ukod) — для відображення фармацевту
/// причини зміни ціни в кошику.
///
/// Eager-стратегія: коли товар з'являється у кошику, `pos_screen` викликає
/// [prefetch] для всіх ukod-ів. Сервіс кешує результат у пам'яті назавжди
/// (на час сесії додатку — на старті порожній).
class StopPriceService {
  static final Map<String, List<StopPriceAction>> _cache = {};
  static final Map<String, Future<List<StopPriceAction>>> _inFlight = {};

  /// Отримати з кешу. `null` якщо ще не завантажено.
  static List<StopPriceAction>? get(String ukod) => _cache[ukod];

  /// Безумовна акційна ціна на сам товар при роздрібній [retail] — для показу
  /// в таблиці пошуку. Враховує базові правила `r:-XX%` (відсоток) та `r:-XX`
  /// (грн), бере найнижчу. `null` якщо безумовної знижки немає, акція умовна
  /// (драбина від 2 уп) чи це крос-сейл (`adddisk` → ТПК), або акції ще не в кеші.
  static double? promoPrice(String ukod, double retail) {
    final acts = _cache[ukod];
    if (acts == null || acts.isEmpty || retail <= 0) return null;
    var best = retail;
    for (final a in acts) {
      final p = a.unconditionalPromoPrice(retail);
      if (p != null && p < best) best = p;
    }
    if (best >= retail) return null;
    return (best * 100).round() / 100;
  }

  /// Отримати акції — з кешу, інакше fetch.
  static Future<List<StopPriceAction>> fetchActions(String ukod) async {
    if (ukod.isEmpty) return const [];
    final cached = _cache[ukod];
    if (cached != null) return cached;
    final inFlight = _inFlight[ukod];
    if (inFlight != null) return inFlight;

    final future = _doFetch(ukod);
    _inFlight[ukod] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(ukod);
    }
  }

  static Future<List<StopPriceAction>> _doFetch(String ukod) async {
    try {
      final r = await CacheApiClient()
          .call('GetStopPriceUKod', params: {'ukod': ukod});
      if (!r.isOk) {
        debugPrint('GetStopPriceUKod FAIL ukod=$ukod: ${r.result}');
        return _cache[ukod] = const [];
      }
      final raw = r.data['Actions'];
      final actions = raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(StopPriceAction.fromJson)
              .toList(growable: false)
          : const <StopPriceAction>[];
      debugPrint('GetStopPriceUKod ukod=$ukod: ${actions.length} actions');
      return _cache[ukod] = actions;
    } catch (e) {
      debugPrint('GetStopPriceUKod ERROR ukod=$ukod: $e');
      return _cache[ukod] = const [];
    }
  }

  /// Eager prefetch для batch ukod-ів. Обробляє з обмеженою паралельністю
  /// (батчами по [concurrency]), щоб префетч топ-500 не вистрілив сотнями
  /// одночасних HTTP-запитів. [onBatch] викликається після кожного батча —
  /// для прогресивного оновлення UI (таблиця показує акційні ціни по мірі
  /// надходження). Future завершується коли всі fetch-и закінчаться.
  static Future<void> prefetch(
    Iterable<String> ukods, {
    int concurrency = 8,
    void Function()? onBatch,
  }) async {
    final unique = ukods.where((u) => u.isNotEmpty).toSet();
    final missing = unique
        .where((u) => !_cache.containsKey(u) && !_inFlight.containsKey(u))
        .toList(growable: false);
    if (missing.isEmpty) return;
    for (var i = 0; i < missing.length; i += concurrency) {
      final batch = missing.skip(i).take(concurrency);
      await Future.wait(batch.map(fetchActions));
      onBatch?.call();
    }
  }

  static void clearCache() {
    _cache.clear();
  }
}
