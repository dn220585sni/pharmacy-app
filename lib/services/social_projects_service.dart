import 'package:flutter/foundation.dart';
import '../models/social_project.dart';
import 'cache_api_client.dart';

/// Список соц-програм для аптеки. Об'єднує:
///   1) Постійно показувані локально (`_alwaysShown`) — поки не з'являться
///      на сервері. Переїдуть туди коли Карпенко/IT додасть їх в довідник.
///   2) Динамічний список з `GetSpisSocProject` — реально дозволені на цій
///      аптеці програми з серверних правил.
///
/// Кешується у пам'яті — другий і подальші виклики не б'ють API.
class SocialProjectsService {
  static List<SocialProject>? _cache;

  /// Локальні програми завжди в UI (не залежать від сервера).
  /// `tag = null` → при активації не передаємо `nameProject` у GetSumSkid
  /// (коли отримаємо реальні tag-и — переведемо в server-список).
  static const List<SocialProject> _alwaysShown = [
    SocialProject(name: 'Пакунок малюка', isLocal: true),
    SocialProject(name: 'Дарниця +', isLocal: true),
    SocialProject(name: 'Армія+', isLocal: true),
    SocialProject(name: 'єПідтримка', isLocal: true),
    SocialProject(name: 'Нацкешбек', isLocal: true),
  ];

  /// UI-overrides для server-name → коротша/звичніша назва.
  static const Map<String, String> _displayNameOverrides = {
    'Ебот кард': 'Медикард',
    'Реімбурсація': 'Доступні ліки',
    'БО Асістанс': 'Асістанс',
    'БФ Карітас': 'Карітас',
    'ГО «АЗОВ СУПРОВІД»': 'АЗОВ супровід',
    'Знижка для УБД': 'Знижка УБД',
  };

  /// Отримати об'єднаний список (always-shown + server). Кешується.
  /// На помилку сервера — повертає лише локальні.
  static Future<List<SocialProject>> fetchAvailable({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cache != null) return _cache!;

    try {
      final r = await CacheApiClient().call('GetSpisSocProject');
      if (r.isOk) {
        final raw = r.data['Projects'];
        final fromServer = raw is List
            ? raw.whereType<Map<String, dynamic>>().map((j) {
                final origName = j['name']?.toString() ?? '';
                return SocialProject(
                  name: _displayNameOverrides[origName] ?? origName,
                  tag: j['tag']?.toString(),
                );
              }).toList(growable: false)
            : const <SocialProject>[];
        debugPrint('SocialProjectsService: server=${fromServer.length} '
            'local=${_alwaysShown.length}');
        return _cache = List.unmodifiable([..._alwaysShown, ...fromServer]);
      }
      debugPrint('SocialProjectsService: server FAIL "${r.result}", '
          'local-only fallback');
    } catch (e) {
      debugPrint('SocialProjectsService ERROR: $e');
    }
    return _cache = List.unmodifiable(_alwaysShown);
  }

  /// Знайти програму за відображуваною назвою.
  static SocialProject? findByName(String? name) {
    if (name == null || _cache == null) return null;
    try {
      return _cache!.firstWhere((p) => p.name == name);
    } catch (_) {
      return null;
    }
  }

  /// Отримати tag (для `nameProject` у GetSumSkid) за UI-назвою.
  /// `null` для local або невідомої програми.
  static String? tagForName(String? name) => findByName(name)?.tag;

  static void clearCache() {
    _cache = null;
  }
}
