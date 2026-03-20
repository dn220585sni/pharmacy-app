// ignore_for_file: avoid_print
/// Discover all Palantir-related services on the Caché server.
/// Run: dart run tool/discover_palantir_services.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const baseUrl = 'http://10.90.77.66:57772/csp/user/Kab.Service.cls';

  // All possible Palantir service name variations
  final serviceNames = [
    // GetPalantir variants
    'GetPalantir',
    'GetPalantirItems',
    'GetPalantirDetail',
    'GetPalantirOrder',
    'GetPalantirOrders',
    'GetPalantirInfo',
    'GetPalantirData',
    'GetPalantirList',
    'GetPalantirStatus',
    'GetPalantirHistory',
    'GetPalantirProduct',
    'GetPalantirProducts',
    'GetPalantirGoods',
    'GetPalantirSKU',
    'GetPalantirNakladna',
    'GetPalantirInvoice',
    'GetPalantirReserve',
    // Palantir* variants (without Get)
    'Palantir',
    'PalantirItems',
    'PalantirDetail',
    'PalantirOrder',
    'PalantirOrders',
    'PalantirInfo',
    'PalantirData',
    'PalantirList',
    'PalantirStatus',
    'PalantirHistory',
    'PalantirProduct',
    'PalantirProducts',
    'PalantirGoods',
    'PalantirSKU',
    'PalantirNakladna',
    'PalantirInvoice',
    'PalantirReserve',
    'PalantirGet',
    'PalantirGetItems',
    // Set/Update variants
    'SetPalantir',
    'SetPalantirStatus',
    'UpdatePalantir',
    // With underscores/numbers
    'GetPalantir2',
    'GetPalantir3',
    'Palantir2',
    'Palantir3',
    'Get_Palantir',
    'Palantir_Items',
    'Palantir_Detail',
    // Common web-order related names
    'GetWZakaz',
    'GetWZakazItems',
    'GetWZakazDetail',
    'WZakaz',
    'WZakazItems',
    'GetInternetOrder',
    'GetInternetOrders',
    'InternetOrder',
    'InternetOrders',
    'GetReserve',
    'GetReserves',
    'GetReserveItems',
    'GetWebOrder',
    'GetWebOrders',
    'GetOrderItems',
    'GetOrderDetail',
    'GetOnlineOrder',
    'GetTabletkiUA',
    'GetTabletki',
    // Postamaty-related (might have item data)
    'GetPostamat',
    'GetPostamatItems',
    'GetPostamatOrder',
    'GetLocker',
    'GetLockerItems',
    'PostamatOrder',
    'PostamatItems',
  ];

  print('Перевіряю ${serviceNames.length} сервісів на сервері...\n');

  final found = <String>[];
  final errors = <String, String>{};

  for (final name in serviceNames) {
    final uri = Uri.parse(baseUrl).replace(queryParameters: {
      'ServiceName': name,
    });

    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 8));

      String body;
      try {
        body = utf8.decode(response.bodyBytes);
      } catch (_) {
        body = _decodeWin1251(response.bodyBytes);
      }

      // Check for known "not found" responses
      final isNotFound = body.contains('не определен') ||
          body.contains('не визначен') ||
          body.contains('not found') ||
          body.contains('Service Unavailable');

      if (isNotFound) {
        // Skip silently
      } else if (response.statusCode == 200) {
        found.add(name);
        print('✅ ЗНАЙДЕНО: $name');
        print('   HTTP ${response.statusCode}');
        // Show first 300 chars of response
        final preview =
            body.length > 300 ? '${body.substring(0, 300)}...' : body;
        print('   Response: $preview\n');
      } else {
        errors[name] = 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      errors[name] = e.toString();
    }
  }

  print('\n════════════════════════════════════════════');
  print('РЕЗУЛЬТАТИ:');
  print('════════════════════════════════════════════');
  print('Знайдено сервісів: ${found.length}');
  for (final name in found) {
    print('  ✅ $name');
  }
  if (errors.isNotEmpty) {
    print('\nПомилки з\'єднання: ${errors.length}');
    for (final entry in errors.entries) {
      print('  ❌ ${entry.key}: ${entry.value}');
    }
  }
  print(
      '\nНе знайдено: ${serviceNames.length - found.length - errors.length}');
}

/// Minimal win-1251 decoder for Cyrillic
String _decodeWin1251(List<int> bytes) {
  const table = [
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
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.writeCharCode(b < 0x80 ? b : table[b - 0x80]);
  }
  return buf.toString();
}
