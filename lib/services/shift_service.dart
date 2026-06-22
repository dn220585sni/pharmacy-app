import 'package:flutter/foundation.dart';
import '../models/money.dart';
import '../models/shift_state.dart';
import 'api_config.dart';
import 'cache_api_client.dart';

/// Результат перевірки потреби службового внесення (ProvSumZOtchet).
class ServiceDepositCheck {
  /// Чи потрібне службове внесення (ExVnos != 1).
  final bool needed;

  /// Залишок з останнього Z-звіту (SumZZvit) — для передзаповнення.
  final Money carryover;

  const ServiceDepositCheck({required this.needed, required this.carryover});
}

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

  /// Перевірити, чи потрібне службове внесення на старті зміни, і отримати
  /// залишок з останнього Z-звіту (ProvSumZOtchet). Реальний бекенд.
  static Future<ServiceDepositCheck> checkServiceDeposit() async {
    if (ApiConfig.useMock) {
      return ServiceDepositCheck(needed: true, carryover: Money.fromHryvnia(1250));
    }
    try {
      final r = await CacheApiClient().call('ProvSumZOtchet');
      if (r.isOk) {
        final carryover = Money.parse(r.data['SumZZvit']?.toString() ?? '');
        final needed = (r.data['ExVnos']?.toString() ?? '0') != '1';
        debugPrint('ShiftService: ProvSumZOtchet SumZZvit=${carryover.format()} '
            'needed=$needed');
        return ServiceDepositCheck(needed: needed, carryover: carryover);
      }
      debugPrint('ShiftService ProvSumZOtchet FAIL: ${r.result}');
    } catch (e) {
      debugPrint('ShiftService ProvSumZOtchet ERROR: $e');
    }
    // На помилку — краще показати діалог (із 0), ніж мовчки пропустити старт.
    return const ServiceDepositCheck(needed: true, carryover: Money.zero);
  }

  /// Почати зміну зі службовим внесенням [deposit]. (МОК — фіскальну дію
  /// SaveSumDay/OPEN_SHIFT підключимо після уточнення Q9.)
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
