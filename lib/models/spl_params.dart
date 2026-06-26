import 'package:flutter/foundation.dart';

/// Параметри ЛАЙК/Спарта для аптеки (`GetSPLParam`, Задача 26).
///
/// Caché віддає per-аптека креди й налаштування Спарти (та інших підсистем —
/// тут лишаємо лише Sparta-поля). Прод-креди для підпису й проведення
/// транзакції беруться звідси, а не хардкодяться.
@immutable
class SplParams {
  /// Секрет підпису (1.6.3). Поле `posKey`.
  final String posKey;

  /// Код аптеки в Спарті (юр.особа×1000 + склад). Поле `placeCode`.
  final String placeCode;

  /// API-токен. Поле `EdApiTokenSPL`.
  final String apiToken;

  /// База URL Спарти. Поле `EdUrlSPL`.
  final String baseUrl;

  /// Резервні URL (на випадок недоступності основного). Поле `EdUrlSPLSubstitution`.
  final List<String> fallbackUrls;

  /// IP для пінг-перевірки звʼязку. Поле `EdUrlSPLHost`.
  final List<String> hostIps;

  /// Скільки пінгів для перевірки звʼязку. Поле `EdSPLCountPing`.
  final int pingCount;

  /// Таймаут запиту, с. Поле `EdSPLTimeOut`.
  final int timeoutSeconds;

  /// Чи дозволене списання бонусів. Поле `chkSPLSpisBonus` ("1").
  final bool allowBonusSpend;

  /// Режим NGD (обовʼязковий для повного функціоналу). Поле `chkSPLNGD` ("1").
  final bool ngdMode;

  /// Префікси карток ЛАЙК. Поле `EdSPLPrefix` (напр. "99,77,88,ANC").
  final List<String> cardPrefixes;

  /// GlobID аптеки. Поле `GlobId`. Використовується для `orderNo`.
  final String globId;

  const SplParams({
    required this.posKey,
    required this.placeCode,
    required this.apiToken,
    required this.baseUrl,
    required this.fallbackUrls,
    required this.hostIps,
    required this.pingCount,
    required this.timeoutSeconds,
    required this.allowBonusSpend,
    required this.ngdMode,
    required this.cardPrefixes,
    required this.globId,
  });

  /// Унікальний номер ІЗ для Спарти: `GlobId + no` (номер чека в Компасі).
  /// Напр. GlobId=129, no=2900635968 → "1292900635968".
  String orderNoFor(String no) => '$globId$no';

  static List<String> _csv(dynamic v) =>
      (v?.toString() ?? '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

  static int _int(dynamic v, int fallback) =>
      int.tryParse(v?.toString().trim() ?? '') ?? fallback;

  static bool _flag(dynamic v) => v?.toString().trim() == '1';

  factory SplParams.fromJson(Map<String, dynamic> j) => SplParams(
        posKey: j['posKey']?.toString() ?? '',
        placeCode: j['placeCode']?.toString() ?? '',
        apiToken: j['EdApiTokenSPL']?.toString() ?? '',
        baseUrl: j['EdUrlSPL']?.toString() ?? '',
        fallbackUrls: _csv(j['EdUrlSPLSubstitution']),
        hostIps: _csv(j['EdUrlSPLHost']),
        pingCount: _int(j['EdSPLCountPing'], 0),
        timeoutSeconds: _int(j['EdSPLTimeOut'], 5),
        allowBonusSpend: _flag(j['chkSPLSpisBonus']),
        ngdMode: _flag(j['chkSPLNGD']),
        cardPrefixes: _csv(j['EdSPLPrefix']),
        globId: j['GlobId']?.toString() ?? '',
      );

  /// Чи достатньо даних для роботи зі Спартою (підпис + проведення).
  bool get isUsable =>
      posKey.isNotEmpty &&
      placeCode.isNotEmpty &&
      apiToken.isNotEmpty &&
      baseUrl.isNotEmpty;

  @override
  String toString() =>
      'SplParams(placeCode=$placeCode, globId=$globId, baseUrl=$baseUrl, '
      'ngd=$ngdMode, spisBonus=$allowBonusSpend, posKey=${posKey.isNotEmpty ? "***" : ""})';
}
