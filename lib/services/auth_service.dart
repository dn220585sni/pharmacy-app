import 'package:flutter/foundation.dart';

import 'api_config.dart';
import 'cache_api_client.dart';

/// Інформація про фармацевта.
class PharmacistInfo {
  final String user;
  final String password;
  final String ipn;

  /// Спецкористувач (`typezuser==1`) — має доступ до адмінки «Налаштування каси».
  final bool isSpecial;

  PharmacistInfo({
    required this.user,
    required this.password,
    required this.ipn,
    this.isSpecial = false,
  });
}

/// Сервіс авторизації фармацевта.
///
/// Caché сервіси: GetUsersRlz, LoginRlz, LogoutRlz.
/// Один користувач = одна активна сесія (роздріб так спроєктований). Сесію
/// НЕ зберігаємо локально: при повторному вході під зайнятим користувачем
/// сервер повертає «вже працює», а примусове завершення робиться сервером
/// через `LoginRlz&force=1` (по кнопці «Завершити сесію»).
class AuthService {
  static final _api = CacheApiClient();

  /// Активна сесія фармацевта.
  static String? _sessionId;
  static String? get sessionId => _sessionId;

  /// Ім'я поточного залогіненого фармацевта.
  static String? _currentUser;
  static String? get currentUser => _currentUser;

  /// Останній результат помилки login (для UI).
  static String? lastLoginError;

  // ── Auth API ─────────────────────────────────────────────────────────────

  /// Авторизація фармацевта — створює сесію.
  ///
  /// Caché: `GET ?ServiceName=LoginRlz&user={user}&pswd={pswd}&ekkKodKli={kod}[&force=1]`
  /// Response: `{"Status":"OK","Result":"Встановлена сесія","sessionId":"..."}`
  ///
  /// `ekkKodKli` (код каси з реєстру) — ОБОВ'ЯЗКОВИЙ: сервер за ним піднімає
  /// контекст «клієнт РРО» для сесії. Без нього всі РРО-залежні сервіси
  /// (ProvSumZOtchet, SaveSumDay, GetTermBank, ZRep) падають «Перевірте клієнта РРО».
  ///
  /// [force] = true (`force=1`) — сервер зачистить УСІ сесії цього користувача
  /// й залогінить наново. Шлемо лише свідомо (кнопка «Завершити сесію» після
  /// «вже працює»), НЕ автоматично.
  static Future<bool> login(String user, String password,
      {bool force = false}) async {
    if (ApiConfig.useMock) return _mockLogin(user, password);

    final response = await _api.call('LoginRlz', params: {
      'user': user,
      'pswd': password,
      'ekkKodKli': ApiConfig.ekkKodKli,
      if (force) 'force': '1',
    });

    if (response.isOk) {
      final id = response.data['sessionId']?.toString();
      if (id != null && id.isNotEmpty) {
        _sessionId = id;
        _currentUser = user;
        _api.sessionId = id;
        lastLoginError = null;
        debugPrint('LoginRlz OK: sessionId=$id${force ? ' (force)' : ''}');
        return true;
      }
    }

    lastLoginError = response.result;
    debugPrint('LoginRlz failed: ${response.result}');
    return false;
  }

  /// Чи була останньою помилкою "Користувач вже працює".
  static bool get isUserBusy =>
      lastLoginError != null && lastLoginError!.contains('вже працює');

  /// Закриття сесії фармацевта.
  ///
  /// Caché: `GET ?ServiceName=LogoutRlz&sessionId={sessionId}`
  static Future<bool> logout() async {
    if (ApiConfig.useMock) {
      _sessionId = null;
      _currentUser = null;
      return true;
    }

    if (_sessionId == null) return true;

    final id = _sessionId!;
    _sessionId = null;
    _currentUser = null;
    _api.sessionId = null;

    final response = await _api.call('LogoutRlz', params: {
      'sessionId': id,
    });

    debugPrint('LogoutRlz: ${response.result}');
    return response.isOk;
  }

  /// Отримати список фармацевтів з паролями та ІПН.
  ///
  /// Caché: `GET ?ServiceName=GetUsersRlz`
  /// Повертає масив {user, pswd, ipn, typezuser}
  static Future<List<PharmacistInfo>> getUsers() async {
    if (ApiConfig.useMock) return _mockGetUsers();

    final response = await _api.call('GetUsersRlz', params: {
      'rezhim': 'all',
    });

    debugPrint('GetUsersRlz isOk=${response.isOk}, result=${response.result}');
    if (!response.isOk) return [];

    final usersJson = response.data['users'];
    debugPrint('GetUsersRlz users type=${usersJson.runtimeType}, '
        'isList=${usersJson is List}, '
        'length=${usersJson is List ? usersJson.length : "n/a"}');
    if (usersJson is! List) return [];

    return usersJson
        .whereType<Map<String, dynamic>>()
        .map((u) => PharmacistInfo(
              user: u['user']?.toString() ?? '',
              password: u['pswd']?.toString() ?? '',
              ipn: u['ipn']?.toString() ?? '',
              isSpecial: u['typezuser']?.toString() == '1',
            ))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Mock
  // ---------------------------------------------------------------------------

  static Future<bool> _mockLogin(String user, String password) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (user.isNotEmpty && password.isNotEmpty) {
      _sessionId = 'mock_session_${DateTime.now().millisecondsSinceEpoch}';
      _currentUser = user;
      _api.sessionId = _sessionId;
      return true;
    }
    return false;
  }

  static Future<List<PharmacistInfo>> _mockGetUsers() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return [
      PharmacistInfo(user: 'Микола', password: '1234', ipn: '1234567890'),
      PharmacistInfo(user: 'Олена', password: '5678', ipn: '0987654321'),
    ];
  }
}
