import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Конфігурація ПРРО (CashDesk).
class PrroConfig {
  /// Тестовий сервер.
  static const baseUrl = 'https://test.cashdesk.com.ua/api/v2';

  /// Облікові дані для авторизації.
  static const email = '4000952779@anc.net.ua';
  static const password = '123456';

  /// Developer ID (обов'язковий заголовок).
  static const developerId = 'ANC';

  /// Фіскальний номер РРО.
  static const numFiscal = 4000952775;
}

/// Результат операції ПРРО.
class PrroResult {
  final bool success;
  final String? checkId;      // UUID чеку (uuid)
  final String? orderNum;     // Номер чеку (ORDERNUM)
  final String? orderDate;    // Дата чеку (ORDERDATE)
  final String? orderTime;    // Час чеку (ORDERTIME)
  final String? qrData;       // URL для QR-коду
  final String? qrBase64;     // QR-код як base64 PNG
  final String? textPrint;    // Текстове представлення чеку (base64)
  final String? pdfBase64;    // PDF чеку (base64)
  final String? link;         // Посилання на чек на сайті
  final bool isOffline;       // Ознака офлайн чеку
  final String? error;

  const PrroResult({
    required this.success,
    this.checkId,
    this.orderNum,
    this.orderDate,
    this.orderTime,
    this.qrData,
    this.qrBase64,
    this.textPrint,
    this.pdfBase64,
    this.link,
    this.isOffline = false,
    this.error,
  });
}

/// Товар для фіскального чеку.
class PrroProduct {
  final String name;
  final double amount;
  final double price;
  final double cost;          // amount * price (з урахуванням знижки)
  final String? code;         // внутрішній код товару
  final String? barcode;      // штрихкод
  final String letters;       // податкова група: "А" (ПДВ 20%), "Б" (ПДВ 7%), "-Н" (без ПДВ)
  final double taxPrc;        // ставка податку
  final String unitName;      // одиниця виміру
  final String? unitCode;     // код одиниці виміру (КСПОВО)
  final double? discount;     // сума знижки

  const PrroProduct({
    required this.name,
    required this.amount,
    required this.price,
    required this.cost,
    this.code,
    this.barcode,
    this.letters = 'Б',       // аптека — ПДВ 7%
    this.taxPrc = 7,
    this.unitName = 'штука',
    this.unitCode = '2009',
    this.discount,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'price': price,
    'cost': cost,
    if (code != null) 'code': code,
    if (barcode != null) 'bar_code': barcode,
    'letters': letters,
    'tax_prc': taxPrc,
    'unit_name': unitName,
    if (unitCode != null) 'unit_code': unitCode,
    if (discount != null && discount! > 0) 'sum_discount': discount,
  };
}

/// Оплата для фіскального чеку.
class PrroPayment {
  final int code;             // 0 = готівка, 1 = картка
  final String name;
  final double sum;
  final double sumProvided;   // скільки надав клієнт
  final double sumRemains;    // здача

  const PrroPayment({
    required this.code,
    required this.name,
    required this.sum,
    required this.sumProvided,
    this.sumRemains = 0,
  });

  /// Готівка.
  factory PrroPayment.cash({
    required double sum,
    double? provided,
  }) {
    final p = provided ?? sum;
    return PrroPayment(
      code: 0,
      name: 'ГОТІВКА',
      sum: sum,
      sumProvided: p,
      sumRemains: (p - sum).clamp(0, double.infinity),
    );
  }

  /// Картка.
  factory PrroPayment.card({required double sum}) {
    return PrroPayment(
      code: 1,
      name: 'КАРТКА',
      sum: sum,
      sumProvided: sum,
      sumRemains: 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'sum': sum,
    'sum_provided': sumProvided,
    'sum_remains': sumRemains,
  };
}

/// Сервіс ПРРО (програмний реєстратор розрахункових операцій).
///
/// API: CashDesk (cashdesk.com.ua)
/// Документація: https://documenter.getpostman.com/view/12128952/TVRj5U1d
class PrroService {
  static final _client = http.Client();
  static String? _token;

  static Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'developer-id': PrroConfig.developerId,
    if (_token != null) 'Authorization': _token!,
  };

  // ---------------------------------------------------------------------------
  // Авторизація
  // ---------------------------------------------------------------------------

