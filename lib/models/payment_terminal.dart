import 'package:flutter/foundation.dart';

/// Протокол спілкування з платіжним терміналом.
enum TerminalProtocol {
  /// ПриватБанк — пропрієтарний JSON поверх TCP (реалізовано: EcrTerminalClient).
  json,

  /// Ощад — BPOS (legacy COM `ECRCommXLib`). Ще НЕ реалізовано в Dart.
  bpos,

  /// Не ECR-термінал (LiqPay/QR/частинами) або протокол невідомий.
  unknown,
}

/// Платіжний термінал аптеки (з `GetTermBank`).
///
/// Основний (`isMain`) привʼязаний до касового місця; решта — резервні:
/// фармацевт може обрати інший у разі поломки основного.
///
/// ⚠️ `kodterm` — код **банку/еквайра** (йде в `KodKli` накладної), а НЕ
/// ідентифікатор пристрою: кілька фізичних терміналів можуть мати один
/// `kodterm` і різні `termIP`. Фізичний пристрій визначає `termIP:termPort`.
@immutable
class PaymentTerminal {
  /// Код терміналу/еквайра (для `KodKli` накладної), напр. "963", "1103".
  final String kodterm;

  /// Опис: каса + адреса (напр. "КАССА 2, Шевченко б-р, 71").
  final String name;

  /// Банк (`teg`): "PrivatBank", "Oschad".
  final String bank;

  /// Тип/банк-код (`name2`): "PRIVAT", "OSHAD", "PUMB"…
  final String bankCode;

  /// Основний термінал касового місця (`main == "1"`).
  final bool isMain;

  /// IP фізичного терміналу (`termIP`). Порожній — не ECR-пристрій.
  final String termIP;

  /// TCP-порт терміналу (`termPort`), напр. "2000".
  final String termPort;

  /// Мова терміналу (`termLang`).
  final String termLang;

  const PaymentTerminal({
    required this.kodterm,
    required this.name,
    required this.bank,
    required this.bankCode,
    required this.isMain,
    this.termIP = '',
    this.termPort = '',
    this.termLang = '',
  });

  factory PaymentTerminal.fromJson(Map<String, dynamic> j) => PaymentTerminal(
        kodterm: j['kodterm']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        bank: j['teg']?.toString() ?? '',
        bankCode: j['name2']?.toString() ?? '',
        isMain: j['main']?.toString() == '1',
        termIP: j['termIP']?.toString() ?? '',
        termPort: j['termPort']?.toString() ?? '',
        termLang: j['termLang']?.toString() ?? '',
      );

  /// Чи можна фізично під'єднатись (є адреса) — тобто це ECR-термінал, на який
  /// можна відправити суму. Інакше це просто спосіб оплати/еквайр-контракт.
  bool get canConnect => termIP.isNotEmpty && termPort.isNotEmpty;

  /// Порт числом (0 — некоректний/відсутній).
  int get portNumber => int.tryParse(termPort.trim()) ?? 0;

  /// Протокол — за банком (`teg`, фолбек `name2`).
  TerminalProtocol get protocol {
    final tag = '$bank $bankCode'.toLowerCase();
    if (tag.contains('privatqr')) return TerminalProtocol.unknown;
    if (tag.contains('privat')) return TerminalProtocol.json;
    if (tag.contains('oschad') || tag.contains('oshad')) {
      return TerminalProtocol.bpos;
    }
    return TerminalProtocol.unknown;
  }

  /// Чи підтримується поточною реалізацією (JSON). BPOS — окрема пізніша фаза.
  bool get isSupported => canConnect && protocol == TerminalProtocol.json;

  /// Розпарсити відповідь `GetTermBank`.
  ///
  /// Групуємо за `kodterm`; **фізичні термінали (з `termIP:termPort`) НЕ
  /// зливаємо** — це різні пристрої навіть за однакового `kodterm` (напр. КАСА 1
  /// і КАСА 3 обидві PRIVAT `1103`, але різні IP; злиття губило б резервний).
  /// «Голі» записи (без адреси) — це еквайр/спосіб оплати: якщо для цього
  /// `kodterm` уже є фізичний термінал, голий запис відкидаємо як дублікат,
  /// інакше лишаємо один найкращий. Основний — першим у списку.
  static List<PaymentTerminal> listFromResponse(dynamic data) {
    final raw = (data is Map) ? data['Terminals'] : null;
    if (raw is! List) return const [];

    final all = raw
        .whereType<Map<String, dynamic>>()
        .map(PaymentTerminal.fromJson)
        .where((t) => t.kodterm.isNotEmpty)
        .toList();

    // Фізичні пристрої — унікальні за kodterm+IP+порт.
    final physical = <String, PaymentTerminal>{};
    // Голі записи — по одному на kodterm.
    final bare = <String, PaymentTerminal>{};

    for (final t in all) {
      if (t.canConnect) {
        final key = '${t.kodterm}@${t.termIP}:${t.termPort}';
        final existing = physical[key];
        physical[key] = existing == null ? t : _preferred(existing, t);
      } else {
        final existing = bare[t.kodterm];
        bare[t.kodterm] = existing == null ? t : _preferred(existing, t);
      }
    }

    // Голий запис зайвий, якщо для цього kodterm є фізичний термінал.
    final withDevice = physical.values.map((t) => t.kodterm).toSet();
    bare.removeWhere((kod, _) => withDevice.contains(kod));

    final terminals = [...physical.values, ...bare.values]
      ..sort((a, b) => (b.isMain ? 1 : 0).compareTo(a.isMain ? 1 : 0));
    return List.unmodifiable(terminals);
  }

  /// Лише ECR-термінали, на які можна відправити суму (є адреса).
  static List<PaymentTerminal> connectable(List<PaymentTerminal> list) =>
      List.unmodifiable(list.where((t) => t.canConnect));

  /// Кращий із двох однакових записів: основний > з описом > перший.
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
      other.isMain == isMain &&
      other.termIP == termIP &&
      other.termPort == termPort &&
      other.termLang == termLang;

  @override
  int get hashCode => Object.hash(
      kodterm, name, bank, bankCode, isMain, termIP, termPort, termLang);

  @override
  String toString() => 'PaymentTerminal($kodterm, $bank, main=$isMain, '
      '${canConnect ? '$termIP:$termPort' : 'no-device'})';
}
