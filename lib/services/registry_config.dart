import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';
import 'api_config.dart';
import 'prro_service.dart';

/// Per-аптека конфіг із Windows-реєстру `HKEY_CURRENT_USER\Software\ZSMU\Farm`
/// (наповнює legacy Delphi-модуль). Перевизначає [ApiConfig]/[PrroConfig]
/// на старті.
///
/// Caché: baseUrl (MAddr/MPortS/MNSpace) + код каси (ekkKodKli).
/// ПРРО (ключі сумісні з cash_uft.dll, специфікація Попова 2026-07-10):
/// ekkPort (ФН), ekkIP (SmartConnect), ekkIPPort (online CashDesk),
/// edVerMini/edPassMini (креди), bearer (токен, ~365 днів),
/// ekkKolBukv/ekkSpeed (ширини TXT/PDF), koef_scale/monofont/
/// PRRO_index_printer (друк), chkSkidkaSumma/cbChKredit (логіка чека).
class RegistryConfig {
  static const _path = r'Software\ZSMU\Farm';

  static String? _read(RegistryKey key, String name) {
    try {
      final v = key.getValueAsString(name);
      return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// URL з реєстру приходить із хвостовим `/` (`.../api/v2/`), а код
  /// клеїть шляхи як `$baseUrl/check/sale` — зрізаємо хвостові слеші.
  static String _normalizeUrl(String url) =>
      url.replaceAll(RegExp(r'/+$'), '');

  /// Завантажити конфіг із реєстру (виклик на старті, до runApp).
  /// Якщо ключів/реєстру немає — лишаються значення за замовчуванням з ApiConfig.
  static void load() {
    if (!Platform.isWindows) return;
    RegistryKey key;
    try {
      key = Registry.openPath(RegistryHive.currentUser, path: _path);
    } catch (e) {
      debugPrint('RegistryConfig: $_path недоступний ($e) — дефолти');
      return;
    }
    try {
      // MAddr — IP сервера (127.0.0.1 коли на сервері, реальний IP коли на касі).
      // MPortS — порт для НАШИХ сервісів (HTTP CSP); MPort=6001 — старий роздріб (не чіпаємо).
      final mAddr = _read(key, 'MAddr');
      final mPortS = _read(key, 'MPortS');
      final mNspace = _read(key, 'MNSpace');
      final kod = _read(key, 'ekkKodKli');
      if (mAddr != null && mPortS != null && mNspace != null) {
        ApiConfig.baseUrl =
            'http://$mAddr:$mPortS/csp/${mNspace.toLowerCase()}/Kab.Service.cls';
        debugPrint('RegistryConfig: baseUrl=${ApiConfig.baseUrl}');
      } else {
        debugPrint('RegistryConfig: MAddr/MPortS/MNSpace неповні — '
            'baseUrl за замовчуванням (${ApiConfig.baseUrl})');
      }
      if (kod != null) {
        ApiConfig.ekkKodKli = kod;
        debugPrint('RegistryConfig: ekkKodKli=$kod');
      }
      _loadPrro(key);
    } finally {
      key.close();
    }
  }

  /// ПРРО-конфіг із тих самих ключів `ZSMU\Farm` → [PrroConfig].
  /// Відсутні значення лишають compile-time дефолти (розробка на cloud test).
  static void _loadPrro(RegistryKey key) {
    final localUrl = _read(key, 'ekkIP');       // SmartConnect (offline)
    final onlineUrl = _read(key, 'ekkIPPort');  // online CashDesk
    final fn = _read(key, 'ekkPort');           // фіскальний номер

    // Гейт ПРРО-режиму: на касах зі СТАРИМ апаратним РРО ті самі ключі мають
    // іншу семантику (ekkPort='COM1', ekkSpeed='9600' бодрейт, ekkKolBukv=11)
    // — застосувавши їх, отримали б print_width=11/pdf_width=9600. ПРРО-режим
    // розпізнаємо по URL у ekkIP/ekkIPPort (з'являється з інсталяцією
    // SmartConnect); інакше всі ПРРО-ключі ігноруємо, працюють дефолти.
    final prroMode = (localUrl?.startsWith('http') ?? false) ||
        (onlineUrl?.startsWith('http') ?? false);
    if (!prroMode) {
      debugPrint('RegistryConfig: ПРРО-ключі в legacy-форматі '
          '(ekkPort=$fn, ekkIP порожній) — ПРРО-дефолти '
          '(${PrroConfig.baseUrl}, ФН ${PrroConfig.numFiscal})');
      return;
    }

    final email = _read(key, 'edVerMini');
    final password = _read(key, 'edPassMini');
    final bearer = _read(key, 'bearer');
    final txtWidth = int.tryParse(_read(key, 'ekkKolBukv') ?? '');
    final pdfWidth = int.tryParse(_read(key, 'ekkSpeed') ?? '');
    final qrScale = double.tryParse(
        (_read(key, 'koef_scale') ?? '').replaceAll(',', '.'));
    final monoFont = _read(key, 'monofont');
    final printerIndex = int.tryParse(_read(key, 'PRRO_index_printer') ?? '');
    final chkSkidka = _read(key, 'chkSkidkaSumma');
    final cbKredit = _read(key, 'cbChKredit');

    if (localUrl != null && localUrl.startsWith('http')) {
      PrroConfig.baseUrl = _normalizeUrl(localUrl);
      debugPrint('RegistryConfig: ПРРО baseUrl=${PrroConfig.baseUrl}');
    }
    if (onlineUrl != null && onlineUrl.startsWith('http')) {
      PrroConfig.onlineBaseUrl = _normalizeUrl(onlineUrl);
    }
    final fnParsed = int.tryParse(fn ?? '');
    if (fnParsed != null) {
      PrroConfig.numFiscal = fnParsed;
      PrroConfig.fiscalFromRegistry = true;
      debugPrint('RegistryConfig: ПРРО ФН=$fnParsed (з реєстру)');
    } else {
      // Каса налаштована на SmartConnect, а ФН нема — гучний сигнал (A5):
      // інакше чеки тихо підуть на тестовий ФН.
      debugPrint('⚠️ RegistryConfig: ekkIP задано, а ekkPort (ФН) '
          'відсутній/некоректний ("$fn") — ПРРО працюватиме з тестовим '
          'ФН ${PrroConfig.numFiscal}!');
    }
    if (email != null) PrroConfig.email = email;
    if (password != null) PrroConfig.password = password;
    if (bearer != null) PrroConfig.registryBearer = bearer;
    if (txtWidth != null && txtWidth > 0) PrroConfig.printWidth = txtWidth;
    if (pdfWidth != null && pdfWidth > 0) PrroConfig.pdfWidth = pdfWidth;
    if (qrScale != null && qrScale > 0) PrroConfig.qrScale = qrScale;
    if (monoFont != null) PrroConfig.monoFont = monoFont;
    if (printerIndex != null) PrroConfig.printerIndex = printerIndex;
    if (chkSkidka != null) PrroConfig.chkSkidkaSumma = chkSkidka;
    if (cbKredit != null) PrroConfig.cbChKredit = cbKredit;

    // Оновлений bearer (після ре-авторизації) пишемо назад у реєстр —
    // ним продовжують користуватись і наступні запуски, і cash_uft.dll.
    PrroConfig.persistBearerToRegistry = writeBearer;
  }

  /// Записати новий bearer у `ZSMU\Farm\bearer` (після ре-авторизації).
  static void writeBearer(String bearer) {
    if (!Platform.isWindows) return;
    try {
      final key = Registry.openPath(RegistryHive.currentUser,
          path: _path, desiredAccessRights: AccessRights.allAccess);
      try {
        key.createValue(RegistryValue(
            'bearer', RegistryValueType.string, bearer));
        debugPrint('RegistryConfig: bearer оновлено в реєстрі');
      } finally {
        key.close();
      }
    } catch (e) {
      debugPrint('RegistryConfig: не вдалося записати bearer: $e');
    }
  }
}
