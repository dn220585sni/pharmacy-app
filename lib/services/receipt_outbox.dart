import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'fiscal_log.dart';
import 'prro_service.dart';

/// Тека `out` — те, що можна віддати на друк.
///
/// Складається з готового, що вже прийшло від ПРРО у відповіді на `/check/sale`:
/// `<order>.pdf` (`pdf`), `<order>.txt` (`text_print`) і `<order>.png`
/// (`qr` — ПРРО віддає QR готовим зображенням, ми його не малюємо).
/// Складений `<order>_txt.pdf` двома кеглями зʼявиться окремо: він потребує
/// рендера, `monofont` і `koef_scale`.
///
/// Живе поряд із журналом, у `%ProgramData%\pharmacy_app\out` — спільна тека,
/// а не профіль користувача: чек має лишитись доступним, навіть якщо його
/// друкує вже інша зміна. Термін зберігання — 7 днів (Андрій, 03.09.2026).
///
/// Усе best-effort: збій запису не має валити продаж, який уже
/// зафіскалізовано.
class ReceiptOutbox {
  static const _folderName = 'out';

  /// Скільки тримаємо файли. Андрій Попов, 03.09.2026.
  static const keep = Duration(days: 7);

  /// Підміна теки в тестах.
  @visibleForTesting
  static Directory? folderOverride;

  /// Чистимо раз на запуск: за зміну це сотні чеків, а прибирати щоразу —
  /// зайвий обхід каталогу на кожному продажу.
  static bool _pruned = false;

  @visibleForTesting
  static void resetPruneFlag() => _pruned = false;

  static Future<Directory?> _folder() async {
    if (folderOverride != null) return folderOverride;
    if (kIsWeb) return null;
    try {
      final programData = Platform.environment['ProgramData'];
      final base = (programData != null && programData.isNotEmpty)
          ? Directory('$programData${Platform.pathSeparator}pharmacy_app')
          : await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}$_folderName');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (e) {
      FiscalLog.log('out: не вдалося відкрити теку: $e');
      return null;
    }
  }

  /// Базове імʼя файлів чека — номер, як його називає Андрій (`<order>_txt.pdf`).
  ///
  /// Той самий номер = той самий чек, тож перезапис безпечний.
  static String baseName(PrroResult r) {
    final raw = (r.orderNum ?? '').trim();
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return safe.isEmpty ? 'check' : safe;
  }

  /// Викласти чек у `out`. Повертає шляхи записаних файлів.
  ///
  /// Порожні або відсутні частини просто пропускаємо: відновлений чек (A1)
  /// приходить без PDF і QR — це не помилка.
  static Future<List<String>> save(PrroResult result) async {
    if (!result.success) return const [];
    final dir = await _folder();
    if (dir == null) return const [];

    final base = baseName(result);
    final written = <String>[];

    Future<void> put(String ext, String? b64) async {
      if (b64 == null || b64.trim().isEmpty) return;
      try {
        final bytes = base64Decode(b64.trim());
        final f = File('${dir.path}${Platform.pathSeparator}$base.$ext');
        await f.writeAsBytes(bytes, flush: true);
        written.add(f.path);
      } catch (e) {
        FiscalLog.log('out: $base.$ext не записано: $e');
      }
    }

    await put('pdf', result.pdfBase64);
    await put('txt', result.textPrint);
    await put('png', result.qrBase64);

    if (written.isEmpty) {
      FiscalLog.log('out: чек $base — нічого викладати '
          '(pdf/text_print/qr порожні${result.recovered ? ", відновлений" : ""})');
    } else {
      FiscalLog.log('out: чек $base — ${written.length} файл(и) у ${dir.path}');
    }

    if (!_pruned) {
      _pruned = true;
      await prune();
    }
    return written;
  }

  /// Прибрати все, старше за [keep]. Помилка на одному файлі не спиняє решту:
  /// файл може бути відкритий у переглядачі саме зараз.
  static Future<int> prune({DateTime? now}) async {
    final dir = await _folder();
    if (dir == null) return 0;
    final cutoff = (now ?? DateTime.now()).subtract(keep);
    var removed = 0;
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        try {
          if ((await e.lastModified()).isBefore(cutoff)) {
            await e.delete();
            removed++;
          }
        } catch (_) {
          // Зайнятий або вже зник — наступного запуску прибереться.
        }
      }
    } catch (e) {
      FiscalLog.log('out: обхід теки не вдався: $e');
      return removed;
    }
    if (removed > 0) FiscalLog.log('out: прибрано $removed файл(ів) старше 7 днів');
    return removed;
  }
}
