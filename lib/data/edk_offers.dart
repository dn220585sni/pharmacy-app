import '../models/drug.dart';
import '../models/edk_offer.dart';
import '../services/priority_analog_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// API-based EDK offers builder (live mode)
// ═══════════════════════════════════════════════════════════════════════════════

/// Build EDK offers from Priority Analogs API data.
///
/// Keyed by **donor ukod** (string). For each donor, finds the first analog
/// (by RATING) that exists in [drugs] catalog with stock > 0.
Map<String, EdkOffer> buildEdkOffersFromApi(
  List<PriorityAnalog> analogs,
  List<Drug> drugs,
) {
  // Build ukod → Drug lookup (only drugs with ukod and stock)
  final drugByUkod = <String, Drug>{};
  for (final d in drugs) {
    if (d.ukod != null && d.ukod!.isNotEmpty) {
      // Keep the one with most stock if duplicates
      final existing = drugByUkod[d.ukod!];
      if (existing == null || d.stock > existing.stock) {
        drugByUkod[d.ukod!] = d;
      }
    }
  }

  // Group analogs by donor ukod, sorted by rating
  final grouped = <String, List<PriorityAnalog>>{};
  for (final a in analogs) {
    final key = a.donorUkod.toString();
    (grouped[key] ??= []).add(a);
  }
  for (final list in grouped.values) {
    list.sort((a, b) => a.rating.compareTo(b.rating));
  }

  // Build offers: first in-stock analog per donor
  final offers = <String, EdkOffer>{};
  for (final entry in grouped.entries) {
    final donorKey = entry.key;
    for (final analog in entry.value) {
      final analogKey = analog.analogUkod.toString();
      final replacementDrug = drugByUkod[analogKey];
      if (replacementDrug != null && replacementDrug.stock > 0) {
        // Build promo label from bonuses
        String? promo;
        if (analog.bonus > 0 && analog.dodBonus > 0) {
          promo = 'Бонус +${analog.bonus + analog.dodBonus}';
        } else if (analog.bonus > 0) {
          promo = 'Бонус +${analog.bonus}';
        } else if (analog.dodBonus > 0) {
          promo = 'Дод. бонус +${analog.dodBonus}';
        }

        offers[donorKey] = EdkOffer(
          drug: replacementDrug,
          donorDrugId: donorKey,
          description: '${analog.analogName} — '
              'рекомендована заміна від ${analog.analogManufact.replaceAll('*', '').trim()}.',
          script: 'Рекомендую розглянути ${analog.analogName.trim()} — '
              'якісний аналог з перевіреною ефективністю.',
          promoLabel: promo,
          bonus: analog.bonus,
          dodBonus: analog.dodBonus,
          linkType: analog.linkType,
          rating: analog.rating,
        );
        break; // перший з наявністю — достатньо
      }
    }
  }

  return offers;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Mock EDK offers (development mode)
// ═══════════════════════════════════════════════════════════════════════════════

/// Build MOCK retail EDK offers map (donor Drug.id → replacement offer).
/// Used by PosScreen in mock mode.
Map<String, EdkOffer> buildMockRetailEdkOffers(List<Drug> drugs) {
  Drug byId(String id) => drugs.firstWhere((d) => d.id == id);
  return {
    // ── In-stock EDK offers ────────────────────────────────────────────────
    // Ібупрофен 200мг №20 id:'024' (bonus 8) → Нурофен Експрес id:'009' (bonus 20)
    '024': EdkOffer(
      drug: byId('009'),
      donorDrugId: '024',
      description:
          'Капсульна форма для швидшого всмоктування — '
          'ефект настає вже через 15 хвилин.',
      script:
          'Зверніть увагу, є аналогічний препарат у капсулах — '
          'діє значно швидше. Бажаєте спробувати?',
      promoLabel: 'Потрійний кешбек',
    ),
    // Парацетамол 500мг №20 id:'001' (bonus 5) → Панадол 500мг №12 id:'031' (bonus 12)
    '001': EdkOffer(
      drug: byId('031'),
      donorDrugId: '001',
      description:
          'Європейська якість, та сама діюча речовина. '
          'Покращена формула для швидшого всмоктування.',
      script:
          'Є такий самий парацетамол європейського виробництва — '
          'діє швидше завдяки покращеній формулі. Рекомендую!',
    ),
    // МІГ 400 №20 id:'025' (bonus 12) → Нурофен форте 400мг id:'035' (bonus 20)
    '025': EdkOffer(
      drug: byId('035'),
      donorDrugId: '025',
      description:
          'Преміальна якість від світового виробника. '
          'Швидкодіюча формула для максимального ефекту.',
      script:
          'Якщо потрібен максимальний ефект — рекомендую цей варіант. '
          'Швидкодіюча формула, перевірена якість.',
      promoLabel: 'Знижка −10%',
    ),
    // ── Out-of-stock EDK offers ────────────────────────────────────────────
    // Диклофенак 50мг id:'050' → Нурофен Експрес id:'009' (bonus 20)
    '050': EdkOffer(
      drug: byId('009'),
      donorDrugId: '050',
      description:
          'Відмінна заміна — капсульна форма діє швидше '
          'та ефективніше знімає біль.',
      script:
          'На жаль, Диклофенак зараз відсутній на ринку. '
          'Рекомендую Нурофен Експрес — капсули для швидкого ефекту.',
    ),
    // Цефтріаксон 1г id:'051' (quarantined) → Флемоксин Солютаб id:'042' (bonus 12)
    '051': EdkOffer(
      drug: byId('042'),
      donorDrugId: '051',
      description:
          'Пероральний антибіотик широкого спектру — '
          'зручна форма прийому без ін\'єкцій.',
      script:
          'Цефтріаксон зараз у карантині. Рекомендую Флемоксин Солютаб — '
          'потужний антибіотик у зручній формі таблеток.',
    ),
    // Кларитін 10мг id:'053' → Цетрин 10мг id:'036'
    '053': EdkOffer(
      drug: byId('036'),
      donorDrugId: '053',
      description:
          'Цетрин — сучасний антигістамінний засіб '
          'з тією ж ефективністю та м\'якою дією.',
      script:
          'Кларитін наразі не замовлений. Рекомендую Цетрин — '
          'така ж діюча речовина, перевірена якість.',
    ),
  };
}

/// Build MOCK order EDK offers map (order item SKU → replacement offer).
/// Used by OrdersPanel in mock mode.
Map<String, EdkOffer> buildMockOrderEdkOffers(List<Drug> drugs) {
  Drug byId(String id) => drugs.firstWhere((d) => d.id == id);
  return {
    // МЕЛОКСИКАМ-ТЕВА (ord-07) → Нурофен Експрес
    '26771903': EdkOffer(
      drug: byId('009'),
      donorDrugId: '26771903',
      description: 'Капсульна форма — швидше всмоктування.',
      script:
          'У клієнта Мелоксикам. Пропоную Нурофен Експрес — '
          'капсули для швидкого знеболення.',
      promoLabel: 'Потрійний кешбек',
    ),
    // ЕНТЕРОСГЕЛЬ (ord-14, Glovo) → Атоксіл (mock id '032')
    '26883210': EdkOffer(
      drug: byId('032'),
      donorDrugId: '26883210',
      description: 'Потужний сорбент нового покоління.',
      script:
          'До Ентеросгелю рекомендую розглянути Атоксіл — '
          'сильніший сорбент за нижчою ціною.',
    ),
    // СІОФОР ХР (ord-09) → Метформін (mock id '010')
    '26890213': EdkOffer(
      drug: byId('010'),
      donorDrugId: '26890213',
      description: 'Та ж діюча речовина, вигідніша ціна.',
      script:
          'Замість Сіофору пропоную Метформін — ідентичний склад, '
          'значно вигідніша ціна для клієнта.',
    ),
    // ДОППЕЛЬГЕРЦ АКТ (ord-11) → Вітамін D3 (mock id '019')
    '26345670': EdkOffer(
      drug: byId('019'),
      donorDrugId: '26345670',
      description: 'Преміальна якість від Солгар.',
      script:
          'До Доппельгерц рекомендую Вітамін D3 від Солгар — '
          'вищий вміст діючої речовини, перевірена якість.',
      promoLabel: 'Кешбек ×2',
    ),
    // ЦИПРОФЛОКСАЦИН (ord-03) → Флемоксин Солютаб (mock id '042')
    '25487201': EdkOffer(
      drug: byId('042'),
      donorDrugId: '25487201',
      description: 'Зручна форма прийому без ін\'єкцій.',
      script:
          'Рекомендую розглянути Флемоксин Солютаб — '
          'потужний антибіотик у зручній формі таблеток.',
    ),
  };
}
