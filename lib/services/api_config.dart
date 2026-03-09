/// Конфігурація з'єднання з Caché сервером.
///
/// [useMock] = true  — працює на локальних моках (без сервера)
/// [useMock] = false — HTTP-запити до Caché CSP
class ApiConfig {
  /// Перемикач mock / live.
  /// true  = розробка без сервера (mock дані)
  /// false = реальний Caché сервер
  static const bool useMock = true;

  /// Адреса Caché CSP сервера.
  /// Формат: http://IP:PORT/csp/user/Kab.Service.cls
  static const String baseUrl =
      'http://10.10.99.1:6001/csp/user/Kab.Service.cls';

  /// Таймаут запиту в секундах.
  static const int timeoutSeconds = 10;
}
