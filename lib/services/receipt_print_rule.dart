import '../models/internet_order.dart';

/// Чому чек друкується — або чому ні.
///
/// Причина потрібна не для краси: її видно у вікні здачі (фармацевту й
/// відеоспостереженню) і в журналі, коли доведеться пояснювати, чому
/// конкретний чек не роздрукувався.
enum PrintReason {
  /// Реімбурсація, соцпроєкт або страховий — папір потрібен не клієнту,
  /// а НСЗУ / програмі / страховій. Друкуємо завжди.
  mandatoryProgram,

  /// Інтернет-замовлення: клієнт отримує чек каналом магазину.
  internetOrder,

  /// Анкета Спарти: «Получать эл-й чек» = `no`.
  customerOptedOut,

  /// Анкета дозволяє електронний чек — типовий випадок (62–64 % за даними
  /// Андрія на 17.08.2026).
  customerElectronic,

  /// Анкети немає взагалі — продаж без картки лояльності (ЛАЙК).
  noAnketa,
}

extension PrintReasonLabel on PrintReason {
  String get label => switch (this) {
        PrintReason.mandatoryProgram => 'Програмний чек — друк обовʼязковий',
        PrintReason.internetOrder => 'Інтернет-замовлення — чек іде каналом магазину',
        PrintReason.customerOptedOut => 'Клієнт відмовився від електронного чека',
        PrintReason.customerElectronic => 'Електронний чек сформовано',
        PrintReason.noAnketa => 'Клієнт без анкети — друкуємо папір',
      };
}

class PrintDecision {
  final bool shouldPrint;
  final PrintReason reason;
  const PrintDecision(this.shouldPrint, this.reason);

  @override
  String toString() => '${shouldPrint ? "друк" : "електронний"} (${reason.name})';

  @override
  bool operator ==(Object other) =>
      other is PrintDecision &&
      other.shouldPrint == shouldPrint &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(shouldPrint, reason);
}

/// Друкувати паперовий чек чи показати електронний.
///
/// Джерело — уточнення Андрія Попова (03.09.2026). Назва поля анкети збиває з
/// пантелику: «Получать эл-й чек» **≠ `no`** означає, що чек НЕ друкується, а
/// факт електронної реєстрації показується у вікні здачі. Друк — це виняток:
/// липень 2026 — 64 % чеків без друку, серпень на 17.08 — 62 %.
///
/// Пріоритет умов (згори вниз, перша спрацьована виграє):
///
/// 1. **Реімбурсація / соцпроєкт / страховий → ДРУК.** Андрій підтвердив
///    04.09.2026: «логика верная». Заразом пояснив, чому конфлікту насправді
///    майже немає: реімбурсація і страхові бувають ІЗ у дуже невеликому
///    відсотку випадків, а по соцпроєктах ІЗ не буває взагалі. Тобто пріоритет
///    спрацьовує рідко, але коли спрацьовує — саме так.
///
///    Перелік соцпроєктів зберігається в характеристиці аптеки **3782**,
///    значення через кому. Ми його поки не читаємо — на правило це не впливає.
/// 2. **ІЗ → НЕ друкуємо.** Підтверджено Миколою 03.09.2026.
/// 3. **Анкета «Получать эл-й чек» = `no` → ДРУК.**
/// 4. **Інакше → електронний.**
class ReceiptPrintRule {
  /// Продаж без картки лояльності: анкети немає, отже й каналу для
  /// електронного чека теж.
  ///
  /// Андрій підтвердив 04.09.2026: «в случае отсутствия телефона покупателя
  /// чек печатается». Тобто здогад був правильний. Він же додав деталь до
  /// верстки: такий чек друкується кеглем 5 повністю, бо інформації про
  /// лояльність немає, а значить немає й рядка, на якому кегль міняється.
  static const printWhenNoAnketa = true;

  /// Значення поля анкети → чи отримує клієнт електронний чек.
  ///
  /// `no` (будь-який регістр) — не отримує, друкуємо папір. Будь-яке інше
  /// непорожнє значення — отримує. `null`/порожньо — анкети немає.
  static bool? electronicFromAnketa(String? raw) {
    final s = raw?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return null;
    return s != 'no';
  }

  /// Чи є замовлення програмним (реімбурсація / соцпроєкт / страхове).
  ///
  /// [fields] — `OrderData.fields`, ключі там українські підписи, не сирі
  /// імена полів.
  static bool isMandatoryProgram(OrderType type, Map<String, String> fields) {
    if (type == OrderType.likTas) return true;
    const markers = [
      'Номер реімбурсації',
      'Соціальна картка',
      'Медична програма',
      'Номер поліса',
      'Страхова компанія',
    ];
    return markers.any((m) => (fields[m] ?? '').trim().isNotEmpty);
  }

  static PrintDecision decide({
    required bool mandatoryProgram,
    required bool internetOrder,
    required bool? customerGetsElectronic,
  }) {
    if (mandatoryProgram) {
      return const PrintDecision(true, PrintReason.mandatoryProgram);
    }
    if (internetOrder) {
      return const PrintDecision(false, PrintReason.internetOrder);
    }
    if (customerGetsElectronic == null) {
      return const PrintDecision(printWhenNoAnketa, PrintReason.noAnketa);
    }
    return customerGetsElectronic
        ? const PrintDecision(false, PrintReason.customerElectronic)
        : const PrintDecision(true, PrintReason.customerOptedOut);
  }
}
