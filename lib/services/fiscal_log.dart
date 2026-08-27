import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Файловий журнал фіскальних операцій (audit B4, мінімум): видимість у
/// release-збірці, де debugPrint нема куди читати.
///
/// **Розташування — спільна тека `C:\ProgramData\pharmacy_app`**, а не профіль
/// користувача. Причина: на касі застосунок відкривають у кількох RDP-сесіях
/// (касир, `it`, адміністратор), а `%APPDATA%` у кожного свій — журнали
/// розповзались по чужих профілях, куди немає доступу («Permission denied»),
/// і зібрати картину дня було неможливо (2026-08-27).
///
/// **Файл на КОЖНОГО користувача** (`fiscal_log_<user>.txt`), не один спільний:
/// у ProgramData файл належить тому, хто його створив, і інший користувач
/// дописати в нього не зможе. Так усі журнали лежать поруч і читаються, але
/// кожен пише у свій.
///
/// Фолбек — стара support-тека, якщо ProgramData недоступна.
class FiscalLog {
  static File? _file;
  static bool _initTried = false;

  /// Ім'я користувача Windows для імені файлу (без символів, заборонених у
  /// шляху). Порожнє → `unknown`.
  static String get _userSuffix {
    final raw = Platform.environment['USERNAME'] ?? '';
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'unknown' : safe;
  }

  static Future<File?> _target() async {
    if (_file != null || _initTried) return _file;
    _initTried = true;
    if (kIsWeb) return null;

    // ⚠️ Під `flutter test` НЕ пишемо на диск взагалі. Раніше тести й так нічого
    // не писали (у них немає support-теки), але `ProgramData` доступна завжди —
    // і прогін тестів засмітив би БОЙОВИЙ журнал рядками на кшталт «рядок 0»
    // (спіймано одразу після переїзду, 2026-08-27).
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;

    // 1) Спільна тека — щоб журнали всіх сесій були в одному місці.
    final programData = Platform.environment['ProgramData'];
    if (programData != null && programData.isNotEmpty) {
      try {
        final dir = Directory('$programData\\pharmacy_app');
        if (!await dir.exists()) await dir.create(recursive: true);
        final f = File('${dir.path}\\fiscal_log_$_userSuffix.txt');
        // Перевіряємо саме ЗАПИС: тека може існувати, а прав на неї не бути.
        await f.writeAsString('', mode: FileMode.append, flush: true);
        _file = f;
        return _file;
      } catch (_) {
        // Немає прав / диск недоступний → фолбек нижче.
      }
    }

    // 2) Фолбек: профіль користувача (як було).
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/fiscal_log.txt');
    } catch (_) {}
    return _file;
  }

  /// Черга записів: append-и виконуються СТРОГО по черзі.
  ///
  /// ⚠️ Без цього два одночасні `writeAsString(append, flush)` б'ються за файл:
  /// на Windows один з них кидає виняток (його ковтав `catch`) або рядки
  /// перемішуються посеред тексту. Так безслідно зник рядок «A1 ДУБЛЬ
  /// ВІДСІЧЕНО», що писався одразу за діагностикою X-звіту (2026-08-26), і так
  /// само калічились давніші рядки на кшталт «віді: FormatException».
  /// Викликати можна без await — порядок і цілісність гарантує цей ланцюжок.
  static Future<void> _tail = Future<void>.value();

  /// Дописати рядок (best-effort; збій логу не впливає на продаж).
  static Future<void> log(String line) {
    debugPrint('FISCAL: $line');
    _tail = _tail.then((_) => _append(line));
    return _tail;
  }

  static Future<void> _append(String line) async {
    try {
      final f = await _target();
      if (f == null) return;
      final ts = DateTime.now().toIso8601String().substring(0, 19);
      await f.writeAsString('$ts $line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
