// ignore_for_file: avoid_print
/// Простий тест з'єднання з Caché сервером.
///
/// Запуск:
///   dart run test/api_connection_test.dart
///
/// Перед запуском:
/// 1. Переконайся, що ти в мережі аптеки (або VPN)
/// 2. Зміни IP/порт нижче якщо потрібно
import 'dart:convert';
import 'package:http/http.dart' as http;

const baseUrl = 'http://10.10.99.1:6001/csp/user/Kab.Service.cls';

Future<void> main() async {
  print('=== Тест з\'єднання з Caché сервером ===\n');
  print('URL: $baseUrl\n');

  // --- Тест 1: Простий пінг (GetSKU без параметрів) ---
  await _test('1. GetSKU (пустий запит)', {
    'ServiceName': 'GetSKU',
    'barcode': '',
    'ids': '',
    'user': '',
  });

  // --- Тест 2: GetUsers (список фармацевтів) ---
  await _test('2. GetUsers', {
    'ServiceName': 'GetUsers',
  });

  // --- Тест 3: GetSKU з реальним штрихкодом ---
  // Заміни на реальний штрихкод з аптеки:
  await _test('3. GetSKU (штрихкод)', {
    'ServiceName': 'GetSKU',
    'barcode': '4823002700572',
    'ids': '',
    'user': '',
  });

  // --- Тест 4: GetSKUprice ---
  // Заміни '123' на реальний ids/sku з відповіді GetSKU:
  // await _test('4. GetSKUprice', {
  //   'ServiceName': 'GetSKUprice',
  //   'sku': '123',
  // });

  print('\n=== Тести завершені ===');
}

Future<void> _test(String name, Map<String, String> params) async {
  print('--- $name ---');
  try {
    final uri = Uri.parse(baseUrl).replace(queryParameters: params);
    print('  URL: $uri');

    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 10));

    print('  HTTP: ${response.statusCode} ${response.reasonPhrase}');
    print('  Content-Type: ${response.headers['content-type'] ?? 'не вказано'}');

    // Спробувати декодувати як UTF-8
    String body;
    try {
      body = utf8.decode(response.bodyBytes);
    } catch (_) {
      body = String.fromCharCodes(response.bodyBytes);
      print('  ⚠️  UTF-8 не вдалось, показано raw bytes');
    }

    print('  Body: $body');

    // Спробувати розпарсити JSON
    try {
      final json = jsonDecode(body);
      print('  Status: ${json['Status']}');
      print('  Result: ${json['Result']}');
      if (json['Name'] != null) print('  Name: ${json['Name']}');
      if (json['Proiz'] != null) print('  Proiz: ${json['Proiz']}');
      if (json['users'] != null) print('  Users: ${json['users']}');
    } catch (e) {
      print('  ⚠️  JSON parse error: $e');
    }
  } on Exception catch (e) {
    print('  ❌ Помилка: $e');
  }
  print('');
}
