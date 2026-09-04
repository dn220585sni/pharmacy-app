import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/spl_params.dart';
import 'fiscal_log.dart';
import 'spl_params_service.dart';

/// Конфігурація Sparta Loyalty Platform (ЛАЙК).
///
/// Значення нижче — дефолти (dart_define / demo). На старті зміни
/// перевизначаються реальними per-аптека кредами з `GetSPLParam` (Задача 26)
/// через [applyFrom]. Тому поля креди — мутабельні `static`, а не `const`.
class SplConfig {
  static String baseUrl = 'https://demo.spartaloyalty.com/TestAnc2/api';
  static const apiUser = 'anc_pos';
  // Дефолт-секрети — через --dart-define-from-file (gitignored); на проді їх
  // перекриває GetSPLParam.
  static String apiToken = const String.fromEnvironment('SPL_API_TOKEN');
  static String posKey = const String.fromEnvironment('SPL_POS_KEY');
  static const partnerCode = 'ANC';
  static String placeCode = 'MR_TEST_PLACE';
  static const ver = 4;
  static Duration timeout = const Duration(seconds: 5);

  /// Чи вже застосовано живі креди з GetSPLParam (щоб не тягнути повторно).
  static bool loadedFromServer = false;

  /// Перекрити креди реальними з GetSPLParam. baseUrl нормалізуємо (прибираємо
  /// завершальний '/'), бо ендпоінти LoyaltyService йдуть з ведучим '/tx/...'.
  static void applyFrom(SplParams p) {
    if (!p.isUsable) return;
    baseUrl = _stripTrailingSlash(p.baseUrl.trim());
    posKey = p.posKey;
    apiToken = p.apiToken;
    placeCode = p.placeCode;
    if (p.timeoutSeconds > 0) timeout = Duration(seconds: p.timeoutSeconds);
    loadedFromServer = true;
    debugPrint('SplConfig: живі креди з GetSPLParam застосовано '
        '(placeCode=$placeCode, baseUrl=$baseUrl)');
  }

  static String _stripTrailingSlash(String u) {
    var s = u;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
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

  /// Анкетні додатки Спарти: `code` → `value` з `addonsList`.
  ///
  /// Значення різнотипні: рядок (`"yes"`), число (`children: 1`), список
  /// (`chronic: ["CHRON1","CHRON2"]`) або `null`, якщо поле не заповнене.
  final Map<String, dynamic> addons;

  LoyaltyCheckResult({
    required this.success,
    this.balanceAfter = 0,
    this.firstName,
    this.lastName,
    this.mobile,
    this.cardNo,
    this.errorMsg,
    this.messages = const [],
    this.addons = const {},
  });

  /// Анкетне «Получать эл-й чек» — код `cashreceipt`.
  ///
  /// Назва оманлива: `yes` означає, що клієнт отримує ЕЛЕКТРОННИЙ чек, тож
  /// папір НЕ друкуємо; `no` — друкуємо. Розбирає це
  /// `ReceiptPrintRule.electronicFromAnketa`, а не цей геттер: тут лише сире
  /// значення, `null` — поля в анкеті немає.
  String? get cashReceipt => addons['cashreceipt']?.toString();
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

  /// `addonsList` → `code` → `value`.
  ///
  /// Формат підтверджено листом Андрія (03.09.2026): масив обʼєктів
  /// `{"code":…, "value":…, "valueAsDictLabel":…}`. Беремо `value`:
  /// `valueAsDictLabel` — те саме, лише відформатоване для показу (дати там
  /// перетворені на «Thu Aug 27 11:30:53 CEST 2026»).
  @visibleForTesting
  static Map<String, dynamic> addonsFrom(Map<String, dynamic>? person) {
    final list = person?['addonsList'];
    if (list is! List) return const {};
    final out = <String, dynamic>{};
    for (final e in list) {
      if (e is! Map) continue;
      final code = e['code']?.toString() ?? '';
      if (code.isEmpty) continue;
      out[code] = e['value'];
    }
    return out;
  }

  /// Діагностика: які поля анкети реально повертає Спарта.
  ///
  /// Привід — правило друку чека (Андрій, 03.09): друкуємо лише тоді, коли в
  /// анкеті «Получать эл-й чек» = `no`; інакше чек електронний. Такого поля ми
  /// нікуди не мапимо, і невідомо, чи воно взагалі приходить — `person` ми
  /// розбираємо на чотири поля, решту мовчки викидаємо. `extendedPersonalInfo`
  /// ми вже шлемо, тож відповідь цілком може його містити.
  ///
  /// У журнал ідуть ІМЕНА полів; значення — лише для прапорців
  /// (`true`/`false`/`yes`/`no`/`0`/`1`). Персональні дані так не витечуть.
  static void _logPersonShape(Map<String, dynamic>? person, String source) {
    if (person == null || person.isEmpty) return;
    const flagish = {'true', 'false', 'yes', 'no', '0', '1', 'y', 'n'};
    final parts = person.entries.map((e) {
      final v = e.value;
      if (v is bool) return '${e.key}=$v';
      if (v is List) return '${e.key}[${v.length}]';
      if (v is Map) return '${e.key}{${v.keys.join("|")}}';
      final s = v?.toString().trim().toLowerCase() ?? '';
      if (flagish.contains(s)) return '${e.key}=$s';
      if (s.isEmpty) return '${e.key}=∅';
      return e.key;
    });
    FiscalLog.log('SPL $source: поля анкети — ${parts.join(", ")}');
  }

  /// Гарантувати, що застосовано живі креди з GetSPLParam (раз на сесію).
  /// Викликається перед сигнатурними викликами (checkCard/sale). Якщо
  /// GetSPLParam недоступний — лишаються дефолтні (dart_define/demo) креди.
  static Future<void> _ensureConfig() async {
    if (SplConfig.loadedFromServer) return;
    final p = await SplParamsService.fetch();
    if (p != null) SplConfig.applyFrom(p);
  }

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

      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
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
    await _ensureConfig();
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
    _logPersonShape(person, 'checkCard');

    return LoyaltyCheckResult(
      success: true,
      balanceAfter: (resp['balanceAfter'] as num?)?.toDouble() ?? 0,
      cardNo: person?['cardNo']?.toString() ?? cardNo,
      firstName: person?['firstName']?.toString(),
      lastName: person?['lastName']?.toString(),
      mobile: person?['mobile']?.toString(),
      messages: _extractMessages(resp),
      addons: addonsFrom(person),
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
    await _ensureConfig();
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
    _logPersonShape(person, 'customer/find');
    return LoyaltyCheckResult(
      success: true,
      cardNo: person['cardNo']?.toString(),
      firstName: person['firstName']?.toString(),
      lastName: person['lastName']?.toString(),
      mobile: person['mobile']?.toString(),
      addons: addonsFrom(person),
    );
  }
}
