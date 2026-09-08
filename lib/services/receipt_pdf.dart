import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fiscal_log.dart';
import 'prro_service.dart';

/// Складання `<order>_txt.pdf` — текстового чека для друку.
///
/// Верстка за описом Андрія Попова (03–04.09.2026):
///   • кегль **5** до рядка «ПРОГРАМА ЛОЯЛЬНОСТI», далі кегль **8**;
///   • якщо телефону покупця немає, рядка лояльності теж немає — тоді весь
///     чек кеглем 5;
///   • шрифт із реєстру (`monofont`, типово Arial). Андрій: Arial обраний
///     свідомо саме для кегля 5 — читабельність важливіша за моноширинність;
///   • QR лягає на полотно 350×350, помножене на `1 + koef_scale`.
class ReceiptPdf {
  /// Базовий бік полотна QR у пунктах, до масштабування.
  static const qrBaseSide = 350.0;

  /// Кеглі за описом.
  static const fontSmall = 5.0;
  static const fontLarge = 8.0;

  /// Розділити текст чека на дві частини за рядком лояльності.
  ///
  /// Повертає `(head, tail)`: `head` друкується кеглем 5, `tail` — кеглем 8.
  /// Якщо маркера немає, `tail` порожній і весь чек лишається дрібним.
  ///
  /// Шукаємо підрядок **«ЛОЯЛЬНОСТ»**, а не повну фразу. Причина конкретна: в
  /// описі маркер записаний як «ПРОГРАМА ЛОЯЛЬНОСТI», де остання літера —
  /// латинська `I`, а не кирилична `І`. Чекові принтери часто друкують саме
  /// так, і звірка з повним рядком розсипалась би на одному символі, який
  /// візуально не відрізнити. Корінь «ЛОЯЛЬНОСТ» цієї пастки не має.
  ///
  /// Сам рядок-маркер лишається у ВЕЛИКІЙ частині: він відкриває блок
  /// лояльності, а не завершує попередній.
  @visibleForTesting
  static (String head, String tail) splitAtLoyalty(String text) {
    final lines = text.split('\n');
    final at = lines.indexWhere(
        (l) => l.toUpperCase().contains('ЛОЯЛЬНОСТ'));
    if (at < 0) return (text, '');
    return (lines.take(at).join('\n'), lines.skip(at).join('\n'));
  }

  /// Знайти файл шрифту Windows за назвою з реєстру.
  ///
  /// `monofont` містить людську назву («Arial»), а на диску лежать файли
  /// («arial.ttf»), і збіг не завжди прямий: «Consolas» → `consola.ttf`.
  /// Тому шукаємо спершу точний збіг імені файлу, потім — за початком.
  ///
  /// [dir] і [names] підмінні в тестах, щоб не залежати від машини.
  @visibleForTesting
  static String? fontFileFor(String fontName, List<String> names) {
    final want = fontName.trim().toLowerCase().replaceAll(' ', '');
    if (want.isEmpty) return null;
    String base(String f) =>
        f.toLowerCase().replaceAll('.ttf', '').replaceAll(' ', '');
    // Точний збіг — найнадійніше.
    for (final f in names) {
      if (base(f) == want) return f;
    }
    // «Consolas» → «consola». Беремо найкоротший підхожий, щоб не зачепити
    // накреслення: `arialbd`/`ariali` довші за `arial`.
    final candidates = names.where((f) => want.startsWith(base(f)) || base(f).startsWith(want)).toList()
      ..sort((a, b) => base(a).length.compareTo(base(b).length));
    return candidates.isEmpty ? null : candidates.first;
  }

  static const _fontsDir = r'C:\Windows\Fonts';

  static pw.Font? _cachedFont;
  static String? _cachedFontName;

  /// Завантажити шрифт із системної теки. `null` — не знайшли, тоді викличний
  /// код бере вбудований Helvetica (латиниця лише, але це краще за виняток).
  static Future<pw.Font?> _loadFont(String fontName) async {
    if (_cachedFontName == fontName && _cachedFont != null) return _cachedFont;
    if (kIsWeb) return null;
    try {
      final dir = Directory(_fontsDir);
      if (!await dir.exists()) return null;
      final names = await dir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.ttf'))
          .map((e) => e.uri.pathSegments.last)
          .toList();
      final file = fontFileFor(fontName, names);
      if (file == null) {
        FiscalLog.log('друк: шрифт "$fontName" не знайдено в $_fontsDir');
        return null;
      }
      final bytes = await File('$_fontsDir\\$file').readAsBytes();
      _cachedFont = pw.Font.ttf(bytes.buffer.asByteData());
      _cachedFontName = fontName;
      return _cachedFont;
    } catch (e) {
      FiscalLog.log('друк: шрифт "$fontName" не завантажено: $e');
      return null;
    }
  }

  /// Зібрати PDF чека. Повертає байти або `null`, якщо друкувати нема чого.
  ///
  /// [text] — текстове представлення чека (`text_print` від ПРРО, уже
  /// розкодоване). [qrPng] — готове зображення QR, теж від ПРРО: ми його не
  /// малюємо.
  static Future<Uint8List?> build({
    required String text,
    Uint8List? qrPng,
    String? fontName,
    double? qrScale,
  }) async {
    if (text.trim().isEmpty && qrPng == null) return null;

    final font = await _loadFont(fontName ?? PrroConfig.monoFont);
    final scale = qrScale ?? PrroConfig.qrScale;
    final side = qrBaseSide * (1 + scale);
    final (head, tail) = splitAtLoyalty(text);

    final doc = pw.Document();
    pw.TextStyle style(double size) => pw.TextStyle(
          font: font,
          fontSize: size,
          lineSpacing: 0,
        );

    doc.addPage(
      pw.Page(
        // Стрічка 80 мм — стандартна ширина чекового принтера. Висота
        // фіксована сторінкою: чек, що не влазить, краще обрізати видимо, ніж
        // мовчки згорнути.
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(4),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (head.isNotEmpty) pw.Text(head, style: style(fontSmall)),
            if (tail.isNotEmpty) pw.Text(tail, style: style(fontLarge)),
            if (qrPng != null) ...[
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.SizedBox(
                  width: side,
                  height: side,
                  child: pw.Image(pw.MemoryImage(qrPng), fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return Uint8List.fromList(await doc.save());
  }
}
