// Quick test for Sparta Loyalty API connection.
// Run: dart run tool/test_loyalty_api.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const baseUrl = 'https://demo.spartaloyalty.com/TestAnc2/api';
const apiUser = 'anc_pos';
const apiToken = 'ukw4kztxvael528f5ufpnk67r6xzyvc5fm2dghu7';
const posKey = '87SNRM9ERH7YP6J6';
const partnerCode = 'ANC';
const placeCode = 'MR_TEST_PLACE';

String computeSignature({
  String partnerCode = '',
  String placeCode = '',
  String posCode = '',
  String date = '',
  String no = '',
  String documentNo = '',
  bool reverse = false,
  bool checkOnly = false,
  String cardNo = '',
}) {
  final reverseStr = reverse ? '1' : '';
  final checkOnlyStr = checkOnly ? '1' : '';
  final chain =
      '$partnerCode$placeCode$posCode$date$no$documentNo$reverseStr$checkOnlyStr$cardNo';
  final signatureBase = sha256.convert(utf8.encode(chain)).toString();
  return sha256.convert(utf8.encode('$signatureBase$posKey')).toString();
}

Future<void> main() async {
  print('=== Test 1: Ping ===');
  try {
    final resp = await http
        .post(Uri.parse('$baseUrl/tx/ping'),
            headers: {'Content-Type': 'application/json'}, body: '{}')
        .timeout(const Duration(seconds: 10));
    print('${resp.statusCode}: ${resp.body}\n');
  } catch (e) {
    print('Error: $e\n');
  }

  print('=== Test 2: checkConfig ===');
  try {
    final now = DateTime.now();
    final dateMs = now.millisecondsSinceEpoch.toString();
    final sig = computeSignature(
        partnerCode: partnerCode, placeCode: placeCode, date: dateMs);
    final body = jsonEncode({
      'ver': 4,
      'requestId': 'cfg_$dateMs',
      'apiUser': apiUser,
      'apiToken': apiToken,
      'partnerCode': partnerCode,
      'placeCode': placeCode,
      'date': now.toIso8601String(),
      'signature': sig,
    });
    final resp = await http
        .post(Uri.parse('$baseUrl/tx/checkConfig'),
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(resp.body);
    print('errorCode: ${data["errorCode"]}');
    print('msg: ${data["msg"]}\n');
  } catch (e) {
    print('Error: $e\n');
  }

  print('=== Test 3: checkCard (TS00000103) ===');
  try {
    final now = DateTime.now();
    final dateMs = now.millisecondsSinceEpoch.toString();
    final sig = computeSignature(
        partnerCode: partnerCode,
        placeCode: placeCode,
        date: dateMs,
        cardNo: 'TS00000103');
    final body = jsonEncode({
      'ver': 4,
      'requestId': 'cc_$dateMs',
      'apiUser': apiUser,
      'apiToken': apiToken,
      'partnerCode': partnerCode,
      'placeCode': placeCode,
      'date': now.toIso8601String(),
      'signature': sig,
      'cardNo': 'TS00000103',
      'extendedPersonalInfo': true,
    });
    final resp = await http
        .post(Uri.parse('$baseUrl/tx/checkCard'),
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(resp.body);
    print('errorCode: ${data["errorCode"]}');
    if (data['errorCode'] == '0') {
      final r = data['response'];
      print('balance: ${r["balanceAfter"]}');
      final person = r['person'];
      print(
          'person: ${person["firstName"]} ${person["lastName"]}, mobile: ${person["mobile"]}');
    } else {
      print('msg: ${data["msg"]}');
    }
  } catch (e) {
    print('Error: $e');
  }

  print('\n=== Test 4: checkCard by phone (+380676178812) ===');
  try {
    final now = DateTime.now();
    final dateMs = now.millisecondsSinceEpoch.toString();
    final sig = computeSignature(
        partnerCode: partnerCode,
        placeCode: placeCode,
        date: dateMs,
        cardNo: '+380676178812');
    final body = jsonEncode({
      'ver': 4,
      'requestId': 'ph_$dateMs',
      'apiUser': apiUser,
      'apiToken': apiToken,
      'partnerCode': partnerCode,
      'placeCode': placeCode,
      'date': now.toIso8601String(),
      'signature': sig,
      'cardNo': '+380676178812',
      'extendedPersonalInfo': true,
    });
    final resp = await http
        .post(Uri.parse('$baseUrl/tx/checkCard'),
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(resp.body);
    print('errorCode: ${data["errorCode"]}');
    if (data['errorCode'] == '0') {
      final r = data['response'];
      print('balance: ${r["balanceAfter"]}');
      final person = r['person'];
      print(
          'person: ${person["firstName"]} ${person["lastName"]}, card: ${person["cardNo"]}');
    } else {
      print('msg: ${data["msg"]}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