  /// Авторизуватися в ПРРО. Отримує Bearer token.
  static Future<bool> authenticate() async {
    try {
      final response = await _client.post(
        Uri.parse('${PrroConfig.baseUrl}/authenticate'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'developer-id': PrroConfig.developerId,
        },
        body: jsonEncode({
          'email': PrroConfig.email,
          'password': PrroConfig.password,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('PRRO auth FAIL: HTTP ${response.statusCode}');
        return false;
      }

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      _token = json['token']?.toString();
      final shift = json['opened_shift']?.toString();
      debugPrint('PRRO auth OK: shift=$shift token=${_token != null ? "present" : "null"}');
      return _token != null;
    } catch (e) {
      debugPrint('PRRO auth ERROR: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Чек продажу
  // ---------------------------------------------------------------------------

  /// Створити фіскальний чек продажу.
  ///
  /// [products] — список товарів
  /// [payments] — список оплат (готівка/картка)
  /// [totalSum] — загальна сума чеку
  static Future<PrroResult> createSaleReceipt({
    required List<PrroProduct> products,
    required List<PrroPayment> payments,
    required double totalSum,
  }) async {
    if (_token == null) {
      final ok = await authenticate();
      if (!ok) return const PrroResult(success: false, error: 'Помилка авторизації ПРРО');
    }

    try {
      final body = {
        'num_fiscal': PrroConfig.numFiscal,
        'action_type': 'Z_SALE',
        'total_sum': totalSum,
        'products': products.map((p) => p.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'open_shift': true,
        'no_pdf': true,
        'no_qr': false,
        'no_text_print': false,
      };

      debugPrint('PRRO sale: ${products.length} products, total=$totalSum');

      final response = await _client.post(
        Uri.parse('${PrroConfig.baseUrl}/check/sale'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = PrroResult(
          success: true,
          checkId: json['uuid']?.toString(),
          orderNum: json['ORDERNUM']?.toString(),
          orderDate: json['ORDERDATE']?.toString(),
          orderTime: json['ORDERTIME']?.toString(),
          qrData: json['qr_data']?.toString(),
          qrBase64: json['qr']?.toString(),
          textPrint: json['text_print']?.toString(),
          pdfBase64: json['pdf']?.toString(),
          link: json['link']?.toString(),
          isOffline: json['is_offline'] == true,
        );
        debugPrint('PRRO sale OK: orderNum=${result.orderNum} checkId=${result.checkId} '
            'link=${result.link}');
        return result;
      } else {
        final error = json['message']?.toString() ?? 'Помилка ПРРО (${response.statusCode})';
        debugPrint('PRRO sale FAIL: $error data=$json');
        return PrroResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('PRRO sale ERROR: $e');
      return PrroResult(success: false, error: 'Помилка з\'єднання з ПРРО');
    }
  }

  // ---------------------------------------------------------------------------
  // Чек повернення
  // ---------------------------------------------------------------------------

  /// Створити фіскальний чек повернення.
  static Future<PrroResult> createReturnReceipt({
    required List<PrroProduct> products,
    required List<PrroPayment> payments,
    required double totalSum,
  }) async {
    if (_token == null) {
      final ok = await authenticate();
      if (!ok) return const PrroResult(success: false, error: 'Помилка авторизації ПРРО');
    }

    try {
      final body = {
        'num_fiscal': PrroConfig.numFiscal,
        'action_type': 'Z_RETURN',
        'total_sum': totalSum,
        'products': products.map((p) => p.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'open_shift': true,
        'no_pdf': true,
        'no_qr': false,
        'no_text_print': false,
      };

      final response = await _client.post(
        Uri.parse('${PrroConfig.baseUrl}/check/sale'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final checkId = json['uuid']?.toString() ?? json['id']?.toString();
        debugPrint('PRRO return OK: checkId=$checkId');
        return PrroResult(success: true, checkId: checkId);
      } else {
        final error = json['message']?.toString() ?? 'Помилка ПРРО';
        return PrroResult(success: false, error: error);
      }
    } catch (e) {
      debugPrint('PRRO return ERROR: $e');
      return PrroResult(success: false, error: 'Помилка з\'єднання з ПРРО');
    }
  }

  // ---------------------------------------------------------------------------
  // Отримання чеку
  // ---------------------------------------------------------------------------

  /// Отримати текстове представлення чеку.
  static Future<String?> getReceiptText(String checkId) async {
    try {
      final url = '${PrroConfig.baseUrl}/checks/$checkId/text?print_width=48';
      final response = await _client.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return utf8.decode(response.bodyBytes);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Отримати QR-код чеку як URL.
  static Future<String?> getReceiptQr(String checkId) async {
    try {
      final url = '${PrroConfig.baseUrl}/checks/$checkId/qr?ascii=1';
      final response = await _client.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return utf8.decode(response.bodyBytes);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
