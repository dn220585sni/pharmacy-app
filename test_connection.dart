// ignore_for_file: avoid_print
/// Діагностичний скрипт для перевірки з'єднання з Caché CSP сервером.
///
/// Запуск: dart run test_connection.dart [IP:PORT]
/// Приклад: dart run test_connection.dart 10.10.99.1:6001
///          dart run test_connection.dart 192.168.1.100:6001
///
/// Якщо IP:PORT не вказано — пробує адресу з api_config.dart
import 'dart:convert';
import 'dart:io';

const defaultHost = '10.10.99.1';
const defaultPort = 6001;
const cspPath = '/csp/user/Kab.Service.cls';
const timeout = Duration(seconds: 10);

/// Windows-1251 → Unicode таблиця (0x80..0xFF)
const List<int> _win1251Table = [
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
  0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
  0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
  0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
  0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
  0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
  0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
  0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
  0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
  0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
  0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
  0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
];

String decodeWin1251(List<int> bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    if (b < 0x80) {
      buf.writeCharCode(b);
    } else {
      buf.writeCharCode(_win1251Table[b - 0x80]);
    }
  }
  return buf.toString();
}

String smartDecode(List<int> bytes, String contentType) {
  if (contentType.toLowerCase().contains('windows-1251')) {
    return decodeWin1251(bytes);
  }
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return decodeWin1251(bytes);
  }
}

void main(List<String> args) async {
  String host = defaultHost;
  int port = defaultPort;

  if (args.isNotEmpty) {
    final parts = args[0].split(':');
    host = parts[0];
    if (parts.length > 1) {
      port = int.tryParse(parts[1]) ?? defaultPort;
    }
  }

  final baseUrl = 'http://$host:$port$cspPath';

  print('');
  print('=' * 60);
  print('  ДІАГНОСТИКА З\'ЄДНАННЯ З CACHÉ CSP');
  print('=' * 60);
  print('  Сервер: $host:$port');
  print('  URL:    $baseUrl');
  print('=' * 60);
  print('');

  // ── Крок 1: TCP-з'єднання ─────────────────────────────────
  print('1. TCP-з\'єднання до $host:$port ...');
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    print('   ✅ Порт $port відкритий');
  } on SocketException catch (e) {
    print('   ❌ Не вдалось підключитись: $e');
    print('');
    print('   Можливі причини:');
    print('   - Невірна IP-адреса (перевірте ipconfig на RDP)');
    print('   - Порт $port не слухає (перевірте Caché/CSP)');
    print('   - Фаєрвол блокує з\'єднання');
    print('');
    print('   Спробуйте на RDP-машині виконати:');
    print('   > ipconfig');
    print('   і перезапустіть скрипт з правильною IP');
    exit(1);
  } catch (e) {
    print('   ❌ Помилка: $e');
    exit(1);
  }

  // ── Крок 2: HTTP GET до CSP ───────────────────────────────
  print('');
  print('2. HTTP GET до CSP (без параметрів) ...');
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(Uri.parse(baseUrl));
    final resp = await req.close().timeout(timeout);
    final body = await resp.fold<List<int>>(
      [],
      (prev, chunk) => prev..addAll(chunk),
    );
    final ct = resp.headers.contentType?.toString() ?? '';
    final text = smartDecode(body, ct);

    print('   HTTP ${resp.statusCode} ${resp.reasonPhrase}');
    print('   Content-Type: $ct');
    print('   Тіло (перші 500 симв.):');
    print('   ${text.substring(0, text.length > 500 ? 500 : text.length)}');
    if (resp.statusCode == 200) {
      print('   ✅ CSP відповідає');
    } else {
      print('   ⚠️  Статус не 200, але з\'єднання є');
    }
  } catch (e) {
    print('   ❌ Помилка HTTP: $e');
  }

  // ── Крок 3: GetUsers ──────────────────────────────────────
  print('');
  print('3. Тест сервісу GetUsers ...');
  await _testService(client, baseUrl, 'GetUsers', {});

  // ── Крок 4: GetSKU (порожній запит) ───────────────────────
  print('');
  print('4. Тест сервісу GetSKU (ids=1, barcode пустий) ...');
  await _testService(client, baseUrl, 'GetSKU', {
    'ids': '1',
    'barcode': '',
    'user': '',
  });

  // ── Крок 5: GetSKUprice ───────────────────────────────────
  print('');
  print('5. Тест сервісу GetSKUprice (sku=1) ...');
  await _testService(client, baseUrl, 'GetSKUprice', {
    'sku': '1',
  });

  // ── Крок 6: Login ─────────────────────────────────────────
  print('');
  print('6. Тест сервісу Login (test/test) ...');
  await _testService(client, baseUrl, 'Login', {
    'user': 'test',
    'pswd': 'test',
  });

  // ── Крок 7: GetOstatokForKodSP ────────────────────────────
  print('');
  print('7. Тест сервісу GetOstatokForKodSP (kodsp=1) ...');
  await _testService(client, baseUrl, 'GetOstatokForKodSP', {
    'kodsp': '1',
  });

  print('');
  print('=' * 60);
  print('  ДІАГНОСТИКА ЗАВЕРШЕНА');
  print('=' * 60);
  print('');

  client.close();
  exit(0);
}

Future<void> _testService(
  HttpClient client,
  String baseUrl,
  String serviceName,
  Map<String, String> params,
) async {
  try {
    final queryParams = {
      'ServiceName': serviceName,
      ...params,
    };
    final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);
    print('   URL: $uri');

    final req = await client.getUrl(uri);
    final resp = await req.close().timeout(timeout);
    final body = await resp.fold<List<int>>(
      [],
      (prev, chunk) => prev..addAll(chunk),
    );
    final ct = resp.headers.contentType?.toString() ?? '';
    final text = smartDecode(body, ct);

    print('   HTTP ${resp.statusCode}');
    print('   Відповідь: $text');

    // Пробуємо розпарсити як JSON
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      final status = json['Status']?.toString() ?? '?';
      if (status == 'OK') {
        print('   ✅ Status: OK');
      } else {
        print('   ⚠️  Status: $status — Result: ${json['Result'] ?? ''}');
      }
    } catch (_) {
      print('   ⚠️  Відповідь не є валідним JSON');
    }
  } catch (e) {
    print('   ❌ Помилка: $e');
  }
}
