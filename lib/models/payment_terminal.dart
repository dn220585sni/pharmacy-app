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

  /// Розпарсити відповідь `GetTermBank` → лише **налаштовані** термінали
  /// (з непорожнім `kodterm`; порожні слоти типів банків відкидаємо).
  /// Основний — першим у списку.
  static List<PaymentTerminal> listFromResponse(dynamic data) {
    final raw = (data is Map) ? data['Terminals'] : null;
    if (raw is! List) return const [];
    final terminals = raw
        .whereType<Map<String, dynamic>>()
        .map(PaymentTerminal.fromJson)
        .where((t) => t.kodterm.isNotEmpty)
        .toList();
    // Основний — першим (стабільно для решти).
    terminals.sort((a, b) => (b.isMain ? 1 : 0).compareTo(a.isMain ? 1 : 0));
    return List.unmodifiable(terminals);
  }

  /// Назва для UI: опис, інакше банк, інакше код.
  String get displayName =>
      name.isNotEmpty ? name : (bank.isNotEmpty ? bank : bankCode);

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
