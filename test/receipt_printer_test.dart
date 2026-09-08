import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:pharmacy_app/services/receipt_printer.dart';

Printer _p(String name) => Printer(url: name, name: name);

void main() {
  group('pickByIndex', () {
    final list = [_p('Microsoft Print to PDF'), _p('XP-80C'), _p('OneNote')];

    test('індекс адресує позицію в списку Windows', () {
      // PRRO_index_printer — саме порядковий номер, не назва (Андрій, 04.09).
      // У реєстрі тестової каси там 0.
      expect(ReceiptPrinter.pickByIndex(list, 0)?.name,
          'Microsoft Print to PDF');
      expect(ReceiptPrinter.pickByIndex(list, 1)?.name, 'XP-80C');
      expect(ReceiptPrinter.pickByIndex(list, 2)?.name, 'OneNote');
    });

    test('індекс поза межами — null, а не «перший-ліпший»', () {
      // Індекс зсувається, щойно принтер додали чи прибрали. Мовчазний
      // фолбек означав би чек, надрукований не на тому пристрої.
      expect(ReceiptPrinter.pickByIndex(list, 3), isNull);
      expect(ReceiptPrinter.pickByIndex(list, 99), isNull);
      expect(ReceiptPrinter.pickByIndex(list, -1), isNull);
    });

    test('порожній список — null за будь-якого індексу', () {
      expect(ReceiptPrinter.pickByIndex(const [], 0), isNull);
    });
  });
}
