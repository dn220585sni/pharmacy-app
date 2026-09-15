import 'package:flutter/foundation.dart';
import 'api_config.dart';
import 'cache_api_client.dart';

/// Параметри внутрішньої CRM аптеки (Катя, 2026-09-14; Андрій, 2026-09-15).
///
/// `GET ?ServiceName=GetParamPr&sessionId={sessionId}&TypePr=CRM` →
/// `{"Status":"OK","login":"APT7xx","pass":"…","idT":"41"}`.
/// `login`/`pass` — Basic-авторизація сервісу дзвінків/SMS
/// (`node.anctm.biz:3100`, див. [PhoneVerifyService]); per-аптека.
/// Інші `TypePr` (medicard, orange, newpost) поки не потрібні.
class CrmParams {
  final String login;
  final String pass;
  final String idT;

  const CrmParams({required this.login, required this.pass, required this.idT});

  bool get isUsable => login.isNotEmpty && pass.isNotEmpty;

  factory CrmParams.fromJson(Map<String, dynamic> j) => CrmParams(
        login: j['login']?.toString() ?? '',
        pass: j['pass']?.toString() ?? '',
        idT: j['idT']?.toString() ?? '',
      );

  /// Пароль у лог не виводимо ніколи.
  @override
  String toString() => 'CrmParams(login=$login, idT=$idT, pass=***)';
}

class CrmParamsService {
  static CrmParams? _cache;

  static CrmParams? get cached => _cache;

  /// Завантажити (раз на сесію). На помилку — null.
  static Future<CrmParams?> fetch({bool forceRefresh = false}) async {
    if (ApiConfig.useMock) {
      return _cache ??= const CrmParams(login: 'mock', pass: 'mock', idT: '0');
    }
    if (!forceRefresh && _cache != null) return _cache;
    try {
      final r = await CacheApiClient().call('GetParamPr', params: {'TypePr': 'CRM'});
      if (r.isOk) {
        final p = CrmParams.fromJson(r.data);
        debugPrint('CrmParamsService: $p');
        return _cache = p.isUsable ? p : null;
      }
      debugPrint('CrmParamsService FAIL: ${r.result}');
    } catch (e) {
      debugPrint('CrmParamsService ERROR: $e');
    }
    return null;
  }

  /// Скинути кеш (нова сесія / інший фармацевт).
  static void clear() => _cache = null;
}
