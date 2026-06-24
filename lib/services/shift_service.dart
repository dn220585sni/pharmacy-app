import 'package:flutter/foundation.dart';
import '../models/cash_operation.dart';
import '../models/money.dart';
import '../models/shift_state.dart';
import 'api_config.dart';
import 'cache_api_client.dart';
import 'cash_service.dart';
import 'prro_service.dart';

/// Результат перевірки потреби службового внесення (ProvSumZOtchet).
class ServiceDepositCheck {
  /// Чи потрібне службове внесення (ExVnos != 1).
  final bool needed;

  /// Залишок з останнього Z-звіту (SumZZvit) — для передзаповнення.
  final Money carryover;

  const ServiceDepositCheck({required this.needed, required this.carryover});
}

/// Сервіс робочої зміни.
///   startShift → OPEN_SHIFT (+ авто-Z за вчора) + службове внесення (SaveSumDay);
///   closeShift → Z-звіт у ПРРО (zReport) + фіксація в БД Caché (ZRep);
///   checkServiceDeposit → ProvSumZOtchet (залишок + чи потрібне внесення).
/// Підсумки завершення зміни поки 0 (TODO: підтягнути з xReport).
class ShiftService {
  static ShiftState _state = const ShiftState(isOpen: false);

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

  /// Почати зміну: OPEN_SHIFT (з авто-Z за вчора) + службове внесення [deposit]
  /// (SaveSumDay — запис у Caché). Повертає `true` при успіху.
  static Future<bool> startShift(Money deposit) async {
    if (ApiConfig.useMock) {
      _state = ShiftState(
        isOpen: true,
        openedAt: DateTime.now(),
        carryover: deposit,
        cashInBox: deposit + Money.fromHryvnia(3200),
        cashlessTotal: Money.fromHryvnia(5750),
        checksCount: 18,
      );
      return true;
    }
    // 1. Відкрити зміну на РРО. Якщо стара зміна висить (не закрита за вчора /
    // вже відкрита) → авто-Z і відкрити знову (старт нового дня = нова зміна).
    var open = await PrroService.openShift();
    final err = open.error ?? '';
    if (!open.success &&
        (err.contains('не закрили зміну') || err.contains('вже відкрита'))) {
      debugPrint('ShiftService: авто-Z старої зміни перед відкриттям');
      final autoZ = await PrroService.zReport();
      if (autoZ.success) await _fixZReportInDb();
      open = await PrroService.openShift();
    }
    if (!open.success) {
      debugPrint('ShiftService startShift: OPEN_SHIFT FAIL: ${open.error}');
      return false;
    }
    // 2. Службове внесення — запис операції в Caché (SaveSumDay), morning-причина.
    final reasons = await CashService.getReasons(CashDirection.cashIn);
    final reason = morningReason(reasons)?.name ?? 'Служебное внесение';
    await CashService.saveOperation(
        direction: CashDirection.cashIn, reason: reason, sum: deposit);
    _state = ShiftState(isOpen: true, openedAt: DateTime.now(), carryover: deposit);
    debugPrint('ShiftService: зміну відкрито (OPEN_SHIFT + службове внесення '
        '${deposit.format()}, причина="$reason")');
    return true;
  }

  /// Закрити зміну — Z-звіт у ПРРО, потім фіксація операції в БД Caché (ZRep).
  /// Повертає результат ПРРО (фіскально значущий крок).
  static Future<PrroResult> closeShift() async {
    if (ApiConfig.useMock) {
      _state = const ShiftState(isOpen: false);
      return const PrroResult(success: true);
    }
    final r = await PrroService.zReport();
    if (r.success) {
      _state = const ShiftState(isOpen: false);
      await _fixZReportInDb();
    }
    debugPrint('ShiftService: closeShift ${r.success ? "OK" : "FAIL: ${r.error}"}');
    return r;
  }

  /// Зафіксувати Z-звіт у БД Caché (`ZRep`) — викликати ПІСЛЯ успішного Z у ПРРО.
  /// Best-effort: збій фіксації не скасовує вже зроблений у ПРРО Z-звіт,
  /// лише логуємо (за потреби — ретрай окремо).
  static Future<void> _fixZReportInDb() async {
    try {
      final r = await CacheApiClient().call('ZRep');
      debugPrint('ShiftService: ZRep '
          '${r.isOk ? "OK (${r.result})" : "FAIL: ${r.result}"}');
    } catch (e) {
      debugPrint('ShiftService: ZRep ERROR: $e');
    }
  }
}
