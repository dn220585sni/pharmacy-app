import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/prro_service.dart';

/// A5 — жоден чек не має піти на тестовий ФН з бойової каси.
///
/// У бінарнику лишається compile-time дефолт `numFiscal = 4000952779`
/// (тестовий). Якщо реєстр каси не дав `ekkPort`, чеки мовчки пішли б на нього
/// — з коректним «SALE OK» у лозі. Тут перевіряємо саме таблицю рішень.
void main() {
  group('PrroConfig.fiscalTrustedWhen', () {
    test('ФН з реєстру → фіскалізація дозволена', () {
      expect(
        PrroConfig.fiscalTrustedWhen(
          fromRegistry: true,
          allowDefault: false,
          isDebugBuild: false,
        ),
        isTrue,
      );
    });

    test('release + ФН НЕ з реєстру → ЗАБЛОКОВАНО (головний кейс A5)', () {
      expect(
        PrroConfig.fiscalTrustedWhen(
          fromRegistry: false,
          allowDefault: false,
          isDebugBuild: false,
        ),
        isFalse,
      );
    });

    test('debug-збірка → дозволено (розробка на cloud test)', () {
      expect(
        PrroConfig.fiscalTrustedWhen(
          fromRegistry: false,
          allowDefault: false,
          isDebugBuild: true,
        ),
        isTrue,
      );
    });

    test('аварійний вимикач PRRO_ALLOW_DEFAULT_FISCAL → дозволено', () {
      expect(
        PrroConfig.fiscalTrustedWhen(
          fromRegistry: false,
          allowDefault: true,
          isDebugBuild: false,
        ),
        isTrue,
      );
    });

    test('вимикач вимкнений за замовчуванням', () {
      // Якщо колись стане true без --dart-define — гард перестане захищати.
      expect(PrroConfig.allowDefaultFiscal, isFalse);
    });

    test('дефолтний ФН у бінарнику — саме тестовий, і він НЕ з реєстру', () {
      // Контроль припущення, на якому тримається весь A5.
      expect(PrroConfig.numFiscal, 4000952779);
      expect(PrroConfig.fiscalFromRegistry, isFalse);
    });
  });
}
