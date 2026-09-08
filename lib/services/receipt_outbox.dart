import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'fiscal_log.dart';
import 'prro_service.dart';
import 'receipt_pdf.dart';
import 'sklad_ini.dart';

/// Тека `out` — те, що можна віддати на друк.
///
/// Складається з готового, що вже прийшло від ПРРО у відповіді на `/check/sale`:
/// `<order>.pdf` (`pdf`), `<order>.txt` (`text_print`) і `<order>.png`
/// (`qr` — ПРРО віддає QR готовим зображенням, ми його не малюємо).
/// Плюс `<order>_txt.pdf` — наш складений текстовий чек двома кеглями
/// (`ReceiptPdf`): єдиний із чотирьох, який ми рендеримо самі.
///
/// **Тека — не наша.** Андрій уточнив 04.09.2026: шлях читається з
/// `sklad.ini`, ключ `[Sklad] → LocalOut` (на тестовій касі `v:\out`), а імʼя
/// файлу — фіскальний номер чека, поле `ordernum` у відповіді. Туди ж пише
/// роздріб, і звідти ж він відкриває чек фармацевту на перегляд; якщо файлу
/// вже немає (минуло понад 7 календарних днів), роздріб тягне чек з
/// особистого кабінету. Найчастіше цим користуються, щоб зʼясувати, як
/// виглядав чек по проблемній накладній у момент реєстрації в податковій.
///
/// Якщо `sklad.ini` не знайдено — падаємо на `%ProgramData%\pharmacy_app\out`,
/// щоб чеки бодай десь лишались.
///
/// Усе best-effort: збій запису не має валити продаж, який уже
/// зафіскалізовано.
class ReceiptOutbox {
  static const _folderName = 'out';

  /// Скільки тримаємо файли. Андрій Попов, 03.09.2026.
  static const keep = Duration(days: 7);

  /// Що саме нам можна прибирати.
  ///
  /// ⚠️ `LocalOut` — СПІЛЬНА тека роздрібу, і там лежить не лише наше. На
  /// тестовій касі поруч із чеками знайшлись вивантаження
  /// `01.09.26_ООО…_AllWorkCash_1.xls` і звіт `15042026_Звіт приоритетні
  /// фарм заміни….xlsx` віком у пʼять місяців. Чистка «все, старше за 7 днів»
  /// винесла б їх усі.
  ///
  /// Тому прибираємо ЛИШЕ файли, названі фіскальним номером: самі цифри плюс
  /// наше розширення. Під цей шаблон не підпадає жодне зі знайдених чужих
  /// імен.
  static final _ours =
      RegExp(r'^\d{1,20}(_txt)?\.(pdf|txt|png)$', caseSensitive: false);

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
      // Спершу — тека роздрібу зі sklad.ini: саме звідти він читає чеки.
      final localOut = await SkladIni.localOut();
      if (localOut != null && localOut.trim().isNotEmpty) {
        final dir = Directory(localOut.trim());
        if (await dir.exists()) return dir;
        FiscalLog.log('out: LocalOut="$localOut" недоступна — '
            'пишемо в ProgramData');
      }
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

  /// Знайти PDF раніше проведеного чека в теці `out`.
  ///
  /// Андрій описав саме цей сценарій (04.09): щоб подивитись, як виглядав чек
  /// по проблемній накладній у момент реєстрації в податковій, роздріб
  /// спершу шукає файл тут, а якщо його вже прибрали (понад 7 днів) — тягне
  /// з особистого кабінету.
  ///
  /// ⚠️ Проблема ідентифікатора. Файли названі ФІСКАЛЬНИМ номером
  /// (`ordernum`), а `GetNaklKas` віддає `NumNakl` — номер накладної, інше
  /// число — і `FNRRO`. Чи є `FNRRO` тим самим `ordernum`, ще не доведено,
  /// тож пробуємо обидва й пишемо в журнал, що спрацювало. Живі дані
  /// закриють це питання швидше за листування.
  ///
  /// Порядок розширень свідомий: спершу `<id>.pdf` від ПРРО (його верстка
  /// офіційна), потім наш складений `<id>_txt.pdf`.
  static Future<String?> findReceiptPdf(Iterable<String?> ids) async {
    final dir = await _folder();
    if (dir == null) return null;
    final tried = <String>[];
    for (final raw in ids) {
      final id = raw?.trim() ?? '';
      if (id.isEmpty) continue;
      for (final name in ['$id.pdf', '${id}_txt.pdf']) {
        tried.add(name);
        final f = File('${dir.path}${Platform.pathSeparator}$name');
        if (await f.exists()) {
          FiscalLog.log('out: чек знайдено — $name');
          return f.path;
        }
      }
    }
    FiscalLog.log('out: чека немає в ${dir.path} '
        '(шукали: ${tried.join(", ")}) — імовірно, минуло понад 7 днів');
    return null;
  }

  /// Зібрати `<order>_txt.pdf` із того, що прислав ПРРО.
  ///
  /// `text_print` і `qr` приходять у base64; декодуємо й віддаємо в рендер.
  /// `null` — друкувати нема чого (відновлений чек A1 приходить без обох).
  static Future<Uint8List?> buildTextPdf(PrroResult result) async {
    String? decodeText(String? b64) {
      if (b64 == null || b64.trim().isEmpty) return null;
      try {
        return utf8.decode(base64Decode(b64.trim()), allowMalformed: true);
      } catch (_) {
        return null;
      }
    }

    Uint8List? decodeBytes(String? b64) {
      if (b64 == null || b64.trim().isEmpty) return null;
      try {
        return base64Decode(b64.trim());
      } catch (_) {
        return null;
      }
    }

    final text = decodeText(result.textPrint) ?? '';
    final qr = decodeBytes(result.qrBase64);
    if (text.trim().isEmpty && qr == null) return null;
    try {
      return await ReceiptPdf.build(text: text, qrPng: qr);
    } catch (e) {
      FiscalLog.log('out: рендер _txt.pdf не вдався: $e');
      return null;
    }
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

    // `<order>_txt.pdf` — наш складений текстовий чек двома кеглями. На
    // відміну від трьох файлів вище, він не приходить готовим: ми його
    // рендеримо з `text_print` і QR.
    final txtPdf = await buildTextPdf(result);
    if (txtPdf != null) {
      try {
        final f = File('${dir.path}${Platform.pathSeparator}${base}_txt.pdf');
        await f.writeAsBytes(txtPdf, flush: true);
        written.add(f.path);
      } catch (e) {
        FiscalLog.log('out: ${base}_txt.pdf не записано: $e');
      }
    }

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
        // Чуже не чіпаємо — див. `_ours`.
        if (!_ours.hasMatch(e.uri.pathSegments.last)) continue;
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
