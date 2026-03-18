import '../models/cart_offer.dart';
import '../models/drug.dart';

/// Build cart recommendation offers (ТПК — Турбота Про Клієнта).
/// In production these will come from a recommendations service.
List<CartOffer> buildCartOffers(List<Drug> drugs) {
  Drug byId(String id) => drugs.firstWhere((d) => d.id == id);
  return [
    CartOffer(
      drug: byId('019'),
      reason: 'Підтримка імунітету при застуді',
      promoLabel: 'Акція 1+1',
      script:
          'Рекомендую додати вітамін С — він підтримує імунітет і прискорює одужання при застуді.',
    ),
    CartOffer(
      drug: byId('017'),
      reason: 'Супутній препарат при кашлі',
      script:
          'Для полегшення кашлю рекомендую цей муколітик — він розріджує мокротиння.',
    ),
  ];
}
