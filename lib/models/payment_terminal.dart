import 'package:flutter/foundation.dart';

/// Платіжний термінал аптеки (з `GetTermBank`).
///
/// Основний (`isMain`) привʼязаний до касового місця; решта — резервні:
/// фармацевт може обрати інший у разі поломки основного.
@immutable
class PaymentTerminal {
  /// Код терміналу (ідентифікатор), напр. "963", "1103".
  final String kodterm;

  /// Опис: каса + адреса (напр. "КАССА 2, Шевченко б-р, 71").
  final String name;

  /// Банк (`teg`): "PrivatBank", "Oschad".
  final String bank;

  /// Тип/банк-код (`name2`): "PRIVAT", "OSHAD", "PUMB"…
  final String bankCode;

  /// Основний термінал касового місця (`main == "1"`).
  final bool isMain;

  const PaymentTerminal({
    required this.kodterm,
    required this.name,
    required this.bank,
    required this.bankCode,
    required this.isMain,
  });

  factory PaymentTerminal.fromJson(Map<String, dynamic> j) => PaymentTerminal(
        kodterm: j['kodterm']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        bank: j['teg']?.toString() ?? '',
        bankCode: j['name2']?.toString() ?? '',
        isMain: j['main']?.toString() == '1',
      );

  /// Розпарсити відповідь `GetTermBank` → налаштовані термінали, **дедупльовані
  /// за `kodterm`** (один термінал = один контрагент). При дублі лишаємо кращий:
  /// основний > з описом (`name`) > перший. Основний — першим у списку.
  static List<PaymentTerminal> listFromResponse(dynamic data) {
    final raw = (data is Map) ? data['Terminals'] : null;
    if (raw is! List) return const [];

    final byKod = <String, PaymentTerminal>{};
    for (final t in raw
        .whereType<Map<String, dynamic>>()
        .map(PaymentTerminal.fromJson)
        .where((t) => t.kodterm.isNotEmpty)) {
      final existing = byKod[t.kodterm];
      byKod[t.kodterm] = existing == null ? t : _preferred(existing, t);
    }

    final terminals = byKod.values.toList()
      ..sort((a, b) => (b.isMain ? 1 : 0).compareTo(a.isMain ? 1 : 0));
    return List.unmodifiable(terminals);
  }

  /// Кращий із двох записів одного `kodterm`: основний > з описом > перший.
  static PaymentTerminal _preferred(PaymentTerminal a, PaymentTerminal b) {
    if (a.isMain != b.isMain) return a.isMain ? a : b;
    if (a.name.isNotEmpty != b.name.isNotEmpty) return a.name.isNotEmpty ? a : b;
    return a;
  }

  /// Назва для UI: опис; для «голих» записів — «тип · №код» (напр. «MONOPART · №1665»).
  String get displayName {
    if (name.isNotEmpty) return name;
    if (bank.isNotEmpty) return bank;
    return '$bankCode · №$kodterm';
  }

  @override
  bool operator ==(Object other) =>
      other is PaymentTerminal &&
      other.kodterm == kodterm &&
      other.name == name &&
      other.bank == bank &&
      other.bankCode == bankCode &&
      other.isMain == isMain;

  @override
  int get hashCode => Object.hash(kodterm, name, bank, bankCode, isMain);

  @override
  String toString() => 'PaymentTerminal($kodterm, $bank, main=$isMain)';
}
