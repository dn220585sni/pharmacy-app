import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/drug_service.dart';
import 'package:pharmacy_app/services/product_browser_service.dart';

void main() {
  group('Код СЦ з відповіді GetSKUdetail (поле ids)', () {
    test('число без «*» — код СЦ', () {
      expect(kodScFromIds('5511'), '5511');
      expect(kodScFromIds(' 1072035 '), '1072035');
      expect(kodScFromIds(25379), '25379');
    });

    test('ukod (з «*»), порожньо, не число — null', () {
      expect(kodScFromIds('5511*3*14'), isNull);
      expect(kodScFromIds('762*1*47*6****'), isNull);
      expect(kodScFromIds(''), isNull);
      expect(kodScFromIds(null), isNull);
      expect(kodScFromIds('abc'), isNull);
    });

    test('fromJson кладе ids у kodSc і в skuCode', () {
      final d = SKUDetailResult.fromJson({
        'ids': '5511',
        'ukod': '762*1*47*6****',
        'name': 'ЦИТРАМОН-Д №6',
      });
      expect(d.kodSc, '5511');
      expect(d.skuCode, '5511');
      final u = SKUDetailResult.fromJson({'ids': '5511*3*14'});
      expect(u.kodSc, isNull);
    });
  });

  group('pickByKodSc — лише рядок з тим самим id', () {
    ProductSearchResult r(String id, String name) => ProductSearchResult(
          id: id,
          link: 'slug-$id',
          name: name,
          price: 0,
        );

    test('знаходить свій id серед чужих', () {
      final hit = ProductBrowserService.pickByKodSc('5511', [
        r('46324', 'Солпадеїн Актив таблетки шипучі стрип №12'),
        r('5511', 'Цитрамон-Дарниця таблетки №6'),
      ]);
      expect(hit?.link, 'slug-5511');
    });

    test('немає збігу за id — null, а не перший рядок', () {
      final hit = ProductBrowserService.pickByKodSc('6077', [
        r('1075617', 'ХИЛЕР HEALER ГЕЛЬ ДЛЯ РАН И ОЖОГОВ'),
      ]);
      expect(hit, isNull);
      expect(ProductBrowserService.pickByKodSc('1', const []), isNull);
    });
  });
}
