import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/spl_params.dart';
import 'sparta_signature.dart';

/// Результат виклику Спарти.
class SpartaResult {
  /// `errorCode == '0'` → успіх.
  final bool ok;
  final String? errorCode;
  final String? msg;

  /// `response`-обʼєкт відповіді (баланс, нараховані бонуси, basket тощо).
  final Map<String, dynamic> response;

  const SpartaResult({
    required this.ok,
    this.errorCode,
    this.msg,
    this.response = const {},
  });

  factory SpartaResult.fromJson(Map<String, dynamic> j) {
    final code = j['errorCode']?.toString();
    final resp = j['response'];
    return SpartaResult(
      ok: code == '0',
      errorCode: code,
      msg: j['msg']?.toString(),
      response: resp is Map<String, dynamic> ? resp : const {},
    );
  }

  factory SpartaResult.failure(String msg) =>
      SpartaResult(ok: false, errorCode: 'CLIENT', msg: msg);

  // Дані з response `tx/order` для наступних кроків ланцюга.
  // ⚠️ Точні ключі відповіді Спарти НЕ підтверджені — беремо з кількох
  // ймовірних варіантів; на першому живому тесті звірити з логом response.
  double _num(List<String> keys) {
    for (final k in keys) {
      final v = response[k];
      if (v is num) return v.toDouble();
      final p = double.tryParse(v?.toString() ?? '');
      if (p != null) return p;
    }
    return 0;
  }

  /// Ідентифікатор транзакції ЛАЙК (для PutKasaSPL). Спарта віддає його як
  /// `processId` (підтверджено живою відповіддю tx/order 2026-07-20);
  /// решта — запасні варіанти.
  String? get prId => (response['processId'] ??
          response['prId'] ??
          response['transactionId'] ??
          response['id'])
      ?.toString();

  /// Нараховано бонусів за покупку.
  double get balanceEarn => _num(['balanceEarn', 'earn']);

  /// Списано/заощаджено бонусів.
  double get balanceBurn => _num(['balanceBurn', 'burn']);

  /// Баланс після операції.
  double get balanceAfter => _num(['balanceAfter', 'balance', 'after']);
}

/// Клієнт Спарти (ЛАЙК) — реєстрація/підтвердження транзакції чека.
///
/// Креди беруться з [SplParams] (GetSPLParam): `posKey` (підпис), `apiToken`,
/// `placeCode`, `baseUrl`. Підпис — [SpartaSignature] (розділ 1.6.3).
///
/// Послідовність у фіскальному флоу:
///   [order] (pending) → ПРРО фіскалізація → [orderModify] (+cashreceiptlinkurl)
///   → [orderStatusChange] (`D` → store).
class SpartaService {
  final SplParams config;

  /// `posCode` = код каси (ekkKodKli). Передаємо явно, бо у [SplParams] його нема.
  final String posCode;

  SpartaService(this.config, {required this.posCode});

  // Константи роздробу (джерело partnerCode/apiUser уточнити; на demo — ANC/anc_pos).
  static const _partnerCode = 'ANC';
  static const _apiUser = 'anc_pos';
  static const _regUserName = 'PRRO';

  /// Спільний keep-alive клієнт (не створюємо новий на кожен запит — зайвий
  /// TCP+TLS handshake). НЕ закриваємо після запиту.
  static final http.Client _client = http.Client();

  /// `tx/order` — реєстрація в статусі pending (hold).
  /// Підпис: `partnerCode+placeCode+posCode+date+no+cardNo`.
  /// Масиви [basket]/[mops]/[params]/[coupons] — готовий JSON (від Caché або зібраний клієнтом).
  Future<SpartaResult> order({
    required String no,
    required String orderNo,
    required DateTime date,
    required String cardNo,
    required List<Map<String, dynamic>> basket,
    required List<Map<String, dynamic>> mops,
    List<Map<String, dynamic>> params = const [],
    List<Map<String, dynamic>> coupons = const [],
    num amountGross = 0,
    num discountGross = 0,
    num paidByPoints = 0,
    String documentNo = '',
  }) {
    final body = _orderBody(
      no: no, orderNo: orderNo, date: _seconds(date), cardNo: cardNo,
      basket: basket, mops: mops, params: params, coupons: coupons,
      amountGross: amountGross, discountGross: discountGross,
      paidByPoints: paidByPoints, documentNo: documentNo,
    );
    return _post('tx/order', body);
  }

  /// `tx/orderModify` — той самий payload, що [order], + у `params` додається
  /// `{code:"cashreceiptlinkurl", value:<link з ПРРО>}`. Той самий підпис.
  Future<SpartaResult> orderModify({
    required String no,
    required String orderNo,
    required DateTime date,
    required String cardNo,
    required List<Map<String, dynamic>> basket,
    required List<Map<String, dynamic>> mops,
    required String cashReceiptLinkUrl,
    List<Map<String, dynamic>> params = const [],
    List<Map<String, dynamic>> coupons = const [],
    num amountGross = 0,
    num discountGross = 0,
    num paidByPoints = 0,
    String documentNo = '',
  }) {
    final withLink = [
      ...params,
      {'code': 'cashreceiptlinkurl', 'value': cashReceiptLinkUrl},
    ];
    final body = _orderBody(
      no: no, orderNo: orderNo, date: _seconds(date), cardNo: cardNo,
      basket: basket, mops: mops, params: withLink, coupons: coupons,
      amountGross: amountGross, discountGross: discountGross,
      paidByPoints: paidByPoints, documentNo: documentNo,
    );
    return _post('tx/orderModify', body);
  }

