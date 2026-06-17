import 'package:flutter/foundation.dart';
import '../models/money.dart';
import '../models/shift_state.dart';

/// МОК сервісу зміни (UI-фаза).
///
/// Згодом методи викличуть реальні операції ПРРО:
///   startShift → PrroService.openShift() + службове внесення (deposit);
///   closeShift → PrroService.zReport();
/// а дані (залишок, підсумки) прийдуть з ПРРО/Caché. Поки — синтетичні.
class ShiftService {
  // Стартовий мок: зміна закрита, є залишок попереднього дня, вчора не закрито
  // (щоб показати банер про авто-Z у діалозі старту).
  static ShiftState _state = ShiftState(
    isOpen: false,
    carryover: Money.fromHryvnia(1250),
    prevZPending: true,
  );

  static ShiftState get state => _state;

  /// Почати зміну зі службовим внесенням [deposit]. (МОК)
  static Future<ShiftState> startShift(Money deposit) async {
    await Future.delayed(const Duration(milliseconds: 300)); // імітація запиту
    _state = ShiftState(
      isOpen: true,
      openedAt: DateTime.now(),
      carryover: deposit,
      // МОК-підсумки для демонстрації діалогу завершення:
      cashInBox: deposit + Money.fromHryvnia(3200),
      cashlessTotal: Money.fromHryvnia(5750),
      checksCount: 18,
    );
    debugPrint('ShiftService(MOCK): зміну відкрито, внесення=${deposit.format()}');
    return _state;
  }

  /// Закрити зміну (Z-звіт). (МОК)
  static Future<void> closeShift() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _state = ShiftState(
      isOpen: false,
      carryover: Money.fromHryvnia(1250),
      prevZPending: false,
    );
    debugPrint('ShiftService(MOCK): зміну закрито (Z-звіт)');
  }
}
