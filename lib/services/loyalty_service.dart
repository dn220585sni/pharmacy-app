import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Конфігурація Sparta Loyalty Platform (ЛАЙК).
class SplConfig {
  static const baseUrl = 'https://demo.spartaloyalty.com/TestAnc2/api';
  static const apiUser = 'anc_pos';
  static const apiToken = 'ukw4kztxvael528f5ufpnk67r6xzyvc5fm2dghu7';
  static const posKey = '87SNRM9ERH7YP6J6';
  static const partnerCode = 'ANC';
  static const placeCode = 'MR_TEST_PLACE';
  static const ver = 4;
  static const timeout = Duration(seconds: 5);
}

/// Результат перевірки картки лояльності.
class LoyaltyCheckResult {
  final bool success;
  final double balanceAfter;
  final String? firstName;
  final String? lastName;
  final String? mobile;
  final String? cardNo;
  final String? errorMsg;
  final List<String> messages;

  LoyaltyCheckResult({
    required this.success,
    this.balanceAfter = 0,
    this.firstName,
    this.lastName,
    this.mobile,
    this.cardNo,
    this.errorMsg,
    this.messages = const [],
  });
}

/// Результат продажу.
class LoyaltySaleResult {
  final bool success;
  final double balanceBurn;
  final double balanceEarn;
  final double balanceAfter;
  final String? errorMsg;
  final List<String> messages;

  LoyaltySaleResult({
    required this.success,
    this.balanceBurn = 0,
    this.balanceEarn = 0,
    this.balanceAfter = 0,
    this.errorMsg,
    this.messages = const [],
  });
}

/// Сервіс для роботи з Sparta Loyalty Platform (ЛАЙК).
///
/// HTTPS POST JSON API з подвійним SHA256 підписом.
class LoyaltyService {
  static final _client = http.Client();

  // ───────────────────────────────────────────────────────────────────────────
  // Signature (Double SHA256)
  // ───────────────────────────────────────────────────────────────────────────

  /// Compute SPL signature: SHA256(SHA256(fields...) + posKey)
  ///
  /// Default signing fields (in order):
  /// partnerCode, placeCode, posCode, date, no, documentNo, reverse, checkOnly, cardNo
  static String _computeSignature({
    String partnerCode = '',
    String placeCode = '',
    String posCode = '',
    String date = '', // milliseconds timestamp as string
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

    final signatureBase =
        sha256.convert(utf8.encode(chain)).toString(); // lowercase hex

    final signature =
        sha256.convert(utf8.encode('$signatureBase${SplConfig.posKey}'))
            .toString();

    return signature;
  }

  /// Convert DateTime to milliseconds timestamp string (for signature).
  /// SPL truncates to whole seconds, so we do the same.
  static String _dateToMs(DateTime dt) {
    final ms = (dt.millisecondsSinceEpoch ~/ 1000) * 1000;
    return ms.toString();
  }

  /// Format DateTime as ISO8601 with timezone offset (e.g. "2026-03-19T16:25:42+03:00").
  /// Required for SPL to correctly parse the date and match our signature timestamp.
  static String _dateToIso(DateTime dt) {
    final offset = dt.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final h = offset.inHours.abs().toString().padLeft(2, '0');
    final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final base = dt.toIso8601String().split('.').first;
    return '$base$sign$h:$m';
  }

  /// Generate unique requestId.
  static String _requestId() {
    return 'pos_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ───────────────────────────────────────────────────────────────────────────
  // HTTP helpers
  // ───────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final url = Uri.parse('${SplConfig.baseUrl}$endpoint');
    try {
      final response = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode(body),
          )
          .timeout(SplConfig.timeout);

      if (response.statusCode != 200) {
        return {'errorCode': 'HTTP_${response.statusCode}', 'msg': response.reasonPhrase ?? 'error'};
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'errorCode': 'NETWORK_ERROR', 'msg': e.toString()};
    }
  }

