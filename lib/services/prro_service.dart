import 'dart:async';
import '../models/money.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Середовище ПРРО.
///
/// В аптеці використовується SmartConnect — локальний offline-додаток
/// від CashDesk на ПК у БЦ-26 (10.15.30.61). Він сам тримає офлайн-чергу
/// і пушить чеки коли інтернет з'являється. Для розробки зручніше
/// використовувати хмарну пісочницю.
enum PrroEnvironment {
  /// Хмарна пісочниця податкової — для розробки.
  cloudTest('https://test.cashdesk.com.ua/api/v2'),

  /// Локальний SmartConnect, тестовий порт.
  smartConnectTest('http://10.15.30.61:8000/api/v2'),

  /// Локальний SmartConnect, прод порт.
  smartConnectProd('http://10.15.30.61:8001/api/v2');

  const PrroEnvironment(this.baseUrl);
  final String baseUrl;
}

/// Конфігурація ПРРО (CashDesk).
class PrroConfig {
  /// Активне середовище. Змінити на `smartConnectTest`/`smartConnectProd`
  /// при деплої на робоче місце аптеки.
  static const environment = PrroEnvironment.cloudTest;

  /// Облікові дані для авторизації.
  /// Передаються через --dart-define-from-file=dart_define.json (gitignored).
  /// Порожні за замовчуванням — без файлу авторизація впаде явно.
  static const email = String.fromEnvironment('PRRO_EMAIL');
  static const password = String.fromEnvironment('PRRO_PASSWORD');

  /// Developer ID (обов'язковий заголовок).
  static const developerId = 'ANC';

  /// Фіскальний номер РРО за замовчуванням.
  /// Реальний номер визначається з `opened_shift` після авторизації
  /// (див. [PrroService.activeFiscalNumber]).
  /// 4000952779 — тестовий ФН з відкритою через SmartConnect зміною
  /// (Дмитрій-тестировщик 2026-05-11). Не пересікається з online-розничкою.
  static const numFiscal = 4000952779;

  /// Хост хмарного кабінету (для read-only перегляду каси).
  static const cabinetHost = 'https://test.cashdesk.com.ua';

  /// ⚠️ Mock-режим: повертати синтетичний успіх замість реального API.
  /// `false` — реальна фіскалізація через cloud test API. Підтверджено
  /// 2026-05-12 на ФН 4000952779 (sale uuid=7ecd45bb…, ORDERNUM=IIh3g-eh-Ak).
  static const useMockSuccess = false;
}

/// Тип помилки ПРРО — щоб виклик міг розрізнити мережеву проблему
/// (відкласти у чергу) і логічну помилку (заблокувати продаж).
enum PrroErrorKind {
  /// Помилка мережі / SmartConnect не запущений / timeout — кандидат на чергу.
  connection,

  /// Логічна помилка від API (некоректні дані, відмова податкової тощо).
  logical,

  /// Помилка авторизації — токен невалідний.
  auth,
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
  final PrroErrorKind? errorKind;

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
    this.errorKind,
  });

  const PrroResult.failure({
    required String this.error,
    required PrroErrorKind this.errorKind,
  })  : success = false,
        checkId = null,
        orderNum = null,
        orderDate = null,
        orderTime = null,
        qrData = null,
        qrBase64 = null,
        textPrint = null,
        pdfBase64 = null,
        link = null,
        isOffline = false;
}

