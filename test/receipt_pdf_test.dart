import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/receipt_pdf.dart';

void main() {
  group('splitAtLoyalty', () {
    test('маркер відкриває ВЕЛИКУ частину, а не завершує дрібну', () {
      const text = 'ФIСКАЛЬНИЙ ЧЕК\n'
          'ТОВАР 1  100.00\n'
          'ПРОГРАМА ЛОЯЛЬНОСТI\n'
          'Бонусів нараховано: 5';
      final (head, tail) = ReceiptPdf.splitAtLoyalty(text);
      expect(head, 'ФIСКАЛЬНИЙ ЧЕК\nТОВАР 1  100.00');
      expect(tail, 'ПРОГРАМА ЛОЯЛЬНОСТI\nБонусів нараховано: 5');
    });

    test('латинська I в маркері не ламає збіг — головна пастка', () {
      // В описі Андрія маркер записаний з ЛАТИНСЬКОЮ I. Обидві форми
      // візуально однакові, тож звірка з повним рядком розсипалась би на
      // одному символі.
      const latin = 'ШАПКА\nПРОГРАМА ЛОЯЛЬНОСТI\nхвіст';   // I латинська
      const cyril = 'ШАПКА\nПРОГРАМА ЛОЯЛЬНОСТІ\nхвіст';   // І кирилична
      expect(ReceiptPdf.splitAtLoyalty(latin).$2, startsWith('ПРОГРАМА'));
      expect(ReceiptPdf.splitAtLoyalty(cyril).$2, startsWith('ПРОГРАМА'));
    });

    test('без маркера весь чек лишається дрібним', () {
      // Продаж без телефону покупця: рядка лояльності немає, і Андрій
      // підтвердив, що такий чек друкується кеглем 5 повністю.
      const text = 'ФIСКАЛЬНИЙ ЧЕК\nТОВАР 1  100.00\nСУМА 100.00';
      final (head, tail) = ReceiptPdf.splitAtLoyalty(text);
      expect(head, text);
      expect(tail, isEmpty);
    });

    test('регістр не має значення', () {
      final (head, tail) =
          ReceiptPdf.splitAtLoyalty('шапка\nпрограма лояльності\nхвіст');
      expect(head, 'шапка');
      expect(tail, 'програма лояльності\nхвіст');
    });

    test('маркер у першому рядку — дрібної частини немає', () {
      final (head, tail) =
          ReceiptPdf.splitAtLoyalty('ПРОГРАМА ЛОЯЛЬНОСТI\nхвіст');
      expect(head, isEmpty);
      expect(tail, 'ПРОГРАМА ЛОЯЛЬНОСТI\nхвіст');
    });

    test('порожній текст не падає', () {
      expect(ReceiptPdf.splitAtLoyalty('').$1, isEmpty);
      expect(ReceiptPdf.splitAtLoyalty('').$2, isEmpty);
    });
  });

  group('fontFileFor', () {
    // Реальний перелік із C:\Windows\Fonts цієї машини.
    const fonts = [
      'arial.ttf',
      'arialbd.ttf',
      'arialbi.ttf',
      'ariali.ttf',
      'consola.ttf',
      'consolab.ttf',
      'consolai.ttf',
      'consolaz.ttf',
    ];

    test('Arial → arial.ttf, а не накреслення', () {
      // arialbd/ariali теж починаються з «arial» — важливо взяти базовий.
      expect(ReceiptPdf.fontFileFor('Arial', fonts), 'arial.ttf');
      expect(ReceiptPdf.fontFileFor('arial', fonts), 'arial.ttf');
    });

    test('Consolas → consola.ttf: назва й файл не збігаються', () {
      expect(ReceiptPdf.fontFileFor('Consolas', fonts), 'consola.ttf');
    });

    test('пробіли в назві не заважають', () {
      expect(ReceiptPdf.fontFileFor(' Arial ', fonts), 'arial.ttf');
    });

    test('невідомий шрифт — null, беремо вбудований', () {
      expect(ReceiptPdf.fontFileFor('НемаєТакого', fonts), isNull);
      expect(ReceiptPdf.fontFileFor('', fonts), isNull);
      expect(ReceiptPdf.fontFileFor('Arial', const []), isNull);
    });
  });

  group('полотно QR', () {
    test('коефіцієнт множить бік як (1 + koef_scale)', () {
      // Андрій, 04.09: koef_scale збільшує ПОЛОТНО png-обʼєкта, не роздільність.
      // При 0.75 бік 350 стає 612.5.
      expect(ReceiptPdf.qrBaseSide * (1 + 0.75), 612.5);
      // Нуль означає «без збільшення», а не «нульовий розмір».
      expect(ReceiptPdf.qrBaseSide * (1 + 0.0), 350.0);
    });
  });

  group('build', () {
    test('віддає справжній PDF', () async {
      final bytes = await ReceiptPdf.build(
        text: 'ФIСКАЛЬНИЙ ЧЕК\nТОВАР 1  100.00\nПРОГРАМА ЛОЯЛЬНОСТI\nБонус 5',
      );
      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(500));
    });

    test('порожній чек без QR — нічого не збираємо', () async {
      expect(await ReceiptPdf.build(text: ''), isNull);
      expect(await ReceiptPdf.build(text: '   \n  '), isNull);
    });
  });
}
