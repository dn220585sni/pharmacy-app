import 'package:flutter/foundation.dart';

import 'api_config.dart';
import 'cache_api_client.dart';

/// Інформація про фармацевта.
class PharmacistInfo {
  final String user;
  final String password;
  final String ipn;

  PharmacistInfo({
    required this.user,
    required this.password,
    required this.ipn,
  });
}

/// Сервіс авторизації фармацевта.
///
/// Caché сервіси: GetUsersRlz, LoginRlz, LogoutRlz
class AuthService {
  static final _api = CacheApiClient();

  /// Активна сесія фармацевта.
  static String? _sessionId;
  static String? get sessionId => _sessionId;

  /// Авторизація фармацевта — створює сесію.
  ///
  /// Caché: `GET ?ServiceName=LoginRlz&user={user}&pswd={pswd}`
  /// Response: `{"Status":"OK","Result":"Встановлена сесія","sessionId":"..."}`
  static Future<bool> login(String user, String password) async {
    if (ApiConfig.useMock) return _mockLogin(user, password);

    final response = await _api.call('LoginRlz', params: {
      'user': user,
      'pswd': password,
    });

    if (response.isOk) {
      final id = response.data['sessionId']?.toString();
      if (id != null && id.isNotEmpty) {
        _sessionId = id;
        _api.sessionId = id;
        debugPrint('LoginRlz OK: sessionId=$id');
        return true;
      }
    }
    debugPrint('LoginRlz failed: ${response.result}');
    return false;
  }

  /// Закриття сесії фармацевта.
  ///
  /// Caché: `GET ?ServiceName=LogoutRlz&sessionId={sessionId}`
  static Future<bool> logout() async {
    if (ApiConfig.useMock || _sessionId == null) {
      _sessionId = null;
      return true;
    }

    final id = _sessionId!;
    _sessionId = null;
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
  /// Повертає масив {user, pswd, ipn}
  static Future<List<PharmacistInfo>> getUsers() async {
    if (ApiConfig.useMock) return _mockGetUsers();

    final response = await _api.call('GetUsersRlz');

    if (!response.isOk) return [];

    final usersJson = response.data['users'];
    if (usersJson is! List) return [];

    return usersJson
        .whereType<Map<String, dynamic>>()
        .map((u) => PharmacistInfo(
              user: u['user']?.toString() ?? '',
              password: u['pswd']?.toString() ?? '',
              ipn: u['ipn']?.toString() ?? '',
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
