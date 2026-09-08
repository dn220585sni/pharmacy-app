import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import 'fiscal_log.dart';
import 'prro_service.dart';
import 'receipt_pdf.dart';

/// Друк чеків і звітів.
///
/// Правила від Андрія Попова (03–04.09.2026):
///   • принтер обирається за `PRRO_index_printer` — це **порядковий номер у
///     списку принтерів Windows**, не назва. Ключ знадобився, коли зʼявились
///     аптеки, де сервер аптеки й касове місце на одному компʼютері;
///   • Z-звіт друкується завжди;
///   • X-звіт і чек на перегляд відкриваються застосунком Windows,
///     асоційованим із розширенням PDF.
class ReceiptPrinter {
  /// Список принтерів у порядку, який дає Windows. Порядок і є адресацією:
  /// `PRRO_index_printer` — індекс у ньому.
  static Future<List<Printer>> printers() async {
    if (kIsWeb) return const [];
    try {
      return await Printing.listPrinters();
    } catch (e) {
      FiscalLog.log('друк: список принтерів недоступний: $e');
      return const [];
    }
  }

  /// Принтер за індексом із реєстру.
  ///
  /// `null` — індекс поза межами списку. Це не дрібниця: індекс зсувається,
  /// щойно в системі додали чи прибрали принтер, тож мовчки друкувати «на
  /// той, що є» не можна — чек піде не туди.
  @visibleForTesting
  static Printer? pickByIndex(List<Printer> list, int index) {
    if (index < 0 || index >= list.length) return null;
    return list[index];
  }

  /// Надрукувати готовий PDF. Повертає `true`, якщо документ пішов на принтер.
  static Future<bool> printPdf(Uint8List pdf, {String name = 'Чек'}) async {
    if (kIsWeb) return false;
    final index = PrroConfig.printerIndex;
    final list = await printers();
    if (list.isEmpty) {
      FiscalLog.log('друк "$name": принтерів у системі не знайдено');
      return false;
    }
    final printer = pickByIndex(list, index);
    if (printer == null) {
      FiscalLog.log('друк "$name": PRRO_index_printer=$index поза межами '
          'списку з ${list.length} принтерів — '
          '${list.map((p) => p.name).join(", ")}');
      return false;
    }
    try {
      final ok = await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => pdf,
        name: name,
      );
      FiscalLog.log('друк "$name" на "${printer.name}" (індекс $index): '
          '${ok ? "OK" : "ВІДМОВА"}');
      return ok;
    } catch (e) {
      FiscalLog.log('друк "$name" на "${printer.name}" ПОМИЛКА: $e');
      return false;
    }
  }

  /// Взяти PDF звіту: готовий від ПРРО, а якщо його немає — зібрати з тексту.
  ///
  /// ПРРО повертає `pdf` для Z і X, і саме його краще друкувати: там уже його
  /// власна верстка. Рендер із `text_print` — запасний шлях на випадок, коли
  /// PDF не прийшов (буває при `no_pdf` або обриві).
  @visibleForTesting
  static Future<Uint8List?> resolvePdf({
    String? pdfBase64,
    String? textPrint,
  }) async {
    if (pdfBase64 != null && pdfBase64.trim().isNotEmpty) {
      try {
        return base64Decode(pdfBase64.trim());
      } catch (e) {
        FiscalLog.log('звіт: PDF від ПРРО не розібрано ($e) — рендеримо самі');
      }
    }
    if (textPrint == null || textPrint.trim().isEmpty) return null;
    try {
      final text = utf8.decode(base64Decode(textPrint.trim()),
          allowMalformed: true);
      return ReceiptPdf.build(text: text);
    } catch (e) {
      FiscalLog.log('звіт: текст не розібрано: $e');
      return null;
    }
  }

  /// Z-звіт — **друкуємо завжди** (Андрій, 03.09). Це не рішення правила:
  /// звіт про закриття зміни має лишитись на папері незалежно від того, як
  /// клієнти отримують свої чеки.
  static Future<bool> printZReport(PrroResult z) async {
    final pdf = await resolvePdf(
        pdfBase64: z.pdfBase64, textPrint: z.textPrint);
    if (pdf == null) {
      FiscalLog.log('Z-звіт: друкувати нема чого — ПРРО не дав ні pdf, '
          'ні text_print');
      return false;
    }
    return printPdf(pdf, name: 'Z-звіт');
  }

  /// X-звіт — **на перегляд**, не на друк (Андрій, 03.09). Кладемо у тимчасову
  /// теку, а не в `out`: там живуть чеки роздрібу з чистилкою за іменами, і
  /// класти туди сторонній файл — напрошуватись на проблеми.
  static Future<bool> previewXReport(PrroXReport x) async {
    final pdf =
        await resolvePdf(pdfBase64: x.pdfBase64, textPrint: x.textPrint);
    if (pdf == null) {
      FiscalLog.log('X-звіт: показувати нема чого — ПРРО не дав ні pdf, '
          'ні text_print');
      return false;
    }
    try {
      final dir = Directory(
          '${Directory.systemTemp.path}${Platform.pathSeparator}pharmacy_app');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}${Platform.pathSeparator}x_report_$ts.pdf';
      await File(path).writeAsBytes(pdf, flush: true);
      return openPdf(path);
    } catch (e) {
      FiscalLog.log('X-звіт: не вдалося зберегти для перегляду: $e');
      return false;
    }
  }

  /// Показати PDF фармацевту — застосунком Windows за асоціацією.
  ///
  /// Так відкривається X-звіт і чек із теки `out`. Свого переглядача не
  /// робимо свідомо: Андрій прямо описав саме цю поведінку, і роздріб
  /// поводиться так само, тож фармацевт бачить звичне вікно.
  static Future<bool> openPdf(String path) async {
    if (kIsWeb) return false;
    if (!await File(path).exists()) {
      FiscalLog.log('перегляд PDF: файла немає — $path');
      return false;
    }
    try {
      // `start` — вбудована команда оболонки, тож потрібен саме cmd.
      // Порожній рядок після неї — це заголовок вікна: без нього cmd прийме
      // шлях у лапках за заголовок і нічого не відкриє.
      final r = await Process.run('cmd', ['/c', 'start', '', path]);
      final ok = r.exitCode == 0;
      FiscalLog.log('перегляд PDF: $path ${ok ? "відкрито" : "ПОМИЛКА "
          "(код ${r.exitCode}) ${r.stderr}"}');
      return ok;
    } catch (e) {
      FiscalLog.log('перегляд PDF: $path ПОМИЛКА: $e');
      return false;
    }
  }
}
