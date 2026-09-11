import 'dart:math';

/// Нечіткий пошук назв препаратів — терпимість до одруківок касира.
///
/// Сервер (`SearchByName`/`SearchByNameSKU`) шукає лише точний підрядок у
/// верхньому регістрі, перебираючи ВЕСЬ довідник на кожен запит. Тому все, що
/// прощає помилки, живе тут, на клієнті, і зіставляє слова, а не рядки.
///
/// Що прощаємо (перевірено тестами `test/fuzzy_search_test.dart`):
/// - и/і/ї/й/ы, е/є/э/ё, г/ґ — одне й те саме; ь/ъ/апостроф не рахуються
///   («валер'янка» = «валерянка», «цытрамон» = «цитрамон»);
/// - подвоєння літер («аллохол» = «алохол», «іммуно» = «імуно»);
/// - дефіси, дужки, крапки, лапки — роздільники слів («НО-ШПА» = «но шпа»),
///   а склеєне слово зіставляється з парою сусідніх («ношпа» = «НО-ШПА»);
/// - латиниця в назвах — і за звучанням («MG B6» ↔ «мг б6»), і за виглядом
///   («B6» ↔ «в6», «C» ↔ «с»);
/// - одна помилка у слові з 4–7 літер, дві — з 8 і довших, зокрема
///   переставлені сусідні літери («цтирамон»); слова до 3 літер — лише точно
///   або як початок слова;
/// - порядок слів довільний, кожне слово запиту може бути початком слова
///   назви («зест ант» → «ЗЕСТ (АНТИСТРЕС)»).
///
/// Слова з цифрами («30», «500мг», «б6») — лише точно або як початок: одна
/// помилка в дозуванні — це інший препарат.

// ─── Нормалізація ────────────────────────────────────────────────────────────

/// Латиниця → кирилиця за звучанням: так касир набирає латинські назви
/// («NOVEL» → «новел», «Q-10» → «к-10», «mg» → «мг»).
const _latinPhonetic = <String, String>{
  'a': 'а', 'b': 'б', 'c': 'с', 'd': 'д', 'e': 'е', 'f': 'ф', 'g': 'г',
  'h': 'х', 'i': 'і', 'j': 'й', 'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н',
  'o': 'о', 'p': 'п', 'q': 'к', 'r': 'р', 's': 'с', 't': 'т', 'u': 'у',
  'v': 'в', 'w': 'в', 'x': 'х', 'y': 'і', 'z': 'з',
};

/// Латиниця → кирилиця за виглядом, там де відрізняється від звучання:
/// «B6» касир бачить як «В6», «H» як «Н», «P» як «Р».
const _latinGlyphOverride = <String, String>{
  'b': 'в', 'h': 'н', 'p': 'р', 'y': 'у',
};

/// Кириличні еквіваленти: одна літера на клас плутанини.
const _cyrFold = <String, String>{
  'ы': 'і', 'и': 'і', 'ї': 'і', 'й': 'і',
  'є': 'е', 'э': 'е', 'ё': 'е',
  'ґ': 'г',
};

bool _isCyrLetter(int c) => (c >= 0x430 && c <= 0x44F) || c == 0x456;
bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// Згортає [s] до пошукового вигляду: нижній регістр, латиниця → кирилиця,
/// класи плутанини → одна літера, ь/ъ/апостроф геть, подвоєння згорнуті,
/// усе інше — пробіл. Результат — слова через один пробіл.
///
/// [glyph] — латиницю мапити за виглядом, а не за звучанням (для другого
/// варіанта індексації назв з латинськими літерами).
String foldForSearch(String s, {bool glyph = false}) {
  final out = StringBuffer();
  var lastLetter = -1;
  var pendingSpace = false;
  for (final rune in s.toLowerCase().runes) {
    var ch = String.fromCharCode(rune);
    // ь, ъ, апострофи — просто зникають, не розриваючи слова.
    if (ch == 'ь' || ch == 'ъ' || ch == '\'' || ch == '’' || ch == 'ʼ' ||
        ch == '`' || ch == '‘') {
      continue;
    }
    final lat = glyph
        ? (_latinGlyphOverride[ch] ?? _latinPhonetic[ch])
        : _latinPhonetic[ch];
    if (lat != null) ch = lat;
    ch = _cyrFold[ch] ?? ch;
    final c = ch.codeUnitAt(0);
    if (_isCyrLetter(c) || _isDigit(c)) {
      if (pendingSpace && out.isNotEmpty) out.write(' ');
      pendingSpace = false;
      // Подвоєння літер (не цифр: «100» лишається «100»).
      if (_isCyrLetter(c) && c == lastLetter) continue;
      out.write(ch);
      lastLetter = c;
    } else {
      pendingSpace = true;
      lastLetter = -1;
    }
  }
  return out.toString();
}

/// Слова згорнутого запиту.
List<String> searchTokens(String query) =>
    foldForSearch(query).split(' ').where((t) => t.isNotEmpty).toList();