/// Товар для фіскального чеку.
class PrroProduct {
  final String name;
  final double amount;
  final double price;
  final double cost;          // amount * price (з урахуванням знижки)
  final String? code;         // внутрішній код товару
  final String? barcode;      // штрихкод
  /// Податкова група. Поле опціональне — без нього ПРРО рахує податок з [taxPrc].
  /// УВАГА: формат значення НЕ зрозумілий з документації; cloud test API
  /// відхиляє літери 'А'/'В'/'Б'/'B'/'A' з помилкою "invalid". Поки
  /// безпечніше залишати null.
  final String? letters;
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
    this.letters,
    this.taxPrc = 7,          // ліки — ПДВ 7% (дефолт)
    this.unitName = 'штука',
    this.unitCode = '2009',
    this.discount,
  });

  /// Створити з ознакою "лікарський засіб". Автоматично проставляє ставку.
  factory PrroProduct.classified({
    required String name,
    required double amount,
    required double price,
    required double cost,
    required bool isMedicine,
    String? code,
    String? barcode,
    String unitName = 'штука',
    String? unitCode = '2009',
    double? discount,
  }) {
    return PrroProduct(
      name: name,
      amount: amount,
      price: price,
      cost: cost,
      code: code,
      barcode: barcode,
      taxPrc: isMedicine ? 7 : 20,
      unitName: unitName,
      unitCode: unitCode,
      discount: discount,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'price': price,
    'cost': cost,
    if (code != null) 'code': code,
    if (barcode != null) 'bar_code': barcode,
    if (letters != null) 'letters': letters,
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

/// Чек у списку зміни (елемент `checks_list` з X-звіту).
class PrroShiftCheck {
  final String type;          // "Z_SALE", "Z_RETURN" тощо
  final String orderNum;      // фіскальний номер
  final String? datetime;     // "DD.MM.YYYY HH:MM:SS"
  final int? localNumber;     // наш номер з Caché
  final double sum;

  const PrroShiftCheck({
    required this.type,
    required this.orderNum,
    required this.sum,
    this.datetime,
    this.localNumber,
  });

  factory PrroShiftCheck.fromJson(Map<String, dynamic> json) => PrroShiftCheck(
        type: json['type']?.toString() ?? '',
        orderNum: json['order_num']?.toString() ?? '',
        datetime: json['datetime']?.toString(),
        localNumber: (json['local_number'] as num?)?.toInt(),
        sum: (json['sum'] as num?)?.toDouble() ?? 0,
      );
}

/// Результат X-звіту (поточний стан зміни без закриття).
class PrroXReport {
  final bool shiftOpen;
  final int? shiftDurationMinutes;
  final double cashInBox;
  final int ordersCount;
  final double ordersSum;
  final List<PrroShiftCheck> checks;
  final String? pdfBase64;
  final String? textPrint;

  const PrroXReport({
    required this.shiftOpen,
    required this.cashInBox,
    required this.ordersCount,
    required this.ordersSum,
    required this.checks,
    this.shiftDurationMinutes,
    this.pdfBase64,
    this.textPrint,
  });

  /// Терпиме до формату: bool `true`, `1`, `"1"`, `"true"` → true.
  static bool _truthy(dynamic v) =>
      v == true ||
      v == 1 ||
      (v is String && (v == '1' || v.toLowerCase() == 'true'));

  /// num або рядок → int (напр. `shift_duration` може прийти рядком).
  static int? _flexInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  factory PrroXReport.fromJson(Map<String, dynamic> json) {
    final real = json['real'] as Map<String, dynamic>? ?? const {};
    final list = (json['checks_list'] as List?) ?? const [];
    return PrroXReport(
      shiftOpen: _truthy(json['shift_state']),
      cashInBox: (json['cash_in_box'] as num?)?.toDouble() ?? 0,
      shiftDurationMinutes: _flexInt(json['shift_duration']),
      ordersCount: (real['orders_count'] as num?)?.toInt() ?? 0,
      ordersSum: (real['sum'] as num?)?.toDouble() ?? 0,
      checks: list
          .whereType<Map<String, dynamic>>()
          .map(PrroShiftCheck.fromJson)
          .toList(growable: false),
      pdfBase64: json['pdf']?.toString(),
      textPrint: json['text_print']?.toString(),
    );
  }
}

/// Сервіс ПРРО (програмний реєстратор розрахункових операцій).
///
/// API: CashDesk (cashdesk.com.ua)
/// Документація: https://documenter.getpostman.com/view/12128952/TVRj5U1d
class PrroService {
  static final _client = http.Client();
  static String? _token;
  static DateTime? _tokenExpiresAt;
  static int? _activeFiscalNumber;

  /// TEMP-діагностика A4: що останнього разу повернув xReport (для показу в UI).
  static String? lastXReportDebug;

  /// Активний фіскальний номер. Береться з `opened_shift` після авторизації;
  /// fallback — `PrroConfig.numFiscal`.
  static int get activeFiscalNumber =>
      _activeFiscalNumber ?? PrroConfig.numFiscal;

  static Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'developer-id': PrroConfig.developerId,
        // ignore: use_null_aware_elements
        if (_token != null) 'Authorization': _token!,
      };

  // ---------------------------------------------------------------------------
  // Token cache (file-based persistence через path_provider)
  // ---------------------------------------------------------------------------

  static const _tokenFileName = 'prro_token.json';

  static Future<File?> _tokenFile() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_tokenFileName');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persistToken() async {
    final file = await _tokenFile();
    if (file == null || _token == null) return;
    try {
      await file.writeAsString(jsonEncode({
        'token': _token,
        'expires_at': _tokenExpiresAt?.toIso8601String(),
        'fiscal': _activeFiscalNumber,
        'env': PrroConfig.environment.name,
      }));
    } catch (e) {
      debugPrint('PRRO token persist FAIL: $e');
    }
  }

  /// Завантажити кешований токен. Викликати при старті.
  static Future<void> loadCachedToken() async {
    final file = await _tokenFile();
    if (file == null || !await file.exists()) return;
    try {
      final json = jsonDecode(await file.readAsString())
          as Map<String, dynamic>;
      // Інвалідувати кеш якщо змінили середовище або фіскальний номер.
      if (json['env'] != PrroConfig.environment.name) {
        debugPrint('PRRO token cache MISS: env mismatch');
        return;
      }
      final cachedFiscal = (json['fiscal'] as num?)?.toInt();
      if (cachedFiscal != PrroConfig.numFiscal) {
        debugPrint('PRRO token cache MISS: fiscal mismatch '
            '(cached=$cachedFiscal, config=${PrroConfig.numFiscal})');
        return;
      }
      final expiresStr = json['expires_at']?.toString();
      final expires = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
      if (expires != null && expires.isBefore(DateTime.now())) return;
      _token = json['token']?.toString();
      _tokenExpiresAt = expires;
      _activeFiscalNumber = cachedFiscal;
      debugPrint('PRRO token cache HIT: fiscal=$cachedFiscal expires=$expires');
    } catch (e) {
      debugPrint('PRRO token cache FAIL: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Авторизація
  // ---------------------------------------------------------------------------

  /// Авторизуватися в ПРРО. Отримує Bearer token + opened_shift.
  static Future<bool> authenticate() async {
    try {
      final response = await _client.post(
        Uri.parse('${PrroConfig.environment.baseUrl}/authenticate'),
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
      _activeFiscalNumber =
          int.tryParse(json['opened_shift']?.toString() ?? '');
      _tokenExpiresAt = _parseExpiresAt(json['token_expires_at']?.toString());
      debugPrint('PRRO auth OK: shift=$_activeFiscalNumber '
          'expires=$_tokenExpiresAt');
      if (_token != null) await _persistToken();
      return _token != null;
    } catch (e) {
      debugPrint('PRRO auth ERROR: $e');
      return false;
    }
  }

  /// "06.05.2027 09:16" → DateTime
  static DateTime? _parseExpiresAt(String? s) {
    if (s == null) return null;
    final parts = s.split(' ');
    if (parts.length != 2) return null;
    final d = parts[0].split('.');
    final t = parts[1].split(':');
    if (d.length != 3 || t.length < 2) return null;
    return DateTime.tryParse(
      '${d[2]}-${d[1].padLeft(2, '0')}-${d[0].padLeft(2, '0')}'
      'T${t[0].padLeft(2, '0')}:${t[1].padLeft(2, '0')}:00',
    );
  }

  /// Гарантувати, що токен валідний. Якщо ні — авторизуватися.
  static Future<bool> _ensureAuth() async {
    if (_token != null &&
        (_tokenExpiresAt == null ||
            _tokenExpiresAt!.isAfter(DateTime.now().add(const Duration(minutes: 5))))) {
      return true;
    }
    return await authenticate();
  }

  // ---------------------------------------------------------------------------
  // Чек продажу
  // ---------------------------------------------------------------------------

  /// Створити фіскальний чек продажу.
  ///
  /// [products] — список товарів
  /// [payments] — список оплат (готівка/картка)
  /// [totalSum] — загальна сума чеку
  /// [localNumber] — внутрішній номер чеку з Caché (Compass).
  ///   TODO: коли буде реалізовано sgVRoznSale — підмінити timestamp-заглушку
  ///   на реальний номер з відповіді Caché.
  static Future<PrroResult> createSaleReceipt({
    required List<PrroProduct> products,
    required List<PrroPayment> payments,
    required double totalSum,
    int? localNumber,
  }) async {
    if (PrroConfig.useMockSuccess) {
      return _mockSaleSuccess(
        products: products,
        payments: payments,
        totalSum: totalSum,
        localNumber: localNumber,
      );
    }

    if (!await _ensureAuth()) {
      return const PrroResult.failure(
        error: 'Помилка авторизації ПРРО',
        errorKind: PrroErrorKind.auth,
      );
    }

    try {
      final body = <String, dynamic>{
        'num_fiscal': activeFiscalNumber,
        'action_type': 'Z_SALE',
        'total_sum': totalSum,
        'products': products.map((p) => p.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'no_pdf': true,
        'no_qr': false,
        'no_text_print': false,
        // ignore: use_null_aware_elements
        if (localNumber != null) 'local_number': localNumber,
      };

      debugPrint('PRRO sale: ${products.length} products, total=$totalSum, '
          'localNumber=$localNumber');

      final response = await _client.post(
        Uri.parse('${PrroConfig.environment.baseUrl}/check/sale'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = PrroResult(
          success: true,
          checkId: json['uuid']?.toString(),
          orderNum: json['ORDERNUM']?.toString() ?? json['order_num']?.toString(),
          orderDate: json['ORDERDATE']?.toString(),
          orderTime: json['ORDERTIME']?.toString(),
          qrData: json['qr_data']?.toString(),
          qrBase64: json['qr']?.toString(),
          textPrint: json['text_print']?.toString(),
          pdfBase64: json['pdf']?.toString(),
          link: json['link']?.toString(),
          isOffline: json['is_offline'] == true,
        );
        debugPrint('PRRO sale OK: orderNum=${result.orderNum} '
            'checkId=${result.checkId} link=${result.link} '
            'offline=${result.isOffline}');
        return result;
      } else {
        final error = json['message']?.toString() ??
            'Помилка ПРРО (${response.statusCode})';
        debugPrint('PRRO sale FAIL: $error data=$json');
        // 401 → токен прострочений, треба повторно авторизуватись.
        return PrroResult.failure(
          error: error,
          errorKind: response.statusCode == 401
              ? PrroErrorKind.auth
              : PrroErrorKind.logical,
        );
      }
    } on TimeoutException {
      debugPrint('PRRO sale TIMEOUT');
      return const PrroResult.failure(
        error: 'Таймаут з\'єднання з ПРРО',
        errorKind: PrroErrorKind.connection,
      );
    } on SocketException catch (e) {
      debugPrint('PRRO sale SOCKET: $e');
      return const PrroResult.failure(
        error: 'Немає з\'єднання з ПРРО',
        errorKind: PrroErrorKind.connection,
      );
    } catch (e) {
      debugPrint('PRRO sale ERROR: $e');
      return PrroResult.failure(
        error: 'Помилка ПРРО: $e',
        errorKind: PrroErrorKind.logical,
      );
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
    int? localNumber,
  }) async {
    if (PrroConfig.useMockSuccess) {
      return _mockSaleSuccess(
        products: products,
        payments: payments,
        totalSum: totalSum,
        localNumber: localNumber,
        isReturn: true,
      );
    }

    if (!await _ensureAuth()) {
      return const PrroResult.failure(
        error: 'Помилка авторизації ПРРО',
        errorKind: PrroErrorKind.auth,
      );
    }

    try {
      final body = <String, dynamic>{
        'num_fiscal': activeFiscalNumber,
        'action_type': 'Z_RETURN',
        'total_sum': totalSum,
        'products': products.map((p) => p.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'no_pdf': true,
        'no_qr': false,
        'no_text_print': false,
        // ignore: use_null_aware_elements
        if (localNumber != null) 'local_number': localNumber,
      };

      final response = await _client.post(
        Uri.parse('${PrroConfig.environment.baseUrl}/check/sale'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        final checkId = json['uuid']?.toString() ?? json['id']?.toString();
        debugPrint('PRRO return OK: checkId=$checkId');
        return PrroResult(success: true, checkId: checkId);
      } else {
        final error = json['message']?.toString() ?? 'Помилка ПРРО';
        return PrroResult.failure(
          error: error,
          errorKind: response.statusCode == 401
              ? PrroErrorKind.auth
              : PrroErrorKind.logical,
        );
      }
    } on TimeoutException {
      return const PrroResult.failure(
        error: 'Таймаут з\'єднання з ПРРО',
        errorKind: PrroErrorKind.connection,
      );
    } on SocketException {
      return const PrroResult.failure(
        error: 'Немає з\'єднання з ПРРО',
        errorKind: PrroErrorKind.connection,
      );
    } catch (e) {
      debugPrint('PRRO return ERROR: $e');
      return PrroResult.failure(
        error: 'Помилка ПРРО: $e',
        errorKind: PrroErrorKind.logical,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // X-звіт
  // ---------------------------------------------------------------------------

  /// X-звіт: поточний стан зміни без закриття.
  /// [includeChecks] — включати список чеків зміни.
  static Future<PrroXReport?> xReport({
    bool includeChecks = true,
    int printWidth = 40,
  }) async {
    lastXReportDebug = 'старт (fiscal=$activeFiscalNumber)';
    if (!await _ensureAuth()) {
      lastXReportDebug = 'помилка авторизації ПРРО';
      return null;
    }

    try {
      final body = {
        'num_fiscal': activeFiscalNumber.toString(),
        'print_width': printWidth,
        'pdf_width': printWidth,
        'include_checks': includeChecks,
        'developer-id': PrroConfig.developerId,
      };

      final response = await _client.post(
        Uri.parse('${PrroConfig.environment.baseUrl}/shift/xReport'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200 && response.statusCode != 201) {
        lastXReportDebug = 'HTTP ${response.statusCode}';
        debugPrint('PRRO xReport FAIL: HTTP ${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        lastXReportDebug = 'відповідь не обʼєкт: ${decoded.runtimeType}';
        return null;
      }
      // TEMP-діагностика (прибрати після A4): які поля реально віддає CashDesk.
      lastXReportDebug = 'shift_state=${decoded['shift_state']} '
          '(${decoded['shift_state'].runtimeType}), '
          'shift_duration=${decoded['shift_duration']}, '
          'keys=${decoded.keys.toList()}';
      debugPrint('PRRO xReport RAW: $lastXReportDebug');
      return PrroXReport.fromJson(decoded);
    } catch (e) {
      lastXReportDebug = 'ERROR: $e';
      debugPrint('PRRO xReport ERROR: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Z-звіт (закриття зміни)
  // ---------------------------------------------------------------------------

  /// Відкрити робочу зміну. Endpoint `POST /shift` з `action_type: OPEN_SHIFT`.
  static Future<PrroResult> openShift() async {
    if (!await _ensureAuth()) {
      return const PrroResult.failure(
        error: 'Помилка авторизації ПРРО',
        errorKind: PrroErrorKind.auth,
      );
    }
    try {
      final body = {
        'action_type': 'OPEN_SHIFT',
        'num_fiscal': activeFiscalNumber,
      };
      final response = await _client
          .post(
            Uri.parse('${PrroConfig.environment.baseUrl}/shift'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        return PrroResult(
          success: true,
          checkId: json['uuid']?.toString(),
          textPrint: json['text_print']?.toString(),
        );
      }
      return PrroResult.failure(
        error: json['message']?.toString() ?? 'Помилка відкриття зміни',
        errorKind: PrroErrorKind.logical,
      );
    } on TimeoutException {
      return const PrroResult.failure(
        error: 'Таймаут відкриття зміни',
        errorKind: PrroErrorKind.connection,
      );
    } on SocketException {
      return const PrroResult.failure(
        error: 'Немає з\'єднання з ПРРО',
        errorKind: PrroErrorKind.connection,
      );
    } catch (e) {
      debugPrint('PRRO openShift ERROR: $e');
      return PrroResult.failure(
        error: 'Помилка відкриття зміни: $e',
        errorKind: PrroErrorKind.logical,
      );
    }
  }

  /// Z-звіт — закрити поточну зміну.
  /// Endpoint `POST /shift` з `action_type: Z_REPORT` (док. CashDesk).
  /// УВАГА: `/shift/xReport` — це X-звіт (НЕ закриває зміну), не плутати.
  static Future<PrroResult> zReport({int printWidth = 40}) async {
    if (!await _ensureAuth()) {
      return const PrroResult.failure(
        error: 'Помилка авторизації ПРРО',
        errorKind: PrroErrorKind.auth,
      );
    }

    try {
      final body = {
        'action_type': 'Z_REPORT',
        'num_fiscal': activeFiscalNumber,
        'print_width': printWidth,
        'pdf_width': printWidth,
      };

      final response = await _client.post(
        Uri.parse('${PrroConfig.environment.baseUrl}/shift'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        return PrroResult(
          success: true,
          checkId: json['uuid']?.toString(),
          textPrint: json['text_print']?.toString(),
          pdfBase64: json['pdf']?.toString(),
        );
      } else {
        return PrroResult.failure(
          error: json['message']?.toString() ?? 'Помилка Z-звіту',
          errorKind: PrroErrorKind.logical,
        );
      }
    } on TimeoutException {
      return const PrroResult.failure(
        error: 'Таймаут Z-звіту',
        errorKind: PrroErrorKind.connection,
      );
    } on SocketException {
      return const PrroResult.failure(
        error: 'Немає з\'єднання з ПРРО',
        errorKind: PrroErrorKind.connection,
      );
    } catch (e) {
      debugPrint('PRRO zReport ERROR: $e');
      return PrroResult.failure(
        error: 'Помилка Z-звіту: $e',
        errorKind: PrroErrorKind.logical,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Отримання чеку
  // ---------------------------------------------------------------------------

  /// Отримати текстове представлення чеку.
  static Future<String?> getReceiptText(String checkId) async {
    try {
      final url = '${PrroConfig.environment.baseUrl}'
          '/checks/$checkId/text?print_width=48';
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
      final url = '${PrroConfig.environment.baseUrl}'
          '/checks/$checkId/qr?ascii=1';
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

  // ---------------------------------------------------------------------------
  // Cabinet URL (read-only перегляд каси)
  // ---------------------------------------------------------------------------

  /// URL для відкриття поточної зміни в браузері без повторної авторизації.
  /// Email/password передаються у URL-safe base64.
  static String cabinetUrl({int? fiscalNumber}) {
    String b64(String s) => base64Url.encode(utf8.encode(s));
    return '${PrroConfig.cabinetHost}/authenticate'
        '?num_fiscal=${fiscalNumber ?? activeFiscalNumber}'
        '&email=${b64(PrroConfig.email)}'
        '&password=${b64(PrroConfig.password)}';
  }

  // ---------------------------------------------------------------------------
  // Mock success (для перевірки UI коли реальний ПРРО заблокований)
  // ---------------------------------------------------------------------------

  static PrroResult _mockSaleSuccess({
    required List<PrroProduct> products,
    required List<PrroPayment> payments,
    required double totalSum,
    int? localNumber,
    bool isReturn = false,
  }) {
    final now = DateTime.now();
    final orderNum = 'MOCK-${now.millisecondsSinceEpoch.toRadixString(36)}';
    final uuid = '${now.microsecondsSinceEpoch.toRadixString(16)}-mock';
    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final yyyy = now.year.toString();
    final hh = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');

    final lines = <String>[
      _center('ТЕСТОВИЙ ЧЕК (MOCK)'),
      _center('Аптека «Арніка»'),
      _center('м. Київ, вул. Тестова 1'),
      '',
      'ФН ПРРО:    ${PrroService.activeFiscalNumber}',
      'ID:         $uuid',
      'Дата/час:   $dd.$mm.$yyyy $hh:$mi:$ss',
      if (localNumber != null) 'Лок. номер: $localNumber',
      _hr(),
      isReturn ? _center('ПОВЕРНЕННЯ') : _center('ПРОДАЖ'),
      _hr(),
      ...products.expand(_formatProductLines),
      _hr(),
      _kv('РАЗОМ', _money(totalSum)),
      ...payments.map((p) => _kv(p.name, _money(p.sum))),
      _hr(),
      _center('Дякуємо за покупку!'),
      _center('Це не фіскальний документ'),
    ];
    final text = lines.join('\n');
    final textBase64 = base64Encode(utf8.encode(text));

    debugPrint('PRRO MOCK sale: orderNum=$orderNum total=$totalSum '
        '${isReturn ? "(return)" : "(sale)"}');

    return PrroResult(
      success: true,
      checkId: uuid,
      orderNum: orderNum,
      orderDate: '$dd.$mm.$yyyy',
      orderTime: '$hh:$mi:$ss',
      qrBase64: _mockQrPng,
      qrData: 'https://cabinet.tax.gov.ua/cashregs/check?id=$uuid',
      textPrint: textBase64,
      link: 'https://cabinet.tax.gov.ua/cashregs/check?id=$uuid',
      isOffline: false,
    );
  }

  static String _hr([int width = 40]) => '-' * width;

  static String _center(String s, [int width = 40]) {
    if (s.length >= width) return s;
    final pad = (width - s.length) ~/ 2;
    return ' ' * pad + s;
  }

  static String _kv(String k, String v, [int width = 40]) {
    final spaces = width - k.length - v.length;
    return spaces > 0 ? '$k${' ' * spaces}$v' : '$k $v';
  }

  static String _money(double v) =>
      v.asMoney;

  static List<String> _formatProductLines(PrroProduct p) {
    final qty = p.amount == p.amount.floorToDouble()
        ? p.amount.toInt().toString()
        : p.amount.toStringAsFixed(3);
    return [
      p.name.length > 40 ? p.name.substring(0, 40) : p.name,
      _kv('  $qty x ${_money(p.price)}', _money(p.cost)),
    ];
  }

  /// Мінімальний валідний 1×1 PNG (білий піксель) — placeholder для QR у mock-режимі.
  static const _mockQrPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=';
}
