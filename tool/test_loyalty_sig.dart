// Debug signature with timezone fix
// Run: dart run tool/test_loyalty_sig.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const baseUrl = 'https://demo.spartaloyalty.com/TestAnc2/api';
const apiUser = 'anc_pos';
const apiToken = 'ukw4kztxvael528f5ufpnk67r6xzyvc5fm2dghu7';
const posKey = '87SNRM9ERH7YP6J6';
const partnerCode = 'ANC';
const placeCode = 'MR_TEST_PLACE';

String dateToIso(DateTime dt) {
  final offset = dt.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final h = offset.inHours.abs().toString().padLeft(2, '0');
  final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final base = dt.toIso8601String().split('.').first;
  return '$base$sign$h:$m';
}

Future<void> main() async {
  final now = DateTime.now();
  final dateIso = dateToIso(now);
  final dateMs = ((now.millisecondsSinceEpoch ~/ 1000) * 1000).toString();
  const cardNo = 'TS00000103';

  final chain = '$partnerCode$placeCode$dateMs$cardNo';
  final signatureBase = sha256.convert(utf8.encode(chain)).toString();
  final signature =
      sha256.convert(utf8.encode('$signatureBase$posKey')).toString();

  print('date ISO: $dateIso');
  print('date ms:  $dateMs');
  print('chain:    $chain');
  print('sig:      $signature');

  final body = jsonEncode({
    'ver': 4,
    'requestId': 'dbg_$dateMs',
    'apiUser': apiUser,
    'apiToken': apiToken,
    'partnerCode': partnerCode,
    'placeCode': placeCode,
    'date': dateIso,
    'no': '',
    'posCode': '',
    'signature': signature,
    'cardNo': cardNo,
    'extendedPersonalInfo': true,
    'debugSignatureExplain': true,
  });

  final resp = await http
      .post(Uri.parse('$baseUrl/tx/checkCard'),
          headers: {'Content-Type': 'application/json'}, body: body)
      .timeout(const Duration(seconds: 10));

  final data = jsonDecode(resp.body);
  print('\nerrorCode: ${data["errorCode"]}');
  if (data['errorCode'] == '0') {
    final r = data['response'];
    print('balance: ${r["balanceAfter"]}');
    final person = r['person'];
    print('person: ${person["firstName"]}, mobile: ${person["mobile"]}');
    print('messages:');
    for (final g in (r['messages'] as List? ?? [])) {
      for (final m in (g['messages'] as List? ?? [])) {
        print('  [${g["channel"]}] ${m["text"]}');
      }
    }
  } else {
    print('msg: ${data["msg"]}');
    if (data['response'] != null && data['response']['explained'] != null) {
      print('explained: ${data["response"]["explained"]}');
    }
  }
}
