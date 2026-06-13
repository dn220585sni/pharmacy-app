// Тести парсингу StopPriceAction / NaborItem з реальних відповідей
// GetStopPriceUKod.
//
// Фікстур test/fixtures/stop_price_sample.json — зрізаний реальний JSON
// (4 дії, що покривають типові форми: adddisk+крос-сейл, пряма знижка r:,
// драбина rules, порожній Nabor).
//
// Якщо поряд лежить повний дамп tool/stop_price_examples_check.json —
// додатковий тест прогонить парсинг по всіх ~1185 діях і перевірить, що
// нічого не падає та агрегати ненульові.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/stop_price_action.dart';

List<StopPriceAction> _parseActions(Map<String, dynamic> resp) {
  final raw = resp['Actions'];
  return raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(StopPriceAction.fromJson)
          .toList()
      : const <StopPriceAction>[];
}

void main() {
  group('StopPriceAction.fromJson (fixture)', () {
    late List<StopPriceAction> actions;

    setUpAll(() {
      final file = File('test/fixtures/stop_price_sample.json');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      actions = _parseActions(json);
    });

    test('парсить усі дії без винятків', () {
      expect(actions, isNotEmpty);
    });

    test('adddisk + крос-сейл (dopgoods=1) — рекомендований супутній товар', () {
      final a = actions.firstWhere((a) => a.id == '43425');
      expect(a.pravilo, 'adddisk:0.00%:1:');
      expect(a.dateBegin, '01.06.2026');
      expect(a.dateEnd, '30.06.2026');
      expect(a.pack, 1);
      expect(a.priceNabor, 0);

      expect(a.hasNabor, isTrue);
      expect(a.nabor, hasLength(1));
      final n = a.nabor.single;
      expect(n.ukod, '7827.999*90*721.999*24****22162.999');
      expect(n.name, contains('ХЕРБАЛСЕПТІК'));
      expect(n.kol, 1);
      expect(n.isAdditional, isTrue);

      // Допродаж: товар з dopgoods=1 потрапляє в recommendedItems.
      expect(a.recommendedItems, hasLength(1));
      expect(a.recommendedItems.single.ukod, n.ukod);
      // % знижки на супутній товар — з тексту opis ("знижка 15.0%").
      expect(a.recommendedDiscountText, '−15%');
    });

    test('пряма знижка r:-20% (dopgoods=0) — Nabor є, але не допродаж', () {
      final a = actions.firstWhere((a) => a.id == '43351');
      expect(a.pravilo, 'r:-20.00%:1:');
      expect(a.hasNabor, isTrue);
      expect(a.nabor.single.isAdditional, isFalse);
      // dopgoods=0 → не вважається рекомендованим допродажем.
      expect(a.recommendedItems, isEmpty);
      // Базова знижка декодується з pravilo.
      expect(a.baseIncentiveText, '−20%');
      // АЛЕ знижка УМОВНА (є Nabor — діє у зв'язці) → не безумовна ціна в таблиці.
      expect(a.unconditionalPromoPrice(100), isNull);
    });

    test('драбина rules без Nabor', () {
      final a = actions.firstWhere((a) => a.id == '43311');
      expect(a.hasNabor, isFalse);
      expect(a.nabor, isEmpty);
      expect(a.recommendedItems, isEmpty);
      expect(a.rules, hasLength(2));
      expect(a.rules[0].kol, 2);
      expect(a.rules[0].discountPercent, -10.0);
      expect(a.rules[0].incentiveText, 'Купи 2+ → −10%');
      // Друге правило adddisk:0% → без відсотка.
      expect(a.rules[1].discountPercent, isNull);
    });
  });

  group('NaborItem.fromJson — крайові випадки', () {
    test('відсутні/порожні поля → безпечні дефолти', () {
      const empty = <String, dynamic>{};
      final n = NaborItem.fromJson(empty);
      expect(n.ukod, '');
      expect(n.name, '');
      expect(n.kol, 1);
      expect(n.isAdditional, isFalse);
    });

    test('dopgoods як рядок "1" → isAdditional', () {
      final n = NaborItem.fromJson({'dopgoods': '1', 'kol': '3'});
      expect(n.isAdditional, isTrue);
      expect(n.kol, 3);
    });
  });

  group('StopPriceAction — стійкість парсингу', () {
    test('Nabor не список → порожній, без винятку', () {
      final a = StopPriceAction.fromJson({'id': '1', 'Nabor': 'oops'});
      expect(a.nabor, isEmpty);
      expect(a.hasNabor, isFalse);
    });

    test('priceNabor з комою як десятковим роздільником', () {
      final a = StopPriceAction.fromJson({'id': '1', 'priceNabor': '12,50'});
      expect(a.priceNabor, 12.5);
    });

    test('pravilo r:-32.00 БЕЗ % = абсолютна знижка 32 грн (не 32%)', () {
      final a = StopPriceAction.fromJson({'id': '1', 'pravilo': 'r:-32.00:1:'});
      final base = a.baseRule!;
      expect(base.isPercent, isFalse);
      expect(base.discountPercent, isNull);
      expect(base.discountUah, 32.0);
      expect(a.baseIncentiveText, '−32 грн');
      // ОРАСЕПТ: роздріб 432 → 432 − 32 = 400 (а не 432×0.68 = 293,76).
      expect(a.unconditionalPromoPrice(432), 400.0);
    });

    test('pravilo r:-20.00% зі знаком % = відсоткова знижка', () {
      final a = StopPriceAction.fromJson({'id': '1', 'pravilo': 'r:-20.00%:1:'});
      final base = a.baseRule!;
      expect(base.isPercent, isTrue);
      expect(base.discountPercent, -20.0);
      expect(base.discountUah, isNull);
      expect(a.baseIncentiveText, '−20%');
      expect(a.unconditionalPromoPrice(100), 80.0);
    });

    test('recommendedDiscountText — варіації тексту opis', () {
      String? disc(String opis) =>
          StopPriceAction.fromJson({'id': '1', 'opis': opis})
              .recommendedDiscountText;
      expect(disc('Для Вас знижка 20%'), '−20%');
      expect(disc('ще знижка 12,5% на товар'), '−12.5%');
      expect(disc('знижку 10.0% на аналог'), '−10%');
      expect(disc('без жодних відсотків'), isNull);
      expect(disc('знижка 0%'), isNull);
    });
  });

  // Опціонально: повний дамп, якщо він присутній у робочій копії.
  group('повний дамп GetStopPriceUKod (якщо є)', () {
    final dump = File('tool/stop_price_examples_check.json');

    test('усі дії парсяться, агрегати ненульові', () {
      if (!dump.existsSync()) {
        markTestSkipped('tool/stop_price_examples_check.json відсутній');
        return;
      }
      final root = jsonDecode(dump.readAsStringSync()) as Map<String, dynamic>;
      final examples = (root['examples'] as List).cast<Map<String, dynamic>>();

      var total = 0;
      var withNabor = 0;
      var recommended = 0;
      for (final e in examples) {
        final raw = e['raw'];
        if (raw is! Map<String, dynamic>) continue;
        for (final a in _parseActions(raw)) {
          total++;
          if (a.hasNabor) withNabor++;
          recommended += a.recommendedItems.length;
        }
      }

      expect(total, greaterThan(0));
      expect(withNabor, greaterThan(0));
      expect(recommended, greaterThan(0));
      // ignore: avoid_print
      print('Дамп: дій=$total, з Nabor=$withNabor, допродажів=$recommended');
    });
  });
}
