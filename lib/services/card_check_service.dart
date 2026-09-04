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
  String toString() => isOk ? 'OK pan=$pan' : 'ВІДМОВА: $result';
}

/// Перевірка картки на набраному кошику — `PANFromBaskets` (Катерина, 03.09).
///
/// `Kab.Service.cls?ServiceName=PANFromBaskets&sessionId={sessionId}`
/// `&PAN={PAN}&NumNakl={NumNakl}`
/// → `{"Status":"OK","PAN":"405424863","Result":"Перевірка номера картки"}`
///
/// ⚠️ **Ніде не викликається.** Транспорт написано, бо інтерфейс однозначний,
/// але бізнес-правило — ні, і вигадувати його не варто. Відкрито:
///
///   • ЯКА це картка. У нас `PAN` — це маскований номер банківської картки з
///     ECR-термінала («4731XXXXXXXX9838»), а приклад Катерини «405424863» це
///     9 цифр без маски. Тобто або це інша сутність (соціальна картка
///     програми?), або інший формат, або приклад скорочено.
///   • КОЛИ викликати: «при набраній корзині або вже на чеку» — до оплати,
///     після неї, чи в обох точках.
///   • ЩО РОБИТИ при відмові: блокувати оплату чи попереджати.
///
/// Поки на ці три питання немає відповіді, підключати сервіс до потоку
/// продажу не можна: помилка тут коштує заблокованої каси.
class CardCheckService {
  /// [pan] — номер картки у форматі, який очікує сервер (див. відкрите
  /// питання вище). [numNakl] — накладна-сеанс із `SavesgVNakl`.
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
      // Пишемо в журнал завжди: і відмову, і успіх. Картка на чеку — це те,
      // до чого повертаються при розборі спірних оплат.
      FiscalLog.log('PANFromBaskets (NumNakl=$numNakl): $out');
      debugPrint('PANFromBaskets → $out');
      return out;
    } catch (e) {
      FiscalLog.log('PANFromBaskets ERROR (NumNakl=$numNakl): $e');
      return CardCheckResult(pan: '', result: 'Немає звʼязку з сервером: $e');
    }
  }
}
