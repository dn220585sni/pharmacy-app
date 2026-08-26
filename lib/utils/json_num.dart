/// Терпимі парсери чисел із JSON-відповідей серверів.
///
/// ⚠️ Навіщо: і ПРРО, і Caché віддають числа то числом, то рядком — залежно
/// від поля і від версії сервісу. Жорсткий каст `as num?` на такому полі кидає
/// `type 'String' is not a subtype of type 'num?'` і валить розбір УСІЄЇ
/// відповіді, а не одного поля. Двічі за один день (2026-08-26) це коштувало:
/// `local_number` рядком у `checks_list` X-звіту → звірка дублікатів A1 мовчки
/// не працювала; той самий каст у журналі продажу → падав розбір запису.
///
/// Правило: числа з мережі читати ТІЛЬКИ через ці функції.
library;

/// `0.5`, `"0.5"`, `"0,5"` (десяткова кома), `null`, сміття → `double?`.
double? flexDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

/// `597`, `"597"`, `"597.0"`, `null`, сміття → `int?`.
int? flexInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) {
    return int.tryParse(v.trim()) ?? flexDouble(v)?.toInt();
  }
  return null;
}
