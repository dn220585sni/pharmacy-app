import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'fiscal_log.dart';

/// Читання `sklad.ini` — конфігу роздрібного модуля.
///
/// Потрібен нам поки що заради одного значення: `[Sklad] → LocalOut`, теки,
/// куди роздріб складає PDF чеків (Андрій Попов, 04.09.2026). На тестовій
/// касі це `v:\out`.
///
/// Файл лежить у робочому каталозі неймспейсу Caché
/// (`<CacheSys>\Mgr\<NSpace>\sklad.ini`), а шляху до нього немає ні в
/// `HKCU\Software\ZSMU\Farm`, ні в реєстрі InterSystems. Тому пробуємо
/// невеликий перелік очевидних місць — це кілька перевірок існування файлу,
/// а не обхід диска.
class SkladIni {
  /// Куди дивитись. Порядок має значення: перший знайдений виграє.
  @visibleForTesting
  static List<String> candidates({String nameSpace = 'User'}) => [
        for (final drive in const ['D', 'C', 'E', 'F', 'V', 'G'])
          '$drive:\\CacheSys\\Mgr\\$nameSpace\\sklad.ini',
      ];

  /// Підміна шляху в тестах.
  @visibleForTesting
  static String? pathOverride;

  static String? _cachedPath;
  static String? _cachedLocalOut;
  static bool _looked = false;

  @visibleForTesting
  static void resetCache() {
    _cachedPath = null;
    _cachedLocalOut = null;
    _looked = false;
  }

  /// Значення ключа з секції. Регістр не має значення ні для секції, ні для
  /// ключа; рядки, закоментовані `;` або `#`, ігноруються.
  ///
  /// У живому файлі поруч зі значеннями лежать їхні ж закоментовані версії
  /// (`;Hook=1`, `;Graph=e:\sertif\...`), тож пропускати коментарі —
  /// обовʼязково, інакше можна взяти вимкнене значення.
  @visibleForTesting
  static String? value(String content, String section, String key) {
    final wantSection = section.toLowerCase();
    final wantKey = key.toLowerCase();
    var inSection = false;
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) {
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        inSection =
            line.substring(1, line.length - 1).trim().toLowerCase() ==
                wantSection;
        continue;
      }
      if (!inSection) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      if (line.substring(0, eq).trim().toLowerCase() != wantKey) continue;
      final v = line.substring(eq + 1).trim();
      return v.isEmpty ? null : v;
    }
    return null;
  }

  /// Тека `LocalOut` або `null`, якщо `sklad.ini` не знайдено чи ключа немає.
  ///
  /// Результат кешується: файл не змінюється під час зміни, а шукати його на
  /// кожному чеку — марна робота.
  static Future<String?> localOut({String nameSpace = 'User'}) async {
    if (_looked) return _cachedLocalOut;
    _looked = true;
    if (kIsWeb) return null;

    final paths = pathOverride != null ? [pathOverride!] : candidates(
        nameSpace: nameSpace);
    for (final p in paths) {
      try {
        final f = File(p);
        if (!await f.exists()) continue;
        _cachedPath = p;
        // ⚠️ Файл НЕ в UTF-8. 07.09 читання падало з
        // «Failed to decode data using encoding 'utf-8'», і ми мовчки писали
        // чеки в ProgramData замість LocalOut. Кирилиця там у cp1251, але нам
        // потрібні лише ключі й шляхи — вони ASCII, тож latin1 їх передає
        // байт у байт і, головне, НІКОЛИ не кидає виняток. Кириличні коментарі
        // перетворяться на мотлох, і це нормально: ми їх не читаємо.
        _cachedLocalOut = value(
            latin1.decode(await f.readAsBytes(), allowInvalid: true),
            'Sklad',
            'LocalOut');
        FiscalLog.log('sklad.ini: $p → LocalOut='
            '${_cachedLocalOut ?? "(ключа немає)"}');
        return _cachedLocalOut;
      } catch (e) {
        FiscalLog.log('sklad.ini: $p не прочитано: $e');
      }
    }
    FiscalLog.log('sklad.ini не знайдено (шукали: ${paths.join(", ")})');
    return null;
  }

  /// Де саме знайшли файл — для діагностики.
  static String? get foundAt => _cachedPath;
}
