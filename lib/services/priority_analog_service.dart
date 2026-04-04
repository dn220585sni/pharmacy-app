import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Priority Analogs (ЄДК) — Apiator API client
// Docs: memory/priority-analogs-api.md
// ─────────────────────────────────────────────────────────────────────────────

/// Конфігурація Apiator API для пріоритетних аналогів.
class PriorityAnalogConfig {
  static const tokenUrl = 'http://www.apiator.anctm.biz/oauth/token';
  static const procedureUrl =
      'http://www.apiator.anctm.biz/procedure/call/2040030682960363520/GET_PRIORITY_ANALOGS_BASEID';

  static const basicAuth =
      'QVBJdW0yMDQwMDMwNjgyOTYwMzYzNTIwOktoaU9aSD88NnAvd1p6cGYscFYia3g/MzNmQyk2NnBRP1dNTSZFYiFCTyl6Plt1VnQn';
  static const clientId = 'APIum2040030682960363520';
  static const username = 'InuhtemuJF';
  static const password = 'nlAb8_UA3.-GZRaACq0.1FBUf50r7.';

  /// Ідентифікатор юридичної особи (2 = Магнолія).
  static const int baseId = 2;

  static const timeout = Duration(seconds: 15);
}

// ── Model ──────────────────────────────────────────────────────────────────

/// Одна зв'язка донор → аналог з API.
class PriorityAnalog {
  final int donorUkod;          // ID1 — u-код товару-донора
  final String donorName;       // GOOD_NAME1
  final String donorManufact;   // MANUFACT1
  final int analogUkod;         // ID2 — u-код аналога
  final String analogName;      // GOOD_NAME2
  final String analogManufact;  // MANUFACT2
  final DateTime dtBeg;         // початок дії зв'язки
  final DateTime dtEnd;         // кінець дії зв'язки
  final int bonus;
  final int rating;             // пріоритет (менше = вище)
  final DateTime? immunityBeg;  // початок імунітету (пауза)
  final DateTime? immunityEnd;  // кінець імунітету
  final int dodBonus;           // додатковий бонус
  final int? linkType;          // null=загальна, 1=дефектурна

  const PriorityAnalog({
    required this.donorUkod,
    required this.donorName,
    required this.donorManufact,
    required this.analogUkod,
    required this.analogName,
    required this.analogManufact,
    required this.dtBeg,
    required this.dtEnd,
    required this.bonus,
    required this.rating,
    this.immunityBeg,
    this.immunityEnd,
    required this.dodBonus,
    this.linkType,
  });

  /// Чи активна зв'язка на поточний момент (дати + immunity).
  bool get isActive {
    final now = DateTime.now();
    if (now.isBefore(dtBeg) || now.isAfter(dtEnd)) return false;
    if (immunityBeg != null && immunityEnd != null) {
      if (now.isAfter(immunityBeg!) && now.isBefore(immunityEnd!)) {
        return false; // на паузі
      }
    }
    return true;
  }

  factory PriorityAnalog.fromJson(Map<String, dynamic> json) {
    return PriorityAnalog(
      donorUkod: _toInt(json['ID1']),
      donorName: json['GOOD_NAME1']?.toString() ?? '',
      donorManufact: json['MANUFACT1']?.toString() ?? '',
      analogUkod: _toInt(json['ID2']),
      analogName: json['GOOD_NAME2']?.toString() ?? '',
      analogManufact: json['MANUFACT2']?.toString() ?? '',
      dtBeg: _parseDate(json['DT_BEG']) ?? DateTime.now(),
      dtEnd: _parseDate(json['DT_END']) ?? DateTime.now(),
      bonus: _toInt(json['BONUS']),
      rating: _toInt(json['RATING']),
      immunityBeg: _parseDate(json['DT_IM_BEG']),
      immunityEnd: _parseDate(json['DT_IM_END']),
      dodBonus: _toInt(json['DOD_BONUS']),
      linkType: json['LINK_TYPE'] as int?,
    );
  }

  static int _toInt(dynamic v) =>
      (v is int) ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════════════

class PriorityAnalogService {
  static final _client = http.Client();

  // ── OAuth token cache ────────────────────────────────────────────────────
  static String? _accessToken;
  static DateTime? _tokenExpiry;

  // ── Analogs cache ────────────────────────────────────────────────────────
  static List<PriorityAnalog>? _cachedAnalogs;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 55); // трохи менше 1 год

  // ── Public API ───────────────────────────────────────────────────────────

  /// Отримати список активних зв'язок (з кешем).
  static Future<List<PriorityAnalog>> fetchAnalogs({
    bool forceRefresh = false,
  }) async {
    if (ApiConfig.useMock) return [];

    // Return cached if fresh
    if (!forceRefresh &&
        _cachedAnalogs != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedAnalogs!;
    }

    try {
      await _ensureToken();

      final response = await _client
          .post(
            Uri.parse(PriorityAnalogConfig.procedureUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_accessToken',
            },
            body: jsonEncode({'BASEID': PriorityAnalogConfig.baseId}),
          )
          .timeout(PriorityAnalogConfig.timeout);

      if (response.statusCode != 200) {
        debugPrint('PriorityAnalog: HTTP ${response.statusCode}');
        return _cachedAnalogs ?? [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 'ok') {
        debugPrint('PriorityAnalog: status=${json['status']}');
        return _cachedAnalogs ?? [];
      }

      final dataList = json['data'] as List<dynamic>? ?? [];
      final analogs = dataList
          .map((e) => PriorityAnalog.fromJson(e as Map<String, dynamic>))
          .where((a) => a.isActive)
          .toList();

      _cachedAnalogs = analogs;
      _cacheTime = DateTime.now();
      debugPrint('PriorityAnalog: loaded ${analogs.length} active links');
      return analogs;
    } catch (e) {
      debugPrint('PriorityAnalog fetch error: $e');
      return _cachedAnalogs ?? [];
    }
  }

  /// Очистити кеш.
  static void clearCache() {
    _accessToken = null;
    _tokenExpiry = null;
    _cachedAnalogs = null;
    _cacheTime = null;
  }

  // ── OAuth ────────────────────────────────────────────────────────────────

  static Future<void> _ensureToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return;
    }
    await _authenticate();
  }

  static Future<void> _authenticate() async {
    try {
      final response = await _client
          .post(
            Uri.parse(PriorityAnalogConfig.tokenUrl),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Authorization': 'Basic ${PriorityAnalogConfig.basicAuth}',
            },
            body:
                'grant_type=password&client_id=${PriorityAnalogConfig.clientId}'
                '&username=${PriorityAnalogConfig.username}'
                '&password=${PriorityAnalogConfig.password}',
          )
          .timeout(PriorityAnalogConfig.timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = json['access_token']?.toString();
        final expiresIn = json['expires_in'] as int? ?? 3600;
        _tokenExpiry =
            DateTime.now().add(Duration(seconds: expiresIn - 60)); // buffer
        debugPrint('PriorityAnalog: OAuth OK, expires in ${expiresIn}s');
      } else {
        debugPrint('PriorityAnalog OAuth error: HTTP ${response.statusCode}');
        throw Exception('OAuth failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('PriorityAnalog auth error: $e');
      rethrow;
    }
  }
}
