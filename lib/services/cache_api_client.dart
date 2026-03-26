import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Відповідь від Caché CSP сервера.
///
/// Caché повертає JSON вигляду:
///   {"Status":"OK", "Result":"...", ...поля...}
///   {"Status":"BAD", "Result":"текст помилки"}
class CacheResponse {
  final bool isOk;
  final String result;
  final Map<String, dynamic> data;

  CacheResponse({
    required this.isOk,
    required this.result,
    required this.data,
  });

  factory CacheResponse.fromJson(Map<String, dynamic> json) {
    return CacheResponse(
      isOk: json['Status'] == 'OK',
      result: json['Result']?.toString() ?? '',
      data: json,
    );
  }

  factory CacheResponse.error(String message) {
    return CacheResponse(
      isOk: false,
      result: message,
      data: {'Status': 'BAD', 'Result': message},
    );
  }
}

/// HTTP-клієнт для Caché CSP сервера.
///
/// Всі запити йдуть через єдину точку:
///   GET {baseUrl}?ServiceName=XXX&param1=val1&param2=val2
///
/// Особливості:
/// - Відповідь може бути в windows-1251 (кирилиця)
/// - JSON формується конкатенацією return(1..N) на сервері
/// - Status: "OK" або "BAD"
class CacheApiClient {
  static final CacheApiClient _instance = CacheApiClient._();
  factory CacheApiClient() => _instance;
  CacheApiClient._();

  final http.Client _client = http.Client();

  /// CSP session cookies — зберігаємо CSPSESSIONID + CSPWSERVERID
  /// і передаємо в кожному наступному запиті.
  String? _sessionCookie;

  /// Кодек windows-1251 для декодування кирилиці.
  /// Caché може віддавати в цьому кодуванні (залежить від настройки).
  static const _win1251 = 'windows-1251';

  /// Виконати запит до Caché CSP.
  ///
  /// [serviceName] — назва сервісу (GetSKU, GetSKUprice, Login, тощо)
  /// [params] — додаткові параметри запиту
  ///
  /// Повертає [CacheResponse] з розпарсеним JSON.
  /// Максимальна кількість повторних спроб при 503 Service Unavailable.
  static const _maxRetries = 2;
  static const _retryDelay = Duration(seconds: 2);

  Future<CacheResponse> call(
    String serviceName, {
    Map<String, String>? params,
  }) async {
    final queryParams = {
      'ServiceName': serviceName,
      ...?params,
    };

    final uri = Uri.parse(ApiConfig.baseUrl).replace(
      queryParameters: queryParams,
    );

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final headers = <String, String>{};
        if (_sessionCookie != null) {
          headers['Cookie'] = _sessionCookie!;
        }

        final response = await _client
            .get(uri, headers: headers)
            .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

        // Зберігаємо CSP session cookies з SET-COOKIE заголовків
        _updateSessionCookies(response);

        // Retry on 503 Service Unavailable (Caché CSP gateway перевантажений)
        if (response.statusCode == 503 && attempt < _maxRetries) {
          await Future.delayed(_retryDelay);
          continue;
        }

        if (response.statusCode != 200) {
          return CacheResponse.error(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          );
        }

        // Декодуємо тіло відповіді.
        // Спочатку пробуємо UTF-8, якщо не виходить — windows-1251.
        final bodyString = _decodeBody(response);

        // Парсимо JSON.
        final json = jsonDecode(bodyString) as Map<String, dynamic>;
        return CacheResponse.fromJson(json);
      } on FormatException catch (e) {
        return CacheResponse.error('Помилка формату відповіді: $e');
      } on http.ClientException catch (e) {
        if (attempt < _maxRetries) {
          await Future.delayed(_retryDelay);
          continue;
        }
        return CacheResponse.error('Помилка з\'єднання: $e');
      } catch (e) {
        if (attempt < _maxRetries) {
          await Future.delayed(_retryDelay);
          continue;
        }
        return CacheResponse.error('Помилка: $e');
      }
    }
    return CacheResponse.error('Сервер недоступний після $_maxRetries спроб');
  }

  /// Витягує CSPSESSIONID та CSPWSERVERID з SET-COOKIE заголовків
  /// і зберігає їх для передачі в наступних запитах.
  void _updateSessionCookies(http.Response response) {
    // http package об'єднує всі set-cookie в один рядок через ', '
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null) return;

    final cookies = <String, String>{};

    // Parse existing session cookie to preserve values
    if (_sessionCookie != null) {
      for (final part in _sessionCookie!.split('; ')) {
        final eq = part.indexOf('=');
        if (eq > 0) {
          cookies[part.substring(0, eq)] = part.substring(eq + 1);
        }
      }
    }

    // Extract cookie name=value from each SET-COOKIE entry
    // Format: "NAME=VALUE; path=...; httpOnly;"
    for (final entry in setCookie.split(RegExp(r',\s*(?=[A-Z])'))) {
      final nameValue = entry.split(';').first.trim();
      final eq = nameValue.indexOf('=');
      if (eq > 0) {
        final name = nameValue.substring(0, eq);
        if (name.startsWith('CSPSESSIONID') || name == 'CSPWSERVERID') {
          cookies[name] = nameValue.substring(eq + 1);
        }
      }
    }

    if (cookies.isNotEmpty) {
      _sessionCookie =
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
  }

  /// Декодує тіло HTTP-відповіді з урахуванням кодування.
  ///
  /// Caché може віддавати windows-1251 або UTF-8 залежно від
  /// налаштування ^NewSPR("Service","SetCharSet").
  String _decodeBody(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';

    // Якщо сервер явно вказав windows-1251
    if (contentType.toLowerCase().contains(_win1251)) {
      return _decodeWin1251(response.bodyBytes);
    }

    // Пробуємо UTF-8
    try {
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      // Фолбек на windows-1251
      return _decodeWin1251(response.bodyBytes);
    }
  }

  /// Декодер windows-1251 → String.
  ///
  /// Таблиця відповідності для кириличних символів (0x80-0xFF).
  String _decodeWin1251(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte < 0x80) {
        buffer.writeCharCode(byte);
      } else {
        buffer.writeCharCode(_win1251Table[byte - 0x80]);
      }
    }
    return buffer.toString();
  }

  /// Таблиця windows-1251 (0x80..0xFF) → Unicode code points.
  static const List<int> _win1251Table = [
    // 0x80-0x8F
    0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
    0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
    // 0x90-0x9F
    0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
    // 0xA0-0xAF
    0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
    0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
    // 0xB0-0xBF
    0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
    0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
    // 0xC0-0xCF (А-П)
    0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
    0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
    // 0xD0-0xDF (Р-Я)
    0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
    0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
    // 0xE0-0xEF (а-п)
    0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
    0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
    // 0xF0-0xFF (р-я)
    0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
    0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
  ];
}
