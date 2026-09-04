import 'package:flutter/foundation.dart';
import 'api_config.dart';
import 'cache_api_client.dart';
import 'fiscal_log.dart';

/// Результат перевірки картки — `PANFromBaskets`.
///
/// Правило відповіді за описом Катерини (03.09.2026): «якщо все ок PAN є у
/// відповіді, інакше пусто і Result пише причину». Тобто ознака успіху — це
/// НЕ `Status`, а наявність `PAN`.
class CardCheckResult {
  /// Номер картки, який повернув сервер. Порожньо — перевірку не пройдено.
  final String pan;

  /// Пояснення від сервера. При успіху це просто «Перевірка номера картки».
  final String result;

  const CardCheckResult({required this.pan, required this.result});

  bool get isOk => pan.isNotEmpty;

  @override
  String toString() =>
      isOk ? 'OK pan=${CardCheckService.maskPan(pan)}' : 'ВІДМОВА: $result';
}

/// Перевірка картки на набраному кошику — `PANFromBaskets` (Катерина, 03.09).
///
/// `Kab.Service.cls?ServiceName=PANFromBaskets&sessionId={sessionId}`
/// `&PAN={PAN}&NumNakl={NumNakl}`
/// → `{"Status":"OK","PAN":"405424863","Result":"Перевірка номера картки"}`
///
/// **Призначення** (уточнив Микола, 04.09): перевіряє, чи картка клієнта є
/// карткою **Нацкешбеку**, і якщо так — перевіряє кошик. Тобто одна відповідь
/// покриває два різні висновки: «не та картка» і «картка та, але товар не
/// підходить».
///
/// **Звідки брати PAN.** `Purchase` віддає лише маскований номер
/// («4731XXXXXXXX9838»), і з нього девʼять цифр Катериного прикладу не
/// зібрати. Повний номер БЕЗ списання дає `ReadBonusCard` (ECR 5.22):
/// `{"pan":"6769659308590307","responseCode":"0000"}`. Це єдина операція в
/// протоколі, яка читає картку до оплати.
///
/// ⚠️ **Ніде не викликається.** Відкрито:
///
///   • чи дозволяє ПриватБанк читати звичайну банківську картку через
///     `ReadBonusCard` — метод названий під бонусні;
///   • чи розрізняє `Result` «не Нацкешбек» і «кошик не підходить» — це
///     різні повідомлення для фармацевта: перше нормальне, друге дія;
///   • що робити при відмові: блокувати оплату чи попереджати.
class CardCheckService {
  /// Показати номер картки так, щоб він не осідав у журналі повністю.
  ///
  /// `PANFromBaskets` працює з ПОВНИМ номером — на відміну від усього іншого
  /// в касі, де ми бачимо лише маску від термінала. Повний номер у
  /// незашифрованому журналі на аптечній машині — зайвий ризик, а для
  /// розбору спірних оплат вистачає перших шести й останніх чотирьох.
  static String maskPan(String pan) {
    final d = pan.replaceAll(RegExp(r'\D'), '');
    if (d.length < 12) return '*' * d.length;
    return '${d.substring(0, 6)}${'*' * (d.length - 10)}${d.substring(d.length - 4)}';
  }

  /// [pan] — повний номер картки (див. `ReadBonusCard` вище).
  /// [numNakl] — накладна-сеанс із `SavesgVNakl`.
  static Future<CardCheckResult> check({
    required String pan,
    required String numNakl,
  }) async {
    if (ApiConfig.useMock) {
      return const CardCheckResult(pan: '', result: 'mock: перевірки немає');
    }
    try {
      final r = await CacheApiClient().call('PANFromBaskets', params: {
        'PAN': pan,
        'NumNakl': numNakl,
      });
      final got = r.data['PAN']?.toString().trim() ?? '';
      final why = r.result.isNotEmpty ? r.result : 'без пояснення';
      final out = CardCheckResult(pan: got, result: why);
      // Пишемо в журнал завжди: і відмову, і успіх — до цього повертаються
      // при розборі спірних оплат. Але номер ЛИШЕ маскований: повний у
      // відкритому файлі на аптечній машині нам не потрібен.
      FiscalLog.log('PANFromBaskets (NumNakl=$numNakl, '
          'картка ${maskPan(pan)}): ${out.isOk ? "OK" : "ВІДМОВА — $why"}');
      debugPrint('PANFromBaskets → ${out.isOk ? "OK" : why}');
      return out;
    } catch (e) {
      FiscalLog.log('PANFromBaskets ERROR (NumNakl=$numNakl): $e');
      return CardCheckResult(pan: '', result: 'Немає звʼязку з сервером: $e');
    }
  }
}