  /// Extract cashier/printer messages from SPL response.
  static List<String> _extractMessages(Map<String, dynamic>? response) {
    if (response == null) return [];
    final msgs = response['messages'];
    if (msgs is! List) return [];
    final result = <String>[];
    for (final group in msgs) {
      if (group is Map && group['messages'] is List) {
        for (final m in group['messages']) {
          if (m is Map && m['text'] != null) {
            result.add(m['text'].toString());
          }
        }
      }
    }
    return result;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Ping
  // ───────────────────────────────────────────────────────────────────────────

  /// Check API availability. No auth needed.
  static Future<bool> ping() async {
    final result = await _post('/tx/ping', {});
    return result['errorCode']?.toString() == '0';
  }

  // ───────────────────────────────────────────────────────────────────────────
  // checkConfig — Validate credentials
  // ───────────────────────────────────────────────────────────────────────────

  /// Validate all POS configuration parameters.
  static Future<Map<String, dynamic>> checkConfig() async {
    final now = DateTime.now();
    final dateMs = _dateToMs(now);

    final signature = _computeSignature(
      partnerCode: SplConfig.partnerCode,
      placeCode: SplConfig.placeCode,
      date: dateMs,
    );

    return _post('/tx/checkConfig', {
      'ver': SplConfig.ver,
      'requestId': _requestId(),
      'apiUser': SplConfig.apiUser,
      'apiToken': SplConfig.apiToken,
      'partnerCode': SplConfig.partnerCode,
      'placeCode': SplConfig.placeCode,
      'date': _dateToIso(now),
      'signature': signature,
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // checkCard — Check card / balance
  // ───────────────────────────────────────────────────────────────────────────

  /// Check loyalty card or phone number. Returns balance and customer info.
  ///
  /// [cardNo] — card number or phone with country prefix (e.g. "+380501234567")
  static Future<LoyaltyCheckResult> checkCard(String cardNo) async {
    final now = DateTime.now();
    final dateMs = _dateToMs(now);

    final signature = _computeSignature(
      partnerCode: SplConfig.partnerCode,
      placeCode: SplConfig.placeCode,
      date: dateMs,
      cardNo: cardNo,
    );

    final result = await _post('/tx/checkCard', {
      'ver': SplConfig.ver,
      'requestId': _requestId(),
      'apiUser': SplConfig.apiUser,
      'apiToken': SplConfig.apiToken,
      'partnerCode': SplConfig.partnerCode,
      'placeCode': SplConfig.placeCode,
      'date': _dateToIso(now),
      'signature': signature,
      'cardNo': cardNo,
      'extendedPersonalInfo': true,
      // 'debugSignatureSkip': true, // enable for debugging
    });

    if (result['errorCode']?.toString() != '0') {
      return LoyaltyCheckResult(
        success: false,
        errorMsg: result['msg']?.toString() ?? 'Помилка API',
      );
    }

    final resp = result['response'] as Map<String, dynamic>? ?? {};
    final person = resp['person'] as Map<String, dynamic>?;

    return LoyaltyCheckResult(
      success: true,
      balanceAfter: (resp['balanceAfter'] as num?)?.toDouble() ?? 0,
      cardNo: person?['cardNo']?.toString() ?? cardNo,
      firstName: person?['firstName']?.toString(),
      lastName: person?['lastName']?.toString(),
      mobile: person?['mobile']?.toString(),
      messages: _extractMessages(resp),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // sale — Sale transaction (NGD one-phase)
  // ───────────────────────────────────────────────────────────────────────────

  /// Send sale transaction to SPL.
  ///
  /// [receiptNo] — POS receipt number
  /// [basket] — list of {productCode, quantity, amountGross}
  /// [cardNo] — loyalty card (optional for anonymous sale)
  /// [paidByPoints] — monetary amount to pay by bonus points
  /// [cashierName] — name of current pharmacist
  static Future<LoyaltySaleResult> sale({
    required String receiptNo,
    required List<Map<String, dynamic>> basket,
    String? cardNo,
    double paidByPoints = 0,
    String? cashierName,
  }) async {
    final now = DateTime.now();
    final dateMs = _dateToMs(now);

    final signature = _computeSignature(
      partnerCode: SplConfig.partnerCode,
      placeCode: SplConfig.placeCode,
      date: dateMs,
      no: receiptNo,
      cardNo: cardNo ?? '',
    );

    final body = <String, dynamic>{
      'ver': SplConfig.ver,
      'requestId': _requestId(),
      'apiUser': SplConfig.apiUser,
      'apiToken': SplConfig.apiToken,
      'mode': 'NGD',
      'partnerCode': SplConfig.partnerCode,
      'placeCode': SplConfig.placeCode,
      'date': _dateToIso(now),
      'no': receiptNo,
      'signature': signature,
      'basket': basket,
      // 'debugSignatureSkip': true, // enable for debugging
    };

    if (cardNo != null && cardNo.isNotEmpty) {
      body['cardNo'] = cardNo;
    }
    if (paidByPoints > 0) {
      body['paidByPoints'] = paidByPoints;
    }
    if (cashierName != null) {
      body['regUserName'] = cashierName;
    }

    final result = await _post('/tx/sale', body);

    if (result['errorCode']?.toString() != '0') {
      return LoyaltySaleResult(
        success: false,
        errorMsg: result['msg']?.toString() ?? 'Помилка API',
      );
    }

    final resp = result['response'] as Map<String, dynamic>? ?? {};

    return LoyaltySaleResult(
      success: true,
      balanceBurn: (resp['balanceBurn'] as num?)?.toDouble() ?? 0,
      balanceEarn: (resp['balanceEarn'] as num?)?.toDouble() ?? 0,
      balanceAfter: (resp['balanceAfter'] as num?)?.toDouble() ?? 0,
      messages: _extractMessages(resp),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // customer/find — Find customer by phone
  // ───────────────────────────────────────────────────────────────────────────

  /// Find customer by phone number (without country prefix).
  ///
  /// [phone] — phone number without +380 prefix (e.g. "501234567")
  static Future<LoyaltyCheckResult> findByPhone(String phone) async {
    final now = DateTime.now();
    final dateMs = _dateToMs(now);

    final signature = _computeSignature(
      partnerCode: SplConfig.partnerCode,
      placeCode: SplConfig.placeCode,
      date: dateMs,
    );

    final result = await _post('/customer/find', {
      'ver': SplConfig.ver,
      'requestId': _requestId(),
      'apiUser': SplConfig.apiUser,
      'apiToken': SplConfig.apiToken,
      'partnerCode': SplConfig.partnerCode,
      'placeCode': SplConfig.placeCode,
      'date': _dateToIso(now),
      'signature': signature,
      'mobileCountry': '+380',
      'mobile': phone,
      // 'debugSignatureSkip': true, // enable for debugging
    });

    if (result['errorCode']?.toString() != '0') {
      return LoyaltyCheckResult(
        success: false,
        errorMsg: result['msg']?.toString() ?? 'Клієнта не знайдено',
      );
    }

    final resp = result['response'] as Map<String, dynamic>? ?? {};
    final persons = resp['persons'] as List? ?? [];

    if (persons.isEmpty) {
      return LoyaltyCheckResult(
        success: false,
        errorMsg: 'Клієнта не знайдено',
      );
    }

    final person = persons.first as Map<String, dynamic>;
    return LoyaltyCheckResult(
      success: true,
      cardNo: person['cardNo']?.toString(),
      firstName: person['firstName']?.toString(),
      lastName: person['lastName']?.toString(),
      mobile: person['mobile']?.toString(),
    );
  }
}
