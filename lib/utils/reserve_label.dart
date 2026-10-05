/// Підпис резерву «ПРІЗВИЩЕ 0XXXXXXXXX» — за ним клієнта шукають, коли
/// прийде (вимога як у Єврофармі, Микола 05.10.2026). Такий самий вигляд
/// мають старі резерви в полі `rezerv` GetNaklKas («ЖУК 0978288888»).
library;

final _letter = RegExp(r"[A-Za-zА-Яа-яІіЇїЄєҐґЁёЪъЫыЭэ]");

/// Скільки літер у прізвищі (пробіли, дефіси, апострофи не рахуються).
int reserveLetterCount(String surname) => _letter.allMatches(surname).length;

/// Прізвище придатне: щонайменше 3 літери.
bool isValidReserveSurname(String surname) =>
    reserveLetterCount(surname) >= 3;

/// Український мобільний у вигляді `0XXXXXXXXX` або `null`, якщо номер не
/// впізнано. Приймає «097 828 88 88», «+380978288888», «380978288888».
String? normalizeReservePhone(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('380')) return '0${d.substring(3)}';
  if (d.length == 10 && d.startsWith('0')) return d;
  if (d.length == 9) return '0$d';
  return null;
}

/// Готовий підпис для накладної.
String buildReserveLabel(String surname, String phone10) =>
    '${surname.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase()} $phone10';