  /// `tx/orderStatusChange` — pending → store (`D`) або скасування (`C`).
  /// Підпис: `partnerCode+placeCode+date`.
  Future<SpartaResult> orderStatusChange({
    required String orderNo,
    required DateTime date,
    String status = 'D',
  }) {
    date = _seconds(date);
    final signature = SpartaSignature.compute(
      SpartaSignature.chain([
        SpartaSignature.encodeString(_partnerCode),
        SpartaSignature.encodeString(config.placeCode),
        SpartaSignature.encodeDateMs(date),
      ]),
      config.posKey,
    );
    final body = <String, dynamic>{
      'apiToken': config.apiToken,
      'apiUser': _apiUser,
      'date': _iso8601(date),
      'debugSignatureExplain': true,
      'lng': '',
      'orderNo': orderNo,
      'partnerCode': _partnerCode,
      'placeCode': config.placeCode,
      'requestId': '',
      'signature': signature,
      'status': status,
    };
    return _post('tx/orderStatusChange', body);
  }

  // ── Внутрішнє ──────────────────────────────────────────────────────────────

  /// Підпис order/orderModify: `partnerCode+placeCode+posCode+date+no+cardNo`.
  String _orderSignature(DateTime date, String no, String cardNo) =>
      SpartaSignature.compute(
        SpartaSignature.chain([
          SpartaSignature.encodeString(_partnerCode),
          SpartaSignature.encodeString(config.placeCode),
          SpartaSignature.encodeString(posCode),
          SpartaSignature.encodeDateMs(date),
          SpartaSignature.encodeString(no),
          SpartaSignature.encodeString(cardNo),
        ]),
        config.posKey,
      );

  Map<String, dynamic> _orderBody({
    required String no,
    required String orderNo,
    required DateTime date,
    required String cardNo,
    required List<Map<String, dynamic>> basket,
    required List<Map<String, dynamic>> mops,
    required List<Map<String, dynamic>> params,
    required List<Map<String, dynamic>> coupons,
    required num amountGross,
    required num discountGross,
    required num paidByPoints,
    required String documentNo,
  }) {
    return <String, dynamic>{
      'partnerCode': _partnerCode,
      'placeCode': config.placeCode,
      'posCode': posCode,
      'apiUser': _apiUser,
      'apiToken': config.apiToken,
      'regUserName': _regUserName,
      'date': _iso8601(date),
      'no': no,
      'orderNo': orderNo,
      'documentNo': documentNo,
      'cardNo': cardNo,
      'mode': 'NGD',
      'ver': 2,
      'pending': true,
      'checkOnly': false,
      'reverse': false,
      'isOffline': false,
      'amountGross': amountGross,
      'discountGross': discountGross,
      'paidByPoints': paidByPoints,
      'basket': basket,
      'mops': mops,
      'coupons': coupons,
      'params': params,
      'debugSignatureExplain': true,
      'signature': _orderSignature(date, no, cardNo),
    };
  }

  Future<SpartaResult> _post(String endpoint, Map<String, dynamic> body) async {
    final url = '${config.baseUrl}$endpoint';
    try {
      final resp = await _client
          .post(Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(Duration(
              seconds: config.timeoutSeconds > 0 ? config.timeoutSeconds : 15));
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      final result = SpartaResult.fromJson(json);
      debugPrint('Sparta $endpoint: errorCode=${result.errorCode} msg=${result.msg}');
      return result;
    } on TimeoutException {
      return SpartaResult.failure('Таймаут Спарти ($endpoint)');
    } on SocketException {
      return SpartaResult.failure('Немає звʼязку зі Спартою ($endpoint)');
    } catch (e) {
      debugPrint('Sparta $endpoint ERROR: $e');
      return SpartaResult.failure('Помилка Спарти: $e');
    }
  }

  /// Обрізати до цілих секунд: ISO-рядок `date` йде без мілісекунд, тож і ms у
  /// підписі мають бути секундними (інакше сервер порахує інший ms → AUTH_FAILED).
  static DateTime _seconds(DateTime dt) => DateTime.fromMillisecondsSinceEpoch(
        (dt.millisecondsSinceEpoch ~/ 1000) * 1000,
        isUtc: dt.isUtc,
      );

  /// ISO 8601 з локальним зсувом TZ (напр. `2026-06-24T12:00:00+03:00`).
  static String _iso8601(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final off = d.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final oh = two(off.inHours.abs());
    final om = two(off.inMinutes.abs() % 60);
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'
        'T${two(d.hour)}:${two(d.minute)}:${two(d.second)}$sign$oh:$om';
  }
}
