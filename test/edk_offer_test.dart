import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/drug.dart';
import 'package:pharmacy_app/models/edk_offer.dart';

/// ЄДК — заміна одного препарату іншим просто в кошику. Обидва правила тут про
/// гроші: донор мусить піти з кошика, а заміна — потрапити в чек.
void main() {
  Drug drug({required String id, String? ukod}) => Drug(
        id: id,
        name: 'Препарат',
        manufacturer: '',
        category: '',
        price: 100,
        stock: 5,
        unit: 'шт',
        ukod: ukod,
      );

  EdkOffer offer({required String donorDrugId, String replacementId = 'srv_5511'}) =>
      EdkOffer(
        drug: drug(id: replacementId, ukod: '762*1*47*6****'),
        donorDrugId: donorDrugId,
        description: '',
        script: '',
      );

  group('EdkOffer.isDonor', () {
    test('донор за u-кодом (звичайний товар з пошуку)', () {
      final o = offer(donorDrugId: '479*1*47*10**0,2*3*');
      expect(o.isDonor(drug(id: 'srv_9911', ukod: '479*1*47*10**0,2*3*')), isTrue);
    });

    test('донор за id — товар БЕЗ u-коду (напр. доданий сканером)', () {
      // Саме цей кейс лишав донора в кошику разом із заміною: donorDrugId
      // формується як `ukod ?? id`, а звірка була лише за ukod.
      final o = offer(donorDrugId: 'srv_9911');
      expect(o.isDonor(drug(id: 'srv_9911')), isTrue);
    });

    test('інший товар донором не вважається', () {
      final o = offer(donorDrugId: '479*1*47*10**0,2*3*');
      expect(o.isDonor(drug(id: 'srv_7777', ukod: '111*1*1*1****')), isFalse);
      expect(o.isDonor(drug(id: 'srv_7777')), isFalse);
    });

    test('заміна не є власним донором', () {
      final o = offer(donorDrugId: '479*1*47*10**0,2*3*');
      expect(o.isDonor(o.drug), isFalse);
    });
  });

  group('EdkOffer.searchQueriesFor', () {
    test('реальна назва з каси: відрізає фасування і виробника', () {
      // «ЦИТРАМОН-В №10 УСТМ» — саме за такою повною назвою SearchByNameSKU
      // повертав 0 рядків, через що заміна не резолвилась у партію.
      final q = EdkOffer.searchQueriesFor('ЦИТРАМОН-В №10 УСТМ');
      expect(q.first, 'ЦИТРАМОН-В №10 УСТМ'); // спершу точний
      expect(q, contains('ЦИТРАМОН-В'));      // потім без «№10 УСТМ»
      expect(q, contains('ЦИТРАМОН'));        // і зовсім широко
    });

    test('назва без фасування не плодить дублів', () {
      expect(EdkOffer.searchQueriesFor('НУРОФЄН'), ['НУРОФЄН']);
    });

    test('кома і дужка теж вважаються межею', () {
      expect(EdkOffer.searchQueriesFor('АСКОРБІНКА, табл (10)'),
          contains('АСКОРБІНКА'));
    });

    test('надто короткі уламки відкидаються', () {
      // Інакше пішов би запит на 1-2 літери — сервер віддав би півбази.
      final q = EdkOffer.searchQueriesFor('АБ №5');
      expect(q.every((s) => s.length >= 3), isTrue);
    });

    test('порядок від точного до широкого зберігається', () {
      final q = EdkOffer.searchQueriesFor('ПАРАЦЕТАМОЛ-ДАРНИЦЯ №10');
      expect(q.length, 3);
      expect(q[0].length > q[1].length, isTrue);
      expect(q[1].length > q[2].length, isTrue);
    });
  });

  group('EdkOffer.isSellable', () {
    test('s-код резолвнувся (srv_<skod>) → продавати можна', () {
      expect(offer(donorDrugId: 'x', replacementId: 'srv_5511').isSellable, isTrue);
    });

    test('s-код НЕ резолвнувся (edk_<ukod>) → продавати НЕ можна', () {
      // Така позиція не резервується, не потрапляє в GetSumSkid, у накладну і
      // в чек: сума кошика занижується, товар іде повз чек.
      expect(
        offer(donorDrugId: 'x', replacementId: 'edk_6077.999*1*47*10****')
            .isSellable,
        isFalse,
      );
    });
  });
}
