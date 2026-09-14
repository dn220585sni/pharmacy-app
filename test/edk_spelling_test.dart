import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/edk_offer.dart';

/// Назви заміни з `GetEdkOffers` приходять російською, довідник — українською.
/// Без цього фолду пошук партії давав 0 рядків, а в кошик ішла упаковка з
/// фолбек-залишком «1», яку сервер резервував лише частково (14.09.2026).
void main() {
  test('и→і дає українське написання, яке знає SearchByNameSKU', () {
    expect(EdkOffer.ukrainianSpelling('РЕМЕСУЛИД'), 'РЕМЕСУЛІД');
    expect(EdkOffer.ukrainianSpelling('РЕМЕСУЛИД РАПИД ГРАН.'),
        'РЕМЕСУЛІД РАПІД ГРАН.');
  });

  test('ы/э/ё/ъ теж переводяться, латиниця й цифри не чіпаються', () {
    expect(EdkOffer.ukrainianSpelling('АНАЛЬГИН ЫЭЁЪ 100мг №10'),
        'АНАЛЬГІН ИЕЕʼ 100мг №10');
    expect(EdkOffer.ukrainianSpelling('NIMESIL 100'), 'NIMESIL 100');
  });

  test('фолд не розрізняє «правильну» И — тому це лише ДОДАТКОВИЙ запит', () {
    // «ЦИТРАМОН» українською теж через И; фолд його зіпсує. Це відомо і
    // безпечно: сира назва йде першим запитом, а рядок вибирається за кодом.
    expect(EdkOffer.ukrainianSpelling('ЦИТРАМОН-В №10 УСТМ'),
        'ЦІТРАМОН-В №10 УСТМ');
  });
}
