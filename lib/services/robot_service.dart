import 'api_config.dart';
import 'cache_api_client.dart';
import 'fiscal_log.dart';

/// Результат команди роботу: [ok] і текст сервера (для помилки — причина).
class RobotResult {
  final bool ok;
  final String message;
  const RobotResult(this.ok, this.message);
}

/// Команди аптечного робота (Caché, Катя 13.10 — Google-док специфікації,
/// розділ після GetGlobParam). Усі — з sessionId (додає [CacheApiClient]).
/// Кожна команда пишеться в журнал: це дії з фізичним обладнанням.
class RobotService {
  static final _api = CacheApiClient();

  static Future<RobotResult> _run(String service, String what,
      [Map<String, String>? params]) async {
    if (ApiConfig.useMock) return const RobotResult(false, 'демо-режим');
    try {
      final r = await _api.call(service, params: params);
      final msg = r.result.toString().trim();
      FiscalLog.log('РОБОТ $service ($what): '
          '${r.isOk ? "OK" : "FAIL"}${msg.isNotEmpty ? " — $msg" : ""}');
      return RobotResult(r.isOk, msg);
    } catch (e) {
      FiscalLog.log('РОБОТ $service ($what): помилка $e');
      return RobotResult(false, '$e');
    }
  }

  /// Коригування кількості s-коду в комірці: `ModifyOstRobot`,
  /// oper = add / minus, [qty] — додатна кількість упаковок.
  static Future<RobotResult> modifyCell({
    required String skod,
    required String cell,
    required int delta,
  }) =>
      _run('ModifyOstRobot', 'SKod=$skod $cell ${delta > 0 ? "+" : ""}$delta', {
        'SKod': skod,
        'oper': delta > 0 ? 'add' : 'minus',
        'cell': cell,
        'qty': '${delta.abs()}',
      });

  /// Привезти товар: `MoveSKod`.
  static Future<RobotResult> moveSkod(String skod, int qty) =>
      _run('MoveSKod', 'SKod=$skod × $qty', {'SKod': skod, 'qty': '$qty'});

  /// Привезти весь кошик (серверний сеанс): `MoveBasket`.
  static Future<RobotResult> moveBasket() => _run('MoveBasket', 'кошик');

  /// Погасити чергу (індикатор черги): `ClearQueryRobotFront`.
  static Future<RobotResult> clearQueue() =>
      _run('ClearQueryRobotFront', 'черга');

  /// Перезапуск передньої стінки: `RestartFrontRobot`.
  static Future<RobotResult> restartFront() =>
      _run('RestartFrontRobot', 'передня стінка');
}
