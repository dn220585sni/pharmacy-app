import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/product_browser_service.dart';

/// Звіряння назв для картинки товару з anc.ua.
///
/// У картці ЄДК ми брали перший результат пошуку наосліп, і на ремесулід
/// показувалось фото актовегіна (беклог Юлії). Тут перевіряємо, що чужий
/// товар більше не проходить, а свій — знаходиться попри рос./укр. написання.
void main() {
  ProductSearchResult p(String name) => ProductSearchResult(
        id: '1',
        link: 'slug',
        name: name,
        price: 10,
      );

  group('brandNameOf — торгова назва без форми випуску', () {
    test('відрізає форму й дозування', () {
      expect(
        ProductBrowserService.brandNameOf(
            'РЕМЕСУЛИД РАПИД ГРАН. 100 МГ/2 Г САШЕ 2 Г №10 УСТМ'),
        'РЕМЕСУЛИД РАПИД',
      );
      expect(
        ProductBrowserService.brandNameOf('ЦИТРАМОН-В ТАБЛ. №10 УСТМ'),
        'ЦИТРАМОН-В',
      );
    });

    test('назва без маркера форми лишається як є', () {
      expect(ProductBrowserService.brandNameOf('АКТОВЕГІН'), 'АКТОВЕГІН');
    });
  });

  group('dosageFormOf', () {
    test('впізнає форму', () {
      expect(ProductBrowserService.dosageFormOf('РЕМЕСУЛИД ГРАН. 100'),
          'гранул');
      expect(ProductBrowserService.dosageFormOf('ЦИТРАМОН ТАБЛ. №10'),
          'таблетк');
    });

    test('не впізнала — null, і тоді матчимо лише за назвою', () {
      expect(ProductBrowserService.dosageFormOf('АКТОВЕГІН'), isNull);
    });
  });

  group('pickMatch', () {
    test('ЧУЖИЙ товар не проходить — той самий баг із фото актовегіна', () {
      final match = ProductBrowserService.pickMatch(
        'РЕМЕСУЛИД РАПИД ГРАН. 100 МГ/2 Г САШЕ 2 Г №10 УСТМ',
        [p('Актовегін розчин для інєкцій'), p('Актовегін гель')],
      );
      expect(match, isNull);
    });

    test('свій товар знаходиться попри рос./укр. написання (и↔і)', () {
      final match = ProductBrowserService.pickMatch(
        'РЕМЕСУЛИД РАПИД ГРАН. 100 МГ/2 Г САШЕ 2 Г №10 УСТМ',
        [p('Актовегін гель'), p('Ремесулід рапід гранули 100 мг саше №10')],
      );
      expect(match?.name, 'Ремесулід рапід гранули 100 мг саше №10');
    });

    test('за однакової назви виграє збіг за формою випуску', () {
      final match = ProductBrowserService.pickMatch(
        'НІМЕСИЛ ГРАН. 100 МГ САШЕ №30',
        [
          p('Німесил таблетки 100 мг №20'),
          p('Німесил гранули для оральної суспензії 100 мг №30'),
        ],
      );
      expect(match?.name, 'Німесил гранули для оральної суспензії 100 мг №30');
    });

    test('порожній список — null, без падіння', () {
      expect(ProductBrowserService.pickMatch('БУДЬ-ЩО', const []), isNull);
    });
  });
}
