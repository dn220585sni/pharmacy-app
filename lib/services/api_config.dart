/// Конфігурація з'єднання з Caché сервером.
///
/// [useMock] = true  — працює на локальних моках (без сервера)
/// [useMock] = false — HTTP-запити до Caché CSP
class ApiConfig {
  /// Перемикач mock / live.
  /// true  = розробка без сервера (mock дані)
  /// false = реальний Caché сервер
  static const bool useMock = false;

  /// Адреса Caché CSP сервера.
  /// Формат: http://IP:PORT/csp/user/Kab.Service.cls
  static const String baseUrl =
      'http://10.90.77.66:57772/csp/user/Kab.Service.cls';

  /// Таймаут запиту в секундах.
  static const int timeoutSeconds = 10;

  /// Чи має аптека робот для автоматичної подачі ліків.
  /// true  = кнопка «Робот» видима, per-item привезення активне
  /// false = функціонал робота прихований
  static const bool hasRobot = true;
}
