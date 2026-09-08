import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/prro_service.dart';
import 'package:pharmacy_app/services/receipt_outbox.dart';

String _b64(String s) => base64Encode(utf8.encode(s));

PrroResult _ok({
  String? order = '12345',
  String? pdf,
  String? txt,
  String? qr,
  bool recovered = false,
}) =>
    PrroResult(
      success: true,
      orderNum: order,
      pdfBase64: pdf,
      textPrint: txt,
      qrBase64: qr,
      recovered: recovered,
    );

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('outbox_test');
    ReceiptOutbox.folderOverride = tmp;
    ReceiptOutbox.resetPruneFlag();
  });

  tearDown(() {
    ReceiptOutbox.folderOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  List<String> names() => tmp
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .toList()
    ..sort();

  group('baseName', () {
    test('номер чека стає базовим імʼям — як у <order>_txt.pdf в Андрія', () {
      expect(ReceiptOutbox.baseName(_ok(order: '12345')), '12345');
    });

    test('небезпечні символи прибираються, шлях не втече з теки', () {
      expect(ReceiptOutbox.baseName(_ok(order: r'..\..\evil')), 'evil');
      expect(ReceiptOutbox.baseName(_ok(order: 'A-1_2/3')), 'A-1_23');
    });

    test('без номера — не порожнє імʼя', () {
      expect(ReceiptOutbox.baseName(_ok(order: null)), 'check');
      expect(ReceiptOutbox.baseName(_ok(order: '   ')), 'check');
    });
  });

  group('save', () {
    test('розкладає pdf, txt і png під одним іменем', () async {
      final written = await ReceiptOutbox.save(_ok(
        pdf: _b64('%PDF-fake'),
        txt: _b64('ФІСКАЛЬНИЙ ЧЕК'),
        qr: _b64('PNGfake'),
      ));
      expect(written, hasLength(3));
      expect(names(), ['12345.pdf', '12345.png', '12345.txt']);
    });

    test('декодує base64, а не пише його як текст', () async {
      await ReceiptOutbox.save(_ok(txt: _b64('ФІСКАЛЬНИЙ ЧЕК')));
      final f = File('${tmp.path}${Platform.pathSeparator}12345.txt');
      expect(utf8.decode(f.readAsBytesSync()), 'ФІСКАЛЬНИЙ ЧЕК');
    });

    test('відновлений чек (A1) без pdf і qr — не помилка, просто нічого', () async {
      final written = await ReceiptOutbox.save(_ok(recovered: true));
      expect(written, isEmpty);
      expect(names(), isEmpty);
    });

    test('порожні рядки не створюють файлів-пустушок', () async {
      final written = await ReceiptOutbox.save(_ok(pdf: '', txt: '   ', qr: null));
      expect(written, isEmpty);
    });

    test('невдалий чек не викладається взагалі', () async {
      final written = await ReceiptOutbox.save(const PrroResult.failure(
        error: 'таймаут',
        errorKind: PrroErrorKind.connection,
      ));
      expect(written, isEmpty);
    });

    test('той самий номер перезаписує, а не множить файли', () async {
      await ReceiptOutbox.save(_ok(txt: _b64('перший')));
      await ReceiptOutbox.save(_ok(txt: _b64('другий')));
      expect(names(), ['12345.txt', '12345_txt.pdf']);
      final f = File('${tmp.path}${Platform.pathSeparator}12345.txt');
      expect(utf8.decode(f.readAsBytesSync()), 'другий');
    });

    test('із text_print складається ще й <order>_txt.pdf', () async {
      // Єдиний із чотирьох файлів, який ми рендеримо самі, а не отримуємо
      // готовим від ПРРО.
      await ReceiptOutbox.save(_ok(txt: _b64('ФIСКАЛЬНИЙ ЧЕК\nТОВАР 100.00')));
      final pdf = File('${tmp.path}${Platform.pathSeparator}12345_txt.pdf');
      expect(pdf.existsSync(), isTrue);
      expect(String.fromCharCodes(pdf.readAsBytesSync().take(5)), '%PDF-');
    });

    test('без text_print і QR складати нічого', () async {
      await ReceiptOutbox.save(_ok(pdf: _b64('%PDF-від-ПРРО')));
      expect(names(), ['12345.pdf']);
    });
  });

  group('prune', () {
    File touch(String name, Duration age) {
      final f = File('${tmp.path}${Platform.pathSeparator}$name')
        ..writeAsStringSync('x');
      f.setLastModifiedSync(DateTime.now().subtract(age));
      return f;
    }

    test('прибирає старше за 7 днів, свіже лишає', () async {
      touch('900000001.pdf', const Duration(days: 8));
      touch('900000002.pdf', const Duration(days: 7, hours: 1));
      touch('900000003.pdf', const Duration(days: 6, hours: 23));
      touch('900000004.pdf', Duration.zero);

      final removed = await ReceiptOutbox.prune();

      expect(removed, 2);
      expect(names(), ['900000003.pdf', '900000004.pdf']);
    });

    test('рівно 7 днів ще лишається — межа не рубає зайвого', () async {
      touch('900000005.pdf',
          const Duration(days: 7) - const Duration(minutes: 1));
      expect(await ReceiptOutbox.prune(), 0);
      expect(names(), ['900000005.pdf']);
    });

    test('порожня тека — нуль, без винятку', () async {
      expect(await ReceiptOutbox.prune(), 0);
    });

    test('ЧУЖІ файли не чіпаємо, хоч би які старі', () async {
      // LocalOut — спільна тека роздрібу. На тестовій касі поруч із чеками
      // лежали вивантаження AllWorkCash і звіт віком у пʼять місяців; чистка
      // «все, старше за 7 днів» винесла б їх усі.
      touch('01.09.26_ОООАптека-Магнолия_AllWorkCash_1.xls',
          const Duration(days: 200));
      touch('15042026_Звіт приоритетні фарм заміни.xlsx',
          const Duration(days: 150));
      touch('.~lock.15042026_Звіт.xlsx#', const Duration(days: 150));
      touch('logInvoice_06012021.log', const Duration(days: 2000));
      // А наш чек — прибираємо.
      touch('2900664544.pdf', const Duration(days: 30));

      expect(await ReceiptOutbox.prune(), 1);
      expect(names(), [
        '.~lock.15042026_Звіт.xlsx#',
        '01.09.26_ОООАптека-Магнолия_AllWorkCash_1.xls',
        '15042026_Звіт приоритетні фарм заміни.xlsx',
        'logInvoice_06012021.log',
      ]);
    });

    test('прибираємо лише наші розширення', () async {
      touch('2900664544.pdf', const Duration(days: 30));
      touch('2900664544.txt', const Duration(days: 30));
      touch('2900664544.png', const Duration(days: 30));
      touch('2900664544_txt.pdf', const Duration(days: 30));
      // Той самий номер, але чуже розширення — не наше.
      touch('2900664544.xls', const Duration(days: 30));

      expect(await ReceiptOutbox.prune(), 4);
      expect(names(), ['2900664544.xls']);
    });

    test('перший save прибирає старе, наступні вже не ходять по теці', () async {
      touch('900000010.pdf', const Duration(days: 30));
      await ReceiptOutbox.save(_ok(order: '800000001', txt: _b64('перший')));
      expect(names(), ['800000001.txt', '800000001_txt.pdf']);

      touch('900000011.pdf', const Duration(days: 30));
      await ReceiptOutbox.save(_ok(order: '800000002', txt: _b64('другий')));
      expect(names(), [
        '800000001.txt',
        '800000001_txt.pdf',
        '800000002.txt',
        '800000002_txt.pdf',
        '900000011.pdf',
      ]);
    });
  });
}
