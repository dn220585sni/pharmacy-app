import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/utils/fuzzy_search.dart';

/// Терпимість пошуку до одруківок касира (див. `lib/utils/fuzzy_search.dart`).
void main() {
  group('foldForSearch — нормалізація', () {
    test('и/і/ї/й/ы, е/є/э/ё, ґ/г — один клас', () {
      expect(foldForSearch('Цитрамон'), foldForSearch('цітрамон'));
      expect(foldForSearch('цытрамон'), foldForSearch('цитрамон'));
      expect(foldForSearch('Зест'), foldForSearch('зєст'));
      expect(foldForSearch('ґлюкоза'), foldForSearch('глюкоза'));
      expect(foldForSearch('калій'), foldForSearch('калии'));
    });

    test('ь/ъ/апостроф не рахуються і не розривають слово', () {
      expect(foldForSearch("Валер'янка"), foldForSearch('валерянка'));
      expect(foldForSearch('Валер’янка'), foldForSearch('валерянка'));
      expect(foldForSearch('кальцій'), foldForSearch('калций'));
      expect(foldForSearch("здоров'я"), 'здоровя');
    });

    test('подвоєння літер згортаються, цифр — ні', () {
      expect(foldForSearch('Аллохол'), foldForSearch('алохол'));
      expect(foldForSearch('ІММУНО'), foldForSearch('імуно'));
      expect(foldForSearch('№100'), '100');
    });

    test('дефіси, дужки, крапки — роздільники слів', () {
      expect(foldForSearch('НО-ШПА'), 'но шпа');
      expect(foldForSearch('ЗЕСТ (АНТИСТРЕС) MG B6  РЕТАРД ТАБЛ. №30'),
          'зест антістрес мг б6 ретард табл 30');
    });

    test('латиниця за звучанням і за виглядом', () {
      expect(foldForSearch('NOVEL'), 'новел');
      expect(foldForSearch('Q-10'), 'к 10');
      expect(foldForSearch('B6', glyph: true), 'в6');
      expect(foldForSearch('C', glyph: true), 'с');
      expect(foldForSearch('H'), 'х');
      expect(foldForSearch('H', glyph: true), 'н');
    });
  });

  group('searchWords', () {
    test('латинське слово дає обидва варіанти з одним surface', () {
      final w = searchWords('MG B6');
      expect(w.map((x) => x.folded), containsAll(['мг', 'б6', 'в6']));
      expect(w.where((x) => x.folded == 'в6').single.surface, 'b6');
    });

    test('surface — як у назві, у нижньому регістрі', () {
      final w = searchWords('АЛЛОХОЛ ТАБЛ. №50');
      expect(w.map((x) => x.surface), ['аллохол', 'табл', '50']);
      expect(w.first.folded, 'алохол');
    });

    test('пари сусідніх слів зі справжнім роздільником', () {
      final p = searchWordPairs('НО-ШПА ФОРТЕ 80 МГ');
      expect(p.map((x) => x.folded), ['ношпа', 'шпафорте', 'форте80', '80мг']);
      expect(p.first.surface, 'но-шпа');
      expect(p[1].surface, 'шпа форте');
    });

    test('typedWords — як набрано + згорнуте', () {
      final t = typedWords('Цытрамон-Д ь №10');
      expect(t.map((x) => x.surface), ['цытрамон', 'д', '10']);
      expect(t.map((x) => x.folded), ['цітрамон', 'д', '10']);
    });
  });

  group('osaDistance', () {
    test('перестановка сусідніх = 1', () {
      expect(osaDistance('цтирамон', 'цитрамон'), 1);
    });
    test('заміна, вставка, видалення', () {
      expect(osaDistance('нурофен', 'нурафен'), 1);
      expect(osaDistance('нурофен', 'нурофенн'), 1);
      expect(osaDistance('нурофен', 'нуофен'), 1);
      expect(osaDistance('нурофен', 'нурофен'), 0);
    });
    test('обрізання за max', () {
      expect(osaDistance('абвгд', 'xyz', max: 1), 2);
      expect(osaDistance('абвгд', 'абвгж', max: 0), 1);
    });
  });

  group('allowedDistance', () {
    test('≤3 — точно, 4–7 — одна, ≥8 — дві', () {
      expect(allowedDistance(3), 0);
      expect(allowedDistance(4), 1);
      expect(allowedDistance(7), 1);
      expect(allowedDistance(8), 2);
    });
  });

  group('drugSearchScore', () {
    const name = 'ЗЕСТ (АНТИСТРЕС) MG B6  РЕТАРД ТАБЛ. №30';
    double s(String q, [String n = name]) => drugSearchScore(q, n);

    test('точний збіг усіх слів = 1', () {
      expect(s('зест антистрес'), 1.0);
    });

    test('є замість е, и замість і — так само точно', () {
      expect(s('зєст антістрес'), 1.0);
    });

    test('початки слів у будь-якому порядку', () {
      expect(s('ант зест'), greaterThan(0));
      expect(s('ретар'), greaterThan(0));
    });

    test('одна помилка в слові з 4–7 літер', () {
      expect(s('зост'), 0.8);
      expect(s('ретарт'), 0.8);
    });

    test('одна і дві помилки у слові з ≥8 літер', () {
      expect(s('антестрес'), 0.8);
      expect(s('антситрас'), 0.65);
    });

    test('забагато помилок — не збіг', () {
      expect(s('зоср'), 0);
      expect(s('зест нурофен'), 0); // чуже слово валить весь запит
    });

    test('короткі слова — лише точно або як початок', () {
      expect(s('зес'), greaterThan(0));
      expect(s('зєк'), 0);
    });

    test('цифри — лише точно або як початок', () {
      expect(s('зест 30'), 1.0);
      expect(s('зест 31'), 0);
      expect(s('зест 3'), greaterThan(0));
    });

    test('латиниця в назві: і «б6», і «в6», і «mg»', () {
      expect(s('b6'), 1.0);
      expect(s('в6'), 1.0);
      expect(s('мг в6'), 1.0);
      expect(s('mg b6'), 1.0);
    });

    test('склеєне слово = пара сусідніх, пробіл = дефіс', () {
      expect(drugSearchScore('ношпа', 'НО-ШПА ТАБЛ. №24'), 1.0);
      expect(drugSearchScore('но шпа', 'НО-ШПА ТАБЛ. №24'), 1.0);
      expect(drugSearchScore('но-шпа', 'НО ШПА ТАБЛ. №24'), 1.0);
    });

    test('виробник і українська назва теж рахуються', () {
      expect(
        drugSearchScore('зест дельта', name,
            manufacturer: 'Дельта Медікел Промоушнз'),
        1.0,
      );
      expect(
        drugSearchScore('магній', 'МАГНИЙ B6', nameUkr: 'МАГНІЙ B6'),
        1.0,
      );
    });

    test('латинська назва за звучанням', () {
      expect(drugSearchScore('новел', 'Новел NOVEL магній'), 1.0);
      expect(drugSearchScore('ку 10', 'КОЕНЗИМ Q-10 КАПС.'), 0);
      expect(drugSearchScore('к 10', 'КОЕНЗИМ Q-10 КАПС.'), 1.0);
    });

    test('перестановка сусідніх літер', () {
      expect(drugSearchScore('цтирамон', 'ЦИТРАМОН-Д №10'), 0.8);
    });

    test('початок довгого слова з помилкою', () {
      expect(drugSearchScore('цитромо', 'ЦИТРАМОН-Д №10'), 0.8);
    });

    test('порожній запит відповідає всьому', () {
      expect(s(''), 1.0);
      expect(s(' - '), 1.0);
    });
  });

  group('stemForServer', () {
    test('перші 3 літери найдовшого слова — щоб не перетнути дефіс назви', () {
      expect(stemForServer('болран'), 'бол'); // «БОЛ-РАН»: «болр» → 0
      expect(stemForServer('зест актив'), 'акт');
      expect(stemForServer('но-шпа форте 80'), 'фор');
      expect(stemForServer('болр'), 'бол');
    });
    test('null, коли нема слова ≥4 літер', () {
      expect(stemForServer('бол'), isNull);
      expect(stemForServer('но шпа'), isNull);
      expect(stemForServer('12345'), isNull);
    });
  });

  group('розкладка', () {
    test('QWERTY → ЙЦУКЕН', () {
      expect(latinLayoutToUkrainian('wbnhfvjy'), 'цитрамон');
      expect(latinLayoutToUkrainian('pt.n frnbd'), 'зеют актив');
    });

    test('looksLikeLatinLayoutSlip', () {
      expect(looksLikeLatinLayoutSlip('wbnhfvjy'), isTrue);
      expect(looksLikeLatinLayoutSlip('зест mg'), isFalse);
      expect(looksLikeLatinLayoutSlip('ab'), isFalse);
      expect(looksLikeLatinLayoutSlip('123'), isFalse);
    });
  });
}
