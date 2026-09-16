import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/utils/drug_name_case.dart';

void main() {
  group('humanizeDrugName', () {
    test('серверний капс → перше слово з великої, решта малими', () {
      expect(humanizeDrugName('ЦИТРАМОН ЕКСТРА ТАБЛ. №10'),
          'Цитрамон екстра табл. №10');
    });

    test('маркери мережі лишаються капсом', () {
      expect(humanizeDrugName('ЦИТРАМОН-В ТАБЛ. №10 УВТМ'),
          'Цитрамон-в табл. №10 УВТМ');
      expect(humanizeDrugName('ВАЛІДОЛ ТАБЛ. №100 ВТМ 2342 2335'),
          'Валідол табл. №100 ВТМ 2342 2335');
    });

    test('дозування з літерами йде в нижній регістр', () {
      expect(humanizeDrugName('НУРОФЕН Д/ДІТЕЙ ФОРТЕ СУСП. 200МГ/5МЛ 100МЛ'),
          'Нурофен д/дітей форте сусп. 200мг/5мл 100мл');
    });

    test('латинська абревіатура лишається', () {
      expect(humanizeDrugName('ПАНАДОЛ ТАБЛ. №12 GSK'), 'Панадол табл. №12 GSK');
    });

    test('назва не капсом — без змін', () {
      expect(humanizeDrugName('Цитрамон Екстра таблетки №10'),
          'Цитрамон Екстра таблетки №10');
      expect(humanizeDrugName(''), '');
    });

    test('назва, що починається з цифри чи лапок', () {
      expect(humanizeDrugName('"АСКОРУТИН" ТАБЛ. №50'), '"Аскорутин" табл. №50');
      expect(humanizeDrugName('5-НОК ТАБЛ. №50'), '5-Нок табл. №50');
    });
  });
}
