import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// Web localStorage access via conditional import
import 'session_storage_stub.dart'
    if (dart.library.html) 'session_storage_web.dart' as session_storage;

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
/// SessionId зберігається у файл для відновлення після перезапуску.
class AuthService {
  static final _api = CacheApiClient();

  /// Активна сесія фармацевта.
  static String? _sessionId;
  static String? get sessionId => _sessionId;

  /// Ім'я поточного залогіненого фармацевта (для force logout).
  static String? _currentUser;

  /// Останній результат помилки login (для UI).
  static String? lastLoginError;

  // ── Session file ───────────────────────────────────────────────────────

  static const _sessionFileName = '.pharmacy_session';

  /// Шлях до файлу сесії (non-web only).
  static Future<File?> get _sessionFile async {
    if (kIsWeb) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_sessionFileName');
  }

  /// Зберегти sessionId + user.
  static Future<void> _persistSession(String sessionId, String user) async {
    try {
      if (kIsWeb) {
        session_storage.saveSession(sessionId, user);
        return;
      }
      final file = await _sessionFile;
      await file!.writeAsString('$sessionId\n$user');
    } catch (e) {
      debugPrint('Failed to persist session: $e');
    }
  }

  /// Видалити збережену сесію.
  static Future<void> _clearPersistedSession() async {
    try {
      if (kIsWeb) {
        session_storage.clearSession();
        return;
      }
      final file = await _sessionFile;
      if (file != null && await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Failed to clear session file: $e');
    }
  }

  /// Відновити sessionId і викликати LogoutRlz (при старті додатка).
  static Future<void> cleanupPreviousSession() async {
    if (ApiConfig.useMock) return;
    try {
      String? content;
      if (kIsWeb) {
        content = session_storage.getSession();
      } else {
        final file = await _sessionFile;
        if (file != null && await file.exists()) {
          content = await file.readAsString();
        }
      }
      if (content == null || content.isEmpty) return;
      final lines = content.split('\n');
      if (lines.isEmpty || lines[0].trim().isEmpty) return;
      final oldSessionId = lines[0].trim();
      debugPrint('Found previous session: $oldSessionId → LogoutRlz');
      await _api.call('LogoutRlz', params: {'sessionId': oldSessionId});
      if (kIsWeb) {
        session_storage.clearSession();
      } else {
        final file = await _sessionFile;
        await file!.delete();
      }
    } catch (e) {
      debugPrint('Session cleanup error: $e');
    }
  }

  // ── Auth API ─────────────────────────────────────────────────────────────

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
        _currentUser = user;
        _api.sessionId = id;
        lastLoginError = null;
        debugPrint('LoginRlz OK: sessionId=$id');
        // Persist to file for crash recovery
        _persistSession(id, user);
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

    _clearPersistedSession();
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

    debugPrint('GetUsersRlz isOk=${response.isOk}, result=${response.result}');
    if (!response.isOk) return [];

    final usersJson = response.data['users'];
    debugPrint('GetUsersRlz users type=${usersJson.runtimeType}, '
        'isList=${usersJson is List}, '
        'length=${usersJson is List ? (usersJson as List).length : "n/a"}');
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
