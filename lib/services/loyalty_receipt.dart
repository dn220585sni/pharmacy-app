/// Блок «ПРОГРАМА ЛОЯЛЬНОСТI» для коментаря ПРРО-чека.
///
/// Порт MUMPS-шаблону Каті (2026-07-17): маскований телефон АБО картка,
/// нараховані/заощаджені бонуси + баланс; offline (Спарта недоступна) → `***`.
/// Формує клієнт із результату Sparta `tx/order` (`balanceEarn`/`Burn`/`After`)
/// і кладе в поле чека — це ОКРЕМО від позиції «Програма лояльності» (списання).
class LoyaltyReceipt {
  static String build({
    String? phone,
    String? card,
    required bool online,
    double earn = 0,
    double burn = 0,
    double after = 0,
  }) {
    final b = StringBuffer();
    b.writeln('__________________________________________');
    b.writeln('   ПРОГРАМА ЛОЯЛЬНОСТI');
    if (phone == null || phone.isEmpty) {
      b.writeln('Картка:     ${card ?? ''}');
    } else {
      b.writeln('Телефон:    ${_maskPhone(phone)}');
    }
    if (!online) {
      b.writeln('Нараховано: ***');
      b.writeln('Баланс:     ***');
    } else {
      b.writeln('Нараховано: ${_money(earn)}');
      if (burn != 0) b.writeln('Заощаджено: ${_money(burn)}');
      b.writeln('Баланс:     ${_money(after)}');
    }
    return b.toString();
  }

  /// Маскування як у шаблоні: `$e(phone,4,8)**$e(phone,11,13)`.
  /// Для `+380671234567` → `06712**567`. Коротший номер — як є.
  static String _maskPhone(String p) {
    if (p.length < 13) return p;
    return '${p.substring(3, 8)}**${p.substring(10, 13)}';
  }

  /// `12.5` → `12,50` (2 знаки, крапка → кома).
  static String _money(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
}