/// Слово назви: [folded] — для зіставлення, [surface] — як у назві (нижній
/// регістр, без згортання), щоб віддати серверу підрядок, який він знайде.
class SearchWord {
  const SearchWord(this.folded, this.surface);
  final String folded;
  final String surface;
}

final _surfaceWord = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final _hasLatin = RegExp('[a-z]');

void _addVariants(List<SearchWord> out, String surface) {
  final folded = foldForSearch(surface).replaceAll(' ', '');
  if (folded.isEmpty) return;
  out.add(SearchWord(folded, surface));
  if (_hasLatin.hasMatch(surface)) {
    final g = foldForSearch(surface, glyph: true).replaceAll(' ', '');
    if (g != folded && g.isNotEmpty) out.add(SearchWord(g, surface));
  }
}

/// Слова назви [name] з обома варіантами згортання латиниці.
///
/// «MG B6» → (мг, mg), (б6, b6), (в6, b6): і «мг б6», і «мг в6» знайдуть.
List<SearchWord> searchWords(String name) {
  final words = <SearchWord>[];
  for (final m in _surfaceWord.allMatches(name.toLowerCase())) {
    _addVariants(words, m.group(0)!);
  }
  return words;
}

/// Пари сусідніх слів як ОДИН підрядок назви разом зі справжнім роздільником:
/// «НО-ШПА ФОРТЕ» → (ношпа, «но-шпа»), (шпафорте, «шпа форте»).
///
/// Для словника: касир набрав склеєно, а серверу потрібен підрядок, який
/// справді є в назві, — «но-шпа», а не «ношпа».
List<SearchWord> searchWordPairs(String name) {
  final lower = name.toLowerCase();
  final ms = _surfaceWord.allMatches(lower).toList();
  final out = <SearchWord>[];
  for (var i = 0; i + 1 < ms.length; i++) {
    _addVariants(out, lower.substring(ms[i].start, ms[i + 1].end));
  }
  return out;
}

/// Слова [query] як набрано (нижній регістр, без згортання), парами з
/// їх згорнутим виглядом. Слова, що згортаються в ніщо («ь»), пропущено.
List<SearchWord> typedWords(String query) {
  final out = <SearchWord>[];
  for (final m in _surfaceWord.allMatches(query.toLowerCase())) {
    final surface = m.group(0)!;
    final folded = foldForSearch(surface).replaceAll(' ', '');
    if (folded.isNotEmpty) out.add(SearchWord(folded, surface));
  }
  return out;
}

// ─── Відстань ────────────────────────────────────────────────────────────────

/// Скільки помилок прощаємо слову довжини [len].
int allowedDistance(int len) {
  if (len <= 3) return 0;
  if (len <= 7) return 1;
  return 2;
}

