// ignore_for_file: avoid_print
/// Explore FindWZakaz service: parameters, values, related services.
/// Run: dart run tool/explore_find_wzakaz.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

const baseUrl = 'http://10.90.77.66:57772/csp/user/Kab.Service.cls';

/// Calls the Caché service, retries on 503 up to [retries] times.
Future<String?> callService(Map<String, String> params,
    {int retries = 3}) async {
  for (var i = 0; i < retries; i++) {
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      final body = _decode(resp.bodyBytes);
      if (body.contains('Service Unavailable')) {
        if (i < retries - 1) {
          await Future.delayed(Duration(seconds: 5 * (i + 1)));
          continue;
        }
        return null; // server down after retries
      }
      return body;
    } catch (e) {
      if (i < retries - 1) {
        await Future.delayed(Duration(seconds: 5 * (i + 1)));
      }
    }
  }
  return null;
}

void main() async {
  print('═══ FindWZakaz Parameter Discovery ═══\n');

  // 1. Call with no params to see default error
  print('1. No params:');
  final noParams = await callService({'ServiceName': 'FindWZakaz'});
  print('   → ${noParams ?? "SERVER DOWN"}\n');

  // 2. Known internet order numbers from GetPalantir (completed transactions)
  final internetNums = [
    '164601584', '164640162', '164787184', '164876510',
  ];
  final invoiceNums = [
    '4700012757', '4700012924', '4700013005',
  ];
  final phoneNums = ['0440007807', '0982363984'];

  // 3. Try all param names with first internet number
  print('2. Parameter names with internet=${internetNums[0]}:');
  final paramNames = [
    'id', 'number', 'num', 'invoice', 'internet', 'reserve',
    'order', 'nzakaz', 'zakaz', 'nomer', 'kod', 'code',
    'barcode', 'sku', 'wz', 'phone', 'search', 'q', 'query',
    'name', 'nrezweb', 'nrez', 'rezweb', 'numweb', 'web',
    'nint', 'nweb', 'nomer_web', 'zak', 'klient', 'client',
  ];

  for (final p in paramNames) {
    final result = await callService({
      'ServiceName': 'FindWZakaz',
      p: internetNums[0],
    });
    if (result == null) {
      print('   $p → SERVER DOWN');
    } else if (result.contains('не знайдено')) {
      // Expected "not found" — param accepted
      // print('   $p → not found (param accepted)');
    } else {
      print('   ✅ $p → $result');
    }
  }

  // 4. Try with invoice numbers
  print('\n3. Invoice numbers:');
  for (final inv in invoiceNums) {
    for (final p in ['invoice', 'id', 'number', 'num', 'kod']) {
      final result = await callService({
        'ServiceName': 'FindWZakaz',
        p: inv,
      });
      if (result != null && !result.contains('не знайдено')) {
        print('   ✅ $p=$inv → $result');
      }
    }
  }

  // 5. Try phone-based search
  print('\n4. Phone-based search:');
  for (final ph in phoneNums) {
    final result = await callService({
      'ServiceName': 'FindWZakaz',
      'phone': ph,
    });
    if (result != null) {
      if (result.contains('не знайдено')) {
        print('   phone=$ph → not found');
      } else {
        print('   ✅ phone=$ph → ${result.substring(0, result.length.clamp(0, 300))}');
      }
    } else {
      print('   phone=$ph → SERVER DOWN');
    }
  }

  // 6. Try with date range + phone
  print('\n5. Multi-param (phone+dates):');
  final multiResult = await callService({
    'ServiceName': 'FindWZakaz',
    'phone': '0440007807',
    'dt_beg': '07.03.2026',
    'dt_end': '08.03.2026',
  });
  print('   → ${multiResult ?? "SERVER DOWN"}');

  // 7. Discover related services
  print('\n6. Related services:');
  final relatedServices = [
    'FindWZakaz', 'GetWZakaz', 'ListWZakaz', 'WZakaz', 'WZakazList',
    'WZakazItems', 'GetWZakazList', 'GetWZakazItems', 'WZakazDetail',
    'SearchWZakaz', 'FindZakaz', 'GetZakaz', 'ListZakaz',
    'FindOrder', 'GetOrder', 'ListOrders',
    'FindReserve', 'GetReserve', 'ListReserves',
    'FindReserveWeb', 'GetReserveWeb', 'ReserveWeb',
    'GetInternet', 'FindInternet', 'InternetOrder',
    'GetInternetOrder', 'GetInternetOrders', 'FindInternetOrder',
    'GetTabletki', 'GetTabletkiOrder', 'FindTabletki',
    'GetPalantir2', 'GetPalantirDetail', 'GetPalantirItems',
    'PalantirItems', 'PalantirDetail',
    'GetNakladna', 'GetNakladnaItems', 'FindNakladna',
    'GetCheck', 'GetCheckItems', 'FindCheck',
    'GetReceipt', 'GetReceiptItems',
    'GetPostamat', 'FindPostamat', 'GetLocker',
    'GetWZakazSostav', 'WZakazSostav', 'GetZakazSostav',
  ];

  for (final svc in relatedServices) {
    final result = await callService({'ServiceName': svc});
    if (result == null) {
      // Server down, skip
      continue;
    }
    final isNotFound = result.contains('не определен') ||
        result.contains('не визначен') ||
        result.contains('not found') ||
        result.contains('не существует');
    if (!isNotFound) {
      print('   ✅ $svc EXISTS → ${result.substring(0, result.length.clamp(0, 200))}');
    }
  }

  print('\n═══ Done ═══');
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return _decodeWin1251(bytes);
  }
}

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
