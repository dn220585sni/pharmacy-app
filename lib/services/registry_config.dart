import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';
import 'api_config.dart';

/// Per-аптека конфіг із Windows-реєстру `HKEY_CURRENT_USER\Software\ZSMU\Farm`
/// (наповнює legacy Delphi-модуль). Перевизначає [ApiConfig] на старті.
///
/// Зараз: Caché baseUrl (MAddr/MPort/MNSpace) + код каси (ekkKodKli).
/// Далі: ПРРО (edVerMini/edPassMini/ekkPort/ekkIP/ekkIPPort) — окремим кроком.
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
    } finally {
      key.close();
    }
  }
}
