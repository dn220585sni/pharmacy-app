/// Каса зі списку `GetKlient` (Задача 25).
///
/// `{"name":"КАССА 1, Шевченко б-р, 71 (Копійка)","id":"1334"}` — `id` це той
/// самий `KodKli`, який іде параметром у `GetNaklKas`, `SaveSumDay` та інші
/// касові сервіси.
class CashRegister {
  final String id;
  final String name;

  const CashRegister({required this.id, required this.name});

  /// `null` — рядок без id або без назви, показувати таке нема сенсу.
  static CashRegister? fromJson(Map<String, dynamic> j) {
    final id = j['id']?.toString().trim() ?? '';
    final name = j['name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    return CashRegister(id: id, name: name);
  }

  /// Короткий підпис для випадайки.
  ///
  /// У межах однієї аптеки адреса й назва в усіх кас однакові
  /// («КАССА 1, Шевченко б-р, 71 (Копійка)»), тож у списку від них лише шум.
  /// Лишаємо частину до першої коми — але якщо в назві більше однієї дужки,
  /// останню дописуємо: саме нею відрізняється «КАССА 4 (поштомат)».
  ///
  /// Повна назва нікуди не дівається — її показуємо підказкою.
  String get shortName {
    final head = name.split(',').first.trim();
    final groups = RegExp(r'\(([^()]*)\)').allMatches(name).toList();
    if (groups.length < 2) return head.isEmpty ? name : head;
    final tail = groups.last.group(0)!;
    return head.isEmpty ? name : '$head $tail';
  }

  @override
  bool operator ==(Object other) => other is CashRegister && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '$id: $name';
}