/// Відстань Дамерау–Левенштейна (OSA): вставка, видалення, заміна,
/// перестановка сусідніх. Повертає `max + 1`, щойно стане ясно, що відстань
/// більша за [max] — щоб не рахувати зайве на тисячах слів.
int osaDistance(String a, String b, {int max = 1 << 20}) {
  if (a == b) return 0;
  if ((a.length - b.length).abs() > max) return max + 1;
  final n = a.length, m = b.length;
  if (n == 0) return m;
  if (m == 0) return n;

  var prev2 = List<int>.filled(m + 1, 0);
  var prev = List<int>.generate(m + 1, (j) => j);
  var curr = List<int>.filled(m + 1, 0);

  for (var i = 1; i <= n; i++) {
    curr[0] = i;
    var rowMin = i;
    final ai = a.codeUnitAt(i - 1);
    for (var j = 1; j <= m; j++) {
      final bj = b.codeUnitAt(j - 1);
      final cost = ai == bj ? 0 : 1;
      var v = min(min(prev[j] + 1, curr[j - 1] + 1), prev[j - 1] + cost);
      if (i > 1 &&
          j > 1 &&
          ai == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == bj) {
        v = min(v, prev2[j - 2] + 1);
      }
      curr[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    final t = prev2;
    prev2 = prev;
    prev = curr;
    curr = t;
  }
  return prev[m] > max ? max + 1 : prev[m];
}

// ─── Зіставлення слів ────────────────────────────────────────────────────────

final _digit = RegExp(r'\d');

/// Наскільки слово запиту [q] відповідає слову назви [t]: 1 — точно,
/// 0.9 — початок слова, 0.8/0.65 — одна/дві помилки, 0 — не відповідає.
double wordScore(String q, String t) {
  if (q == t) return 1.0;
  if (t.startsWith(q)) return 0.9;
  if (_digit.hasMatch(q) || _digit.hasMatch(t)) return 0.0;
  final allowed = allowedDistance(q.length);
  if (allowed == 0) return 0.0;

  var best = osaDistance(q, t, max: allowed);
  // Початок довшого слова з помилкою: «цитромо» → «цитрамон».
  if (best > allowed && t.length > q.length) {
    best = min(best, osaDistance(q, t.substring(0, q.length), max: allowed));
    if (best > allowed && t.length > q.length + 1) {
      best = min(
          best, osaDistance(q, t.substring(0, q.length + 1), max: allowed));
    }
  }
  if (best > allowed) return 0.0;
  return best == 1 ? 0.8 : 0.65;
}

/// Слова назви для зіставлення: власне слова + склейки сусідніх («но»+«шпа»
/// → «ношпа»), щоб запит без дефіса/пробілу теж знайшовся.
class _NameWords {
  _NameWords(List<String> tokens)
      : words = tokens,
        pairs = [
          for (var i = 0; i + 1 < tokens.length; i++)
            tokens[i] + tokens[i + 1],
        ];
  final List<String> words;
  final List<String> pairs;
}

final _nameWordsCache = <String, _NameWords>{};

_NameWords _nameWords(String name) => _nameWordsCache[name] ??=
    _NameWords(searchWords(name).map((w) => w.folded).toList());

/// Оцінка відповідності запиту [query] назві [name] (+ [nameUkr],
/// [manufacturer]): кожне слово запиту має знайтися серед слів усіх трьох
/// текстів (порядок довільний). 0 — не відповідає, 1 — усі слова точно.
double drugSearchScore(
  String query,
  String name, {
  String? nameUkr,
  String? manufacturer,
}) {
  final qTokens = searchTokens(query);
  if (qTokens.isEmpty) return 1.0;

  final sources = <_NameWords>[
    _nameWords(name),
    if (nameUkr != null && nameUkr.isNotEmpty && nameUkr != name)
      _nameWords(nameUkr),
    if (manufacturer != null && manufacturer.isNotEmpty)
      _nameWords(manufacturer),
  ];

  var total = 0.0;
  for (final q in qTokens) {
    var best = 0.0;
    for (final src in sources) {
      for (final w in src.words) {
        final s = wordScore(q, w);
        if (s > best) best = s;
        if (best == 1.0) break;
      }
      if (best < 1.0) {
        for (final p in src.pairs) {
          final s = wordScore(q, p);
          if (s > best) best = s;
        }
      }
      if (best == 1.0) break;
    }
    if (best == 0.0) return 0.0;
    total += best;
  }
  return total / qTokens.length;
}

/// Початок найдовшого слова [query] для сервера, коли ні точний підрядок, ні
/// словник не допомогли: помилки на початку слова рідкісні, а звузити
/// відповідь до повного запиту ми вміємо самі.
///
/// Рівно 3 літери: сюди ми потрапляємо здебільшого через дефіс у назві
/// («болран» ↔ «БОЛ-РАН»), і 4 літери («болр») його перетинають — 11.09
/// сервер відповів 0+0. Ширша видача не страшна: звуження строге.
/// `null` — нема слова ≥4 літер (той самий виклик уже провалився).
String? stemForServer(String query) {
  String? longest;
  for (final m in _surfaceWord.allMatches(query.toLowerCase())) {
    final w = m.group(0)!;
    if (_digit.hasMatch(w)) continue;
    if (longest == null || w.length > longest.length) longest = w;
  }
  if (longest == null || longest.length < 4) return null;
  return longest.substring(0, 3);
}

// ─── Розкладка ───────────────────────────────────────────────────────────────

/// QWERTY → ЙЦУКЕН (українська): касир забув перемкнути розкладку й набрав
/// «wbnhfvjy» замість «цитрамон».
const _enToUk = <String, String>{
  'q': 'й', 'w': 'ц', 'e': 'у', 'r': 'к', 't': 'е', 'y': 'н', 'u': 'г',
  'i': 'ш', 'o': 'щ', 'p': 'з', '[': 'х', ']': 'ї',
  'a': 'ф', 's': 'і', 'd': 'в', 'f': 'а', 'g': 'п', 'h': 'р', 'j': 'о',
  'k': 'л', 'l': 'д', ';': 'ж', '\'': 'є',
  'z': 'я', 'x': 'ч', 'c': 'с', 'v': 'м', 'b': 'и', 'n': 'т', 'm': 'ь',
  ',': 'б', '.': 'ю', '`': '\'',
};

final _latinLetter = RegExp('[a-z]');
final _cyrLetter = RegExp('[а-яіїєґ]');

/// Чи схоже, що [query] набрано в англійській розкладці: лише латинські
/// літери (без кирилиці), і їх хоча б три.
bool looksLikeLatinLayoutSlip(String query) {
  final q = query.toLowerCase();
  if (_cyrLetter.hasMatch(q)) return false;
  return _latinLetter.allMatches(q).length >= 3;
}

/// Перенабрати [query] так, ніби розкладка була українська.
String latinLayoutToUkrainian(String query) {
  final out = StringBuffer();
  for (final rune in query.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    out.write(_enToUk[ch] ?? ch);
  }
  return out.toString();
}
