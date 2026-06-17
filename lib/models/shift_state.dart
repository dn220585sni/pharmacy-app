import 'money.dart';

/// Стан робочої зміни каси.
///
/// Поки що наповнюється мок-сервісом ([ShiftService]); згодом — реальні дані
/// з ПРРО/Caché (залишок, підсумки, ознака незакритого Z за вчора).
class ShiftState {
  final bool isOpen;
  final DateTime? openedAt;

  /// Залишок з попереднього дня — пропонована сума службового внесення.
  final Money carryover;

  /// Вчора не закрито Z-звітом → при старті буде авто-Z за минулий день.
  final bool prevZPending;

  /// Поточні підсумки зміни (для діалогу завершення).
  final Money cashInBox;
  final Money cashlessTotal;
  final int checksCount;

  const ShiftState({
    required this.isOpen,
    this.openedAt,
    this.carryover = Money.zero,
    this.prevZPending = false,
    this.cashInBox = Money.zero,
    this.cashlessTotal = Money.zero,
    this.checksCount = 0,
  });

  /// Тривалість відкритої зміни (null якщо закрита).
  Duration? get duration =>
      openedAt == null ? null : DateTime.now().difference(openedAt!);
}
