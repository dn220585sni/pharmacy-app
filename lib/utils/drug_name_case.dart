/// Назва товару для ЕКРАНА.
///
/// Сервер віддає назви капсом («ЦИТРАМОН ЕКСТРА ТАБЛ. №10 УВТМ»), а суцільні
/// великі літери в довгому списку читаються на 20–30 % повільніше за звичайний
/// регістр. Перетворюємо лише для показу: перше слово з великої, решта малими,
/// крім маркерів (ВТМ, УВТМ, ЗФ…) і коротких латинських абревіатур.
///
/// У накладну й чек ПРРО іде оригінал (`Drug.displayName`), його не чіпаємо.
String humanizeDrugName(String s) {
  if (s.isEmpty) return s;
  // Назва вже не капсом (наприклад, з anc.ua) — лишаємо як є.
  final letters = s.replaceAll(_nonLetter, '');
  if (letters.isEmpty || letters != letters.toUpperCase()) return s;

  var isFirst = true;
  return s.split(' ').map((w) {
    if (w.isEmpty) return w;
    if (_keepUpper(w)) return w;
    final lower = w.toLowerCase();
    if (isFirst) {
      isFirst = false;
      return _capitalize(lower);
    }
    return lower;
  }).join(' ');
}

final _nonLetter = RegExp(r'[^A-Za-zА-Яа-яЁёІіЇїЄєҐґ]');
final _nonAlnum = RegExp(r'[^A-Za-zА-Яа-яЁёІіЇїЄєҐґ0-9]');
final _latinAbbrev = RegExp(r'^[A-Z]{2,4}$');

/// Маркери мережі та роздрібу, які мають лишатись капсом.
const _upperTokens = {'ВТМ', 'УВТМ', 'СТМ', 'ЗФ', 'ПМ', 'ЄДК', 'ТПК', 'НПЗЗ'};

bool _keepUpper(String w) {
  // `\w` у Dart не покриває кирилицю — чистимо явним класом літер і цифр.
  final core = w.replaceAll(_nonAlnum, '');
  if (_upperTokens.contains(core)) return true;
  if (_latinAbbrev.hasMatch(core)) return true; // GSK, KRKA, USA
  return false;
}

String _capitalize(String w) {
  // Перша ЛІТЕРА з великої, навіть якщо слово починається з цифри чи лапок.
  final i = w.split('').indexWhere((c) => !_nonLetter.hasMatch(c));
  if (i < 0) return w;
  return w.substring(0, i) + w[i].toUpperCase() + w.substring(i + 1);
}
