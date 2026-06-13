import '../data/pakunok_ids_mock.dart';
import '../models/drug.dart';

/// Соц-програма "Пакунок Малюка" — спеціальний відпуск дитячих товарів
/// з державною підтримкою. Має жорсткі обмеження:
///   - тільки товари зі списку (1500+ позицій з ознакою у Caché)
///   - тільки безготівкова оплата по терміналу
///   - тільки контактна оплата (чіп / магнітна стрічка), NFC заборонено
///   - не для інтернет-замовлень
///   - каса має бути прив'язана до терміналу
///
/// Поки використовуємо mock-список з 2400 ids витягнутих з Excel-файлу
/// "Опис програми Пакунок Малюка.xlsx". Коли Катерина додасть ознаку
/// у response `SearchByName(SKU)` (нове поле наприклад `isPakunok`)
/// або окремий ендпоінт `GetPakunokSpisok` — переключити джерело даних.
class PakunokService {
  /// Тег для `nameProject` у GetSumSkid (за документацією — окремий
  /// параметр `TypeProject=Malyuk`, не nameProject).
  static const String typeProjectTag = 'Malyuk';

  /// UI-назва соц-програми (співпадає з `_alwaysShown` у SocialProjectsService).
  static const String displayName = 'Пакунок малюка';

  /// Перевірити чи входить препарат у програму.
  static bool isPakunok(Drug drug) {
    final code = drug.skuCode;
    if (code == null || code.isEmpty) return false;
    return kPakunokIdsMock.contains(code);
  }

  /// Кількість позицій у списку (для UI/діагностики).
  static int get availableCount => kPakunokIdsMock.length;
}
