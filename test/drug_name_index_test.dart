import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/drug_name_index.dart';
import 'package:pharmacy_app/services/drug_service.dart';

/// Виправлення запиту за локальним словником назв — що шлемо серверу, коли
/// набране повернуло порожньо (див. `lib/services/drug_name_index.dart`).
void main() {
  DrugSearchItem item(String ukod, String name, {String? nameUkr}) =>
      DrugSearchItem(
        ids: ukod,
        ukod: ukod,
        name: name,
        nameUkr: nameUkr,
        manufacturer: 'Дарниця',
        shelf: '',
        qty: 1,
        price: 1,
      );

  late DrugNameIndex idx;

  setUp(() {
    idx = DrugNameIndex.inMemory();
    idx.feed([
      item('1', 'ЦИТРАМОН-Д №10'),
      item('2', 'ЦИТРАМОН-Д №6'),
      item('3', 'ЗЕСТ (АНТИСТРЕС) MG B6 РЕТАРД ТАБЛ. №30'),
      item('4', 'НО-ШПА ТАБЛ. №24'),
      item('5', 'АЛЛОХОЛ ТАБЛ. №50'),
      item('6', 'НУРОФЕН ТАБЛ. №12'),
      item('7', 'ЗЕСТ АКТИВ ПАСТ. ЖУВ №30'),
      item('8', 'ВИТАМИН С', nameUkr: 'ВІТАМІН С'),
    ]);
  });

  test('одруківка → слово в написанні з назви', () {
    final f = idx.fix('цитромон')!;
    expect(f.fullQuery, 'цитрамон');
    expect(f.serverQuery, 'цитрамон');
    expect(f.changed, isTrue);
  });

  test('ы/є → серверу справжнє написання', () {
    expect(idx.fix('цытрамон')!.serverQuery, 'цитрамон');
    expect(idx.fix('зєст')!.serverQuery, 'зест');
  });

  test('подвоєння: серверу — з подвоєнням, як у назві', () {
    final f = idx.fix('алохол')!;
    expect(f.serverQuery, 'аллохол');
    expect(f.changed, isTrue);
  });

  test('інший порядок слів → серверу найрідкісніше слово, порядок касира', () {
    final f = idx.fix('актив зест')!;
    expect(f.fullQuery, 'актив зест');
    expect(f.changed, isFalse); // слова ті самі — підказка не потрібна
    // «зест» є у двох назвах, «актив» — в одній: селективніше «актив».
    expect(f.serverQuery, 'актив');
  });

  test('пробіл замість дефіса — обидва слова відомі', () {
    final f = idx.fix('но шпа')!;
    expect(f.fullQuery, 'но шпа');
    expect(f.serverQuery, 'шпа');
    expect(f.changed, isFalse);
  });

  test('початок слова → серверу повне слово', () {
    final f = idx.fix('цитр')!;
    expect(f.serverQuery, 'цитрамон');
  });

  test('невідоме слово без близького → null (без зайвого виклику)', () {
    expect(idx.fix('зест ксанакс'), isNull);
    expect(idx.fix('qwertyuiop'), isNull);
  });

  test('цифри поза словником не блокують і не йдуть серверу', () {
    final f = idx.fix('цитромон 20')!;
    expect(f.fullQuery, 'цитрамон 20');
    expect(f.serverQuery, 'цитрамон');
  });

  test('забута розкладка', () {
    final f = idx.fix('wbnhfvjy')!;
    expect(f.fullQuery, 'цитрамон');
    expect(f.changed, isTrue);
  });

  test('латинська назва — не розкладка', () {
    final f = idx.fix('mg b6')!;
    expect(f.fullQuery, 'mg b6');
    expect(f.changed, isFalse);
  });

  test('українська назва теж у словнику; серверу — НЕ те, що вже провалилось',
      () {
    // Набране «витамин» = російське написання; сервер його не знайшов —
    // шлемо українське.
    expect(idx.fix('витамин')!.serverQuery, 'вітамін');
    // І навпаки.
    expect(idx.fix('вітамін')!.serverQuery, 'витамин');
    // Через є — жодне з написань не набране, беремо українське (перше).
    expect(idx.fix('вітамєн')!.serverQuery, 'вітамін');
  });

  test('склеєне слово → серверу підрядок назви з роздільником', () {
    final f = idx.fix('ношпа')!;
    expect(f.serverQuery, 'но-шпа');
    expect(f.fullQuery, 'но-шпа');
    expect(f.changed, isTrue);
  });

  test('склеєне з одруківкою', () {
    expect(idx.fix('ношпо')!.serverQuery, 'но-шпа');
  });

  test('порожній словник → null', () {
    expect(DrugNameIndex.inMemory().fix('цитрамон'), isNull);
  });

  test('SearchByName (u-коди): ukod порожній, ids = u-код', () {
    final i = DrugNameIndex.inMemory();
    i.feed([
      DrugSearchItem(
        ids: '762*1*47',
        name: 'ПАНАДОЛ',
        manufacturer: '',
        shelf: '',
        qty: 0,
        price: 0,
      ),
    ]);
    expect(i.length, 1);
    expect(i.fix('панодол')!.serverQuery, 'панадол');
  });

  test('повторний feed тієї самої назви нічого не змінює', () {
    final before = idx.length;
    idx.feed([item('1', 'ЦИТРАМОН-Д №10')]);
    expect(idx.length, before);
  });
}
