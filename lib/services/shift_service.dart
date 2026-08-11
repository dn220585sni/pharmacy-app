import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/cash_operation.dart';
import '../models/money.dart';
import '../models/shift_state.dart';
import 'api_config.dart';
import 'cache_api_client.dart';
import 'cash_service.dart';
import 'fiscal_log.dart';
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

  /// Разове відновлення стану зміни з РРО (дедуплікується між викликами).
  static Future<void>? _restoreFuture;
  static Future<void> ensureRestored() => _restoreFuture ??= _restoreFromServer();

  /// Відновити стан зміни з РРО (xReport) на старті. Якщо на РРО відкрита
  /// СЬОГОДНІШНЯ зміна (рестарт/краш посеред дня) — вважаємо її відкритою:
  /// (а) не показуємо повторний старт зі службовим внесенням, (б) не робимо
  /// помилковий авто-Z, (в) при виході пропонуємо Z. Зміна з ПОПЕРЕДНЬОЇ доби
  /// лишає стан закритим — тоді звичайний старт зробить авто-Z за вчора.
  static Future<void> _restoreFromServer() async {
    if (ApiConfig.useMock) return;
    try {
      final x = await PrroService.xReport(includeChecks: false);
      if (x == null || !x.shiftOpen) {
        _state = const ShiftState(isOpen: false);
        return;
      }
      // Дата відкриття — з `from_date` (shift_duration каса віддає 0). Фолбек на
      // shift_duration лишаємо про всяк, але зазвичай працює from_date.
      final openedAt =
          x.openedAt ?? _estimateOpenedAt(x.shiftDurationMinutes);
      // Невідома дата → трактуємо як СЬОГОДНІ (безпечніше, ніж ризикнути авто-Z
      // сьогоднішньої зміни).
      final today = openedAt == null || _isSameDay(openedAt, DateTime.now());
      if (today) {
        _state = ShiftState(
          isOpen: true,
          openedAt: openedAt ?? DateTime.now(),
          cashInBox: Money.fromHryvnia(x.cashInBox),
          checksCount: x.ordersCount,
        );
        debugPrint('ShiftService: відновлено відкриту зміну з xReport '
            '(opened≈$openedAt, чеків=${x.ordersCount})');
      } else {
        _state = const ShiftState(isOpen: false);
        debugPrint('ShiftService: РРО має відкриту зміну з попередньої доби '
            '(opened≈$openedAt) — старт зробить авто-Z');
      }
    } catch (e) {
      debugPrint('ShiftService restore ERROR: $e');
    }
  }

  static DateTime? _estimateOpenedAt(int? durationMinutes) =>
      durationMinutes == null
          ? null
          : DateTime.now().subtract(Duration(minutes: durationMinutes));

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Перевірити, чи потрібне службове внесення на старті зміни, і отримати
  /// залишок з останнього Z-звіту (ProvSumZOtchet). Реальний бекенд.
  static Future<ServiceDepositCheck> checkServiceDeposit() async {
    if (ApiConfig.useMock) {
      return ServiceDepositCheck(needed: true, carryover: Money.fromHryvnia(1250));
    }
    // Пропонована розмінна монета = готівка в касі на момент останнього Z-звіту
    // (збережено в closeShift; CashDesk `cash_in_box`). Фармацевт може змінити.
    final carryover = await _loadCarryover() ?? Money.zero;
    try {
      // ProvSumZOtchet — лише щоб зрозуміти, чи внесення взагалі потрібне (ExVnos).
      final r = await CacheApiClient().call('ProvSumZOtchet');
      if (r.isOk) {
        final needed = (r.data['ExVnos']?.toString() ?? '0') != '1';
        debugPrint('ShiftService: ProvSumZOtchet ExVnos="${r.data['ExVnos']}" '
            'needed=$needed, розмінна(Z)=${carryover.format()}');
        return ServiceDepositCheck(needed: needed, carryover: carryover);
      }
      debugPrint('ShiftService ProvSumZOtchet FAIL: ${r.result}');
    } catch (e) {
      debugPrint('ShiftService ProvSumZOtchet ERROR: $e');
    }
    // На помилку — краще показати діалог (з розмінною), ніж пропустити старт.
    return ServiceDepositCheck(needed: true, carryover: carryover);
  }

  /// Підтягнути реальні підсумки відкритої зміни з ПРРО xReport (готівка в касі,
  /// к-сть чеків) у `_state`. Викликати перед показом діалогу завершення зміни —
  /// інакше поле «Готівка в касі» показує 0 (продажі не оновлюють `_state`).
  static Future<void> refreshTotals() async {
    if (ApiConfig.useMock || !_state.isOpen) return;
    try {
      final x = await PrroService.xReport(includeChecks: false);
      if (x == null) return;
      _state = ShiftState(
        isOpen: _state.isOpen,
        openedAt: _state.openedAt,
        carryover: _state.carryover,
        prevZPending: _state.prevZPending,
        cashInBox: Money.fromHryvnia(x.cashInBox),
        cashlessTotal: _state.cashlessTotal, // xReport не дає прямого розбиття
        checksCount: x.ordersCount,
      );
      debugPrint('ShiftService: refreshTotals cashInBox=${x.cashInBox} '
          'checks=${x.ordersCount}');
    } catch (e) {
      debugPrint('ShiftService refreshTotals ERROR: $e');
    }
  }

  /// Свіжо перевірити на РРО, чи зміна відкрита (`xReport`), і синхронізувати
  /// локальний `_state`. Для перевірки ПЕРЕД ВИХОДОМ: локальний стан міг
  /// застаріти (рестарт, коли відновлення на старті не спрацювало / було
  /// закешоване), і тоді при виході не пропонувався Z для відкритої зміни.
  static Future<bool> isShiftOpenOnServer() async {
    if (ApiConfig.useMock) return _state.isOpen;
    try {
      final x = await PrroService.xReport(includeChecks: false);
      if (x == null) return _state.isOpen;
      if (x.shiftOpen && !_state.isOpen) {
        _state = ShiftState(
          isOpen: true,
          openedAt: x.openedAt,
          cashInBox: Money.fromHryvnia(x.cashInBox),
          checksCount: x.ordersCount,
        );
      } else if (!x.shiftOpen && _state.isOpen) {
        _state = const ShiftState(isOpen: false);
      }
      return x.shiftOpen;
    } catch (e) {
      debugPrint('ShiftService isShiftOpenOnServer ERROR: $e');
      return _state.isOpen;
    }
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
      // Зміна вже відкрита на РРО. Авто-Z ЛИШЕ якщо вона з ПОПЕРЕДНЬОЇ доби
      // (вчорашня незакрита). Якщо сьогоднішня (рестарт посеред дня) — НЕ Z-имо,
      // а приймаємо як відкриту: службове внесення вже зроблено раніше сьогодні.
      final x = await PrroService.xReport(includeChecks: false);
      final openedAt = x?.openedAt ?? _estimateOpenedAt(x?.shiftDurationMinutes);
      final fromPrevDay =
          openedAt != null && !_isSameDay(openedAt, DateTime.now());
      if (fromPrevDay) {
        debugPrint('ShiftService: авто-Z вчорашньої зміни перед відкриттям');
        FiscalLog.log('startShift: зміна з попередньої доби '
            '(відкрита $openedAt) → авто-Z і повторне відкриття');
        final autoZ = await PrroService.zReport();
        if (autoZ.success) await _fixZReportInDb();
        open = await PrroService.openShift();
      } else {
        debugPrint('ShiftService: зміна вже відкрита сьогодні — без Z, '
            'відновлюємо стан');
        FiscalLog.log('startShift: зміна вже відкрита сьогодні '
            '(з $openedAt) → без Z, відновлено стан');
        _state =
            ShiftState(isOpen: true, openedAt: openedAt ?? DateTime.now());
        return true;
      }
    }
    if (!open.success) {
      debugPrint('ShiftService startShift: OPEN_SHIFT FAIL: ${open.error}');
      FiscalLog.log('startShift ПРОВАЛ: ${open.error} '
          '(kind=${open.errorKind}) — каса лишається без зміни');
      return false;
    }
    FiscalLog.log('startShift: зміну відкрито, внесення=${deposit.toHryvnia()}');
    // 2. Службове внесення в ПРРО (CashDesk `/check/service`) — інакше
    // `cash_in_box` у X/Z-звітах не знає про розмінну монету і діалог
    // закриття зміни показує «Готівка в касі: 0». Збій не блокує старт.
    if (deposit.isPositive) {
      final svc = await PrroService.serviceCash(
          isInput: true, sum: deposit.kopiykas / 100);
      if (!svc.success) {
        debugPrint('ShiftService: службове внесення в ПРРО FAIL: ${svc.error}');
      }
    }
    // 3. Службове внесення — запис операції в Caché (SaveSumDay), morning-причина.
    final reasons = await CashService.getReasons(CashDirection.cashIn);
    final reason = morningReason(reasons)?.name ?? 'Служебное внесение';
    await CashService.saveOperation(
        direction: CashDirection.cashIn, reason: reason, sum: deposit);
    _state = ShiftState(isOpen: true, openedAt: DateTime.now(), carryover: deposit);
    debugPrint('ShiftService: зміну відкрито (OPEN_SHIFT + службове внесення '
        '${deposit.format()}, причина="$reason")');
    return true;
  }

  /// Триває закриття (guard від паралельних викликів кнопка+вихід).
  static bool _closing = false;

  /// Закрити зміну — Z-звіт у ПРРО, потім фіксація операції в БД Caché (ZRep).
  /// Повертає результат ПРРО (фіскально значущий крок).
  ///
  /// Ідемпотентний: якщо зміна вже закрита АБО закриття вже виконується — НЕ
  /// робимо повторний Z/ZRep. Інакше кожен зайвий виклик створює ще один запис
  /// «Вынос. Z-отчет» у касовій дисципліні (був баг: потрійний Z на одне закриття).
  static Future<PrroResult> closeShift() async {
    if (!_state.isOpen) {
      debugPrint('ShiftService: closeShift — зміна вже закрита, пропускаємо');
      return const PrroResult(success: true);
    }
    if (_closing) {
      debugPrint('ShiftService: closeShift уже виконується — пропускаємо');
      return const PrroResult(success: true);
    }
    _closing = true;
    try {
      if (ApiConfig.useMock) {
        _state = const ShiftState(isOpen: false);
        return const PrroResult(success: true);
      }
      final r = await PrroService.zReport();
      if (r.success) {
        _state = const ShiftState(isOpen: false);
        await _fixZReportInDb();
        // `cash_in_box` з відповіді Z-звіту = гроші в касі на момент Z = пропонована
        // розмінна монета для НАСТУПНОЇ зміни. Зберігаємо (переживає рестарт).
        final cashAtZ = Money.fromHryvnia(r.cashInBox ?? 0);
        await _persistCarryover(cashAtZ);
        debugPrint('ShiftService: closeShift OK (cashAtZ=${cashAtZ.format()})');
      } else {
        debugPrint('ShiftService: closeShift FAIL: ${r.error}');
      }
      return r;
    } finally {
      _closing = false;
    }
  }

  // ── Перенос розмінної монети (cash_in_box на момент Z) ───────────────────────

  static const _carryoverFile = 'shift_carryover.json';

  static Future<File?> _carryoverPath() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_carryoverFile');
    } catch (_) {
      return null;
    }
  }

  /// Зберегти готівку в касі на момент Z — пропонована розмінна для наступної зміни.
  static Future<void> _persistCarryover(Money m) async {
    final f = await _carryoverPath();
    if (f == null) return;
    try {
      await f.writeAsString(jsonEncode({'kopiykas': m.kopiykas}));
    } catch (e) {
      debugPrint('ShiftService: persist carryover FAIL: $e');
    }
  }

  /// Прочитати збережену розмінну (з останнього Z). null якщо ще не було.
  static Future<Money?> _loadCarryover() async {
    final f = await _carryoverPath();
    if (f == null || !await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final k = (j['kopiykas'] as num?)?.toInt();
      return k != null ? Money.fromKopiykas(k) : null;
    } catch (e) {
      debugPrint('ShiftService: load carryover FAIL: $e');
      return null;
    }
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
