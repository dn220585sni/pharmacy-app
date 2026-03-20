// Test different apiUser/partnerCode combinations
// Run: dart run tool/test_loyalty_combos.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

const baseUrl = 'https://demo.spartaloyalty.com/TestAnc2/api';
const token = 'ukw4kztxvael528f5ufpnk67r6xzyvc5fm2dghu7';

Future<void> main() async {
  final now = DateTime.now();

  final combos = [
    {'apiUser': 'testpos', 'partnerCode': 'MR_TEST_PLACE'},
    {'apiUser': 'MR_TEST_PLACE', 'partnerCode': 'MR_TEST'},
    {'apiUser': token, 'partnerCode': 'MR_TEST'},
    {'apiUser': 'MR_TEST', 'partnerCode': 'MR_TEST_PLACE'},
    {'apiUser': token, 'partnerCode': 'MR_TEST_PLACE'},
    {'apiUser': 'MR_TEST_PLACE', 'partnerCode': 'MR_TEST_PLACE'},
  ];

  for (final c in combos) {
    try {
      final body = jsonEncode({
        'ver': 4,
        'requestId': 't_${now.millisecondsSinceEpoch}_${combos.indexOf(c)}',
        'apiUser': c['apiUser'],
        'apiToken': token,
        'partnerCode': c['partnerCode'],
        'placeCode': 'MR_TEST_PLACE',
        'date': now.toIso8601String(),
        'signature': '',
        'debugSignatureSkip': true,
      });

      final resp = await http
          .post(
            Uri.parse('$baseUrl/tx/checkConfig'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(resp.body);
      print(
          'apiUser=${c["apiUser"]!.substring(0, (c["apiUser"]!.length > 20 ? 20 : c["apiUser"]!.length))}... partnerCode=${c["partnerCode"]} → ${data["errorCode"]}');
    } catch (e) {
      print('apiUser=${c["apiUser"]} partnerCode=${c["partnerCode"]} → ERROR: $e');
    }
  }
}
