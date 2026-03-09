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
/// Caché сервіси: Login, Logout, GetUsers
class AuthService {
  static final _api = CacheApiClient();

  /// Авторизація фармацевта.
  ///
  /// Caché: `GET ?ServiceName=Login&user={user}&pswd={pswd}`
  static Future<bool> login(String user, String password) async {
    if (ApiConfig.useMock) return _mockLogin(user, password);

    final response = await _api.call('Login', params: {
      'user': user,
      'pswd': password,
    });

    return response.isOk;
  }

  /// Вихід.
  ///
  /// Caché: `GET ?ServiceName=Logout&user={user}`
  static Future<bool> logout(String user) async {
    if (ApiConfig.useMock) return true;

    final response = await _api.call('Logout', params: {
      'user': user,
    });

    return response.isOk;
  }

  /// Отримати список фармацевтів.
  ///
  /// Caché: `GET ?ServiceName=GetUsers`
  /// Повертає масив {user, pswd, ipn}
  static Future<List<PharmacistInfo>> getUsers() async {
    if (ApiConfig.useMock) return _mockGetUsers();

    final response = await _api.call('GetUsers');

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
    return user.isNotEmpty && password.isNotEmpty;
  }

  static Future<List<PharmacistInfo>> _mockGetUsers() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return [
      PharmacistInfo(user: 'Микола', password: '', ipn: '1234567890'),
      PharmacistInfo(user: 'Олена', password: '', ipn: '0987654321'),
    ];
  }
}
