import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/fuzzy_search.dart';
import 'drug_service.dart';

/// Локальний словник назв препаратів цієї аптеки — для виправлення запиту
/// перед повторним зверненням до сервера.
///
/// Навіщо: сервер шукає лише точний підрядок і перебирає весь довідник на
/// кожен виклик. Одруківка = порожня відповідь = касир перенабирає = ще 2–4
/// повних перебори. Тут ми виправляємо запит самі й робимо ОДИН повторний
/// виклик — і лише коли перший повернув порожньо.
///
/// Це НЕ джерело результатів: ціни й залишки тут застарілі б за день. Лише
/// слова назв, з яких збирається виправлений запит. Наповнюється топ-500 на
/// старті та кожною відповіддю сервера; зберігається на диску, тож за кілька
/// днів покриває реальний асортимент аптеки.
class DrugNameIndex {
  DrugNameIndex._();

  /// Без диска — для тестів.
  @visibleForTesting
  DrugNameIndex.inMemory();

  static final instance = DrugNameIndex._();

  static const _fileName = 'drug_names.json';
  static const _maxEntries = 20000;

  /// ukod → назви. LinkedHashMap: порядок вставки = вік, для витіснення.
  final _entries = <String, _Entry>{};

  /// Згорнуте слово → скільки товарів його містять (селективність).
  var _freq = <String, int>{};

  /// Згорнуте слово → як воно пишеться в назвах (для сервера), українське
  /// написання першим. Кілька варіантів («німесил»/«нимесил»), бо ми не
  /// знаємо, яке з полів сервер шукає, — а набране вже провалилось.
  var _surface = <String, List<String>>{};
  bool _dictDirty = true;

  File? _file;
  Timer? _saveTimer;
  bool _fileDirty = false;

  int get length => _entries.length;

