import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Файловий журнал фіскальних операцій (audit B4, мінімум): видимість у
/// release-збірці, де debugPrint нема куди читати. Append-only `fiscal_log.txt`
/// у support-директорії застосунку (%APPDATA%\...\pharmacy_app).
class FiscalLog {
  static File? _file;
  static bool _initTried = false;

  static Future<File?> _target() async {
    if (_file != null || _initTried) return _file;
    _initTried = true;
    if (kIsWeb) return null;
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
