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
///   • QR: `koef_scale` масштабує полотно растра, тобто роздільність. Розмір
///     на папері беремо від ширини стрічки — узяті в PDF-пунктах числа опису
///     давали QR на дві третини аркуша (видно на живому чеку 08.09).
///
/// ⚠️ Дослівні числа опису (кеглі 5/8, полотно 350) — з іншої системи
/// координат, не з PDF-пунктів. Зберігаємо їхні СПІВВІДНОШЕННЯ, а розміри
/// рахуємо від ширини стрічки.
class ReceiptPdf {

  /// Кеглі за описом Андрія.
  ///
  /// ⚠️ Взяті дослівно, вони не працюють: на першому живому чеку (08.09)
  /// кегль 5 у пунктах PDF дав текст на ~третину ширини стрічки 80 мм, а
  /// решта лишилась порожньою. Числа Андрія — з ЙОГО системи координат, не з
  /// PDF-пунктів. Тому зберігаємо їх СПІВВІДНОШЕННЯ (8/5 = 1.6×), а сам
  /// розмір рахуємо від ширини стрічки — див. [fontSizeFor].
  static const fontSmall = 5.0;
  static const fontLarge = 8.0;

  /// У скільки разів блок лояльності більший за основний текст.
  static const largeRatio = fontLarge / fontSmall;

  /// Кегль, за якого [chars] символів заповнять [widthPt] пунктів.
  ///
  /// Множник 0.6 — типове відношення ширини гліфа до кегля для моноширинних
  /// і напівширокі цифри Arial. Точність тут не критична: важливо, щоб чек
  /// заповнював стрічку, а не тулився в кутку.
  ///
  /// Ширину беремо з `print_width`, бо саме стільки символів у рядку віддає
  /// ПРРО (на тестовій касі — 32).
  @visibleForTesting
  static double fontSizeFor(double widthPt, int chars) {
    if (chars <= 0) return fontSmall;
    final size = widthPt / (chars * 0.6);
    // Межі здорового глузду: нижче 4 не читається, вище 14 чек рветься.
    return size.clamp(4.0, 14.0);
  }

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
  static const _loyaltyRoot = 'ЛОЯЛЬНОСТ';

  /// Прибрати те, для чого у шрифті немає гліфів.
  ///
  /// ПРРО віддає текст із `CRLF`. Ділили ми по `\n`, а `\r` лишався в кінці
  /// кожного рядка — і Arial малював його чорним прямокутником «немає гліфа».
  /// На першому ж живому чеку (08.09) такий квадрат стояв у кінці КОЖНОГО
  /// рядка. Заразом прибираємо решту керівних символів, окрім самого переносу.
  @visibleForTesting
  static String stripControl(String text) =>
      text.replaceAll(RegExp(r'[\x00-\x09\x0B-\x1F\x7F]'), '');

  @visibleForTesting
  static (String head, String tail) splitAtLoyalty(String text) {
    final lines = stripControl(text).split('\n');
    final at = lines.indexWhere(
        (l) => l.toUpperCase().contains(_loyaltyRoot));
    if (at < 0) return (stripControl(text), '');
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
    final (head, tail) = splitAtLoyalty(text);

    const margin = 4.0;
    final usableWidth = PdfPageFormat.roll80.width - margin * 2;

    // Кегль — від ширини стрічки, а не з константи: див. [fontSizeFor].
    final small = fontSizeFor(usableWidth, PrroConfig.printWidth);
    final large = small * largeRatio;

    // QR: `koef_scale` збільшує ПОЛОТНО растра (Андрій, 04.09), тобто впливає
    // на роздільність, а не на розмір на папері. Фізичний бік беремо від
    // ширини стрічки — і обмежуємо нею. Без цього виходило 612 пунктів
    // (≈216 мм, формат A4) на 80-міліметровому чеку: QR займав дві третини
    // аркуша, що й було видно на першому живому чеку.
    final side = (usableWidth * (0.5 + scale * 0.2)).clamp(40.0, usableWidth);

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
        margin: const pw.EdgeInsets.all(margin),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (head.isNotEmpty) pw.Text(head, style: style(small)),
            if (tail.isNotEmpty) pw.Text(tail, style: style(large)),
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