  // ─── Диск ──────────────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      if (!await _file!.exists()) return;
      final json = jsonDecode(await _file!.readAsString());
      final items = (json as Map)['items'];
      if (items is! List) return;
      for (final j in items.whereType<Map>()) {
        final key = j['u']?.toString();
        if (key == null || key.isEmpty) continue;
        _entries[key] = _Entry(
          name: j['n']?.toString() ?? '',
          nameUkr: j['nu']?.toString(),
          top: j['t'] == 1,
        );
      }
      _dictDirty = true;
      debugPrint('DrugNameIndex: ${_entries.length} назв з диска');
    } catch (e) {
      debugPrint('DrugNameIndex load FAIL: $e');
    }
  }

  void _scheduleSave() {
    if (_file == null) return;
    _fileDirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 5), () => unawaited(_save()));
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null || !_fileDirty) return;
    _fileDirty = false;
    try {
      final items = [
        for (final e in _entries.entries)
          {
            'u': e.key,
            'n': e.value.name,
            if (e.value.nameUkr != null) 'nu': e.value.nameUkr,
            if (e.value.top) 't': 1,
          },
      ];
      await f.writeAsString(jsonEncode({'v': 1, 'items': items}),
          flush: true);
    } catch (e) {
      debugPrint('DrugNameIndex save FAIL: $e');
    }
  }

  // ─── Наповнення ────────────────────────────────────────────────────────────

  /// Додати результати пошуку. [top] — з `GetTopDrugs` (не витісняються).
  ///
  /// У `SearchByName` (u-коди) `ukod` порожній, а `ids` і є u-код.
  void feed(Iterable<DrugSearchItem> items, {bool top = false}) {
    var changed = false;
    for (final it in items) {
      final key = it.ukod.isNotEmpty ? it.ukod : it.ids;
      if (key.isEmpty || it.name.isEmpty) continue;
      final old = _entries[key];
      if (old != null &&
          old.name == it.name &&
          old.nameUkr == it.nameUkr &&
          (old.top || !top)) {
        continue;
      }
      _entries[key] = _Entry(
        name: it.name,
        nameUkr: it.nameUkr,
        top: top || (old?.top ?? false),
      );
      changed = true;
    }
    if (!changed) return;
    _evict();
    _dictDirty = true;
    _scheduleSave();
  }

  void _evict() {
    if (_entries.length <= _maxEntries) return;
    final victims = <String>[];
    for (final e in _entries.entries) {
      if (e.value.top) continue;
      victims.add(e.key);
      if (_entries.length - victims.length <= _maxEntries) break;
    }
    victims.forEach(_entries.remove);
  }

  void _rebuildDict() {
    final freq = <String, int>{};
    final surface = <String, List<String>>{};
    for (final e in _entries.values) {
      final seen = <String>{};
      for (final name in [if (e.nameUkr != null) e.nameUkr!, e.name]) {
        // Пари сусідніх слів («но-шпа») — щоб склеєне «ношпа» теж
        // виправлялось у справжній підрядок назви.
        for (final w in [...searchWords(name), ...searchWordPairs(name)]) {
          if (seen.add(w.folded)) freq[w.folded] = (freq[w.folded] ?? 0) + 1;
          final list = surface.putIfAbsent(w.folded, () => []);
          if (list.length < 4 && !list.contains(w.surface)) list.add(w.surface);
        }
      }
    }
    _freq = freq;
    _surface = surface;
    _dictDirty = false;
  }

  // ─── Виправлення запиту ────────────────────────────────────────────────────

  /// Що слати серверу замість [typed], який повернув порожньо.
  ///
  /// `null` — словник не знає якогось слова й не має до нього близького:
  /// повторний виклик, найпевніше, теж повернув би порожньо, тож не робимо.
  QueryFix? fix(String typed) {
    if (_entries.isEmpty) return null;
    if (_dictDirty) _rebuildDict();

    var tokens = typedWords(typed);
    if (tokens.isEmpty) return null;

    // Забута розкладка: «wbnhfvjy» → «цитрамон». Беремо лише якщо після
    // перенабору ВСІ слова знайомі — інакше це просто латинська назва.
    var layoutFixed = false;
    if (looksLikeLatinLayoutSlip(typed)) {
      final alt = typedWords(latinLayoutToUkrainian(typed));
      if (alt.isNotEmpty &&
          alt.every((t) => _resolve(t.folded, t.surface) != null)) {
        tokens = alt;
        layoutFixed = true;
      }
    }

    final resolved = <_Resolved>[];
    for (final t in tokens) {
      final r = _resolve(t.folded, t.surface);
      if (r == null) return null;
      resolved.add(r);
    }

    final full = resolved.map((r) => r.surface).join(' ');
    final typedNorm =
        typed.toLowerCase().trim().split(RegExp(r'\s+')).join(' ');

    // Серверу — найрідкісніше слово з літерами (найселективніше): він і
    // так обрізає видачу на 50, а звузити до повного запиту ми вміємо самі.
    _Resolved? pick;
    for (final r in resolved) {
      if (r.numeric) continue;
      if (pick == null ||
          r.freq < pick.freq ||
          (r.freq == pick.freq && r.surface.length > pick.surface.length)) {
        pick = r;
      }
    }
    pick ??= resolved.first;

    return QueryFix(
      fullQuery: full,
      serverQuery: pick.surface,
      changed: layoutFixed || full != typedNorm,
    );
  }

  /// Написання [folded] для сервера — не те, що касир уже набрав
  /// ([typed], воно провалилось), якщо є інше.
  String _pickSurface(String folded, String typed) {
    final list = _surface[folded]!;
    for (final s in list) {
      if (s != typed) return s;
    }
    return list.first;
  }

  /// Знайти слово словника для слова запиту [t] (згорнуте; [typed] — як
  /// набрано): точне, за початком, або з помилками в межах [allowedDistance].
  _Resolved? _resolve(String t, String typed) {
    final exact = _freq[t];
    if (exact != null) {
      return _Resolved(t, _pickSurface(t, typed), exact,
          numeric: _isNumeric(t));
    }
    // Цифри поза словником не виправляємо, але й не блокуємо: «№30» може
    // бути в назві, якої ми ще не бачили. Сервер їх знайде як підрядок.
    if (_isNumeric(t)) return _Resolved(t, t, 1 << 20, numeric: true);

    final allowed = t.length >= 2 ? allowedDistance(t.length) : 0;
    _Resolved? best;
    var bestDist = 1 << 20;
    _freq.forEach((word, freq) {
      int dist;
      if (t.length >= 2 && word.length > t.length && word.startsWith(t)) {
        dist = 0; // початок слова — як точний збіг
      } else if (allowed == 0) {
        return;
      } else {
        final lenDiff = word.length - t.length;
        if (lenDiff < -allowed) return;
        dist = osaDistance(t, word, max: allowed);
        // Початок довшого слова з помилкою.
        if (dist > allowed && lenDiff > allowed) {
          dist = osaDistance(t, word.substring(0, t.length), max: allowed);
        }
        if (dist > allowed) return;
      }
      if (best == null ||
          dist < bestDist ||
          (dist == bestDist && freq > best!.freq)) {
        best = _Resolved(word, _pickSurface(word, typed), freq);
        bestDist = dist;
      }
    });
    return best;
  }

  static bool _isNumeric(String t) => RegExp(r'\d').hasMatch(t);
}

class _Entry {
  const _Entry({required this.name, this.nameUkr, this.top = false});
  final String name;
  final String? nameUkr;
  final bool top;
}

class _Resolved {
  const _Resolved(this.folded, this.surface, this.freq, {this.numeric = false});
  final String folded;
  final String surface;
  final int freq;
  final bool numeric;
}

/// Виправлений запит.
class QueryFix {
  const QueryFix({
    required this.fullQuery,
    required this.serverQuery,
    required this.changed,
  });

  /// Усі слова у написанні з назв — за ним звужуємо відповідь сервера і
  /// показуємо касиру «показано за …».
  final String fullQuery;

  /// Одне найселективніше слово — саме його шлемо серверу.
  final String serverQuery;

  /// Чи відрізняється від набраного (інакше підказку не показуємо).
  final bool changed;
}
