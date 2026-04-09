import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Skarb Cloud — e-Prescription API client
// Docs: https://docs.skarb.ua
// Postman: https://documenter.getpostman.com/view/26732688/2s93kxbRCu
// ─────────────────────────────────────────────────────────────────────────────

/// Конфігурація Skarb Cloud API.
class SkarbConfig {
  /// Прод сервер.
  static const baseUrl = 'https://skarb.phrm.pro/api/v2';

  /// Тест сервер.
  static const testBaseUrl = 'https://test-skarb.phrm.pro/api/v2';

  /// API-Key (отримати від Skarb Cloud).
  static const apiKey = ''; // TODO: отримати API-Key

  /// Credentials для авторизації фармацевта (тестове середовище).
  static const email = 'smartsign+2@openpharma.global';
  static const password = '123';

  /// Таймаут запитів.
  static const timeout = Duration(seconds: 15);

  /// Використовувати тест сервер.
  static const bool useTestServer = true;

  static String get effectiveBaseUrl =>
      useTestServer ? testBaseUrl : baseUrl;

  // ── Token state ──────────────────────────────────────────────────────────

  static String? _token;
  static DateTime? _tokenTime;

  static bool get isAuthenticated => _token != null;
  static DateTime? get tokenTime => _tokenTime;
  static String? get token => _token;

  static void setToken(String token) {
    _token = token;
    _tokenTime = DateTime.now();
  }

  static void clearToken() {
    _token = null;
    _tokenTime = null;
  }
}

// ── Result types ───────────────────────────────────────────────────────────

class SkarbResult<T> {
  final bool success;
  final T? data;
  final String? error;

  const SkarbResult({required this.success, this.data, this.error});

  factory SkarbResult.ok(T data) => SkarbResult(success: true, data: data);
  factory SkarbResult.fail(String error) =>
      SkarbResult(success: false, error: error);
}

/// Дані рецепта від Skarb API (get-data response).
class SkarbPrescriptionData {
  final bool skipSign;
  final String medicationRequestId;
  final String requestNumber;
  final String status;
  final String medicalProgramId;
  final String medicalProgramName;
  final String? fundingSource;
  final String patientName;
  final int? patientAge;
  final String? doctorName;
  final String? clinicName;
  final String medicationName;
  final int medicationQty;
  final int? medicationRemainingQty;
  final String? dosageInstruction;
  final DateTime? dispenseValidFrom;
  final DateTime? dispenseValidTo;
  final List<SkarbParticipant> participants;

  const SkarbPrescriptionData({
    required this.skipSign,
    required this.medicationRequestId,
    required this.requestNumber,
    required this.status,
    required this.medicalProgramId,
    required this.medicalProgramName,
    this.fundingSource,
    required this.patientName,
    this.patientAge,
    this.doctorName,
    this.clinicName,
    required this.medicationName,
    required this.medicationQty,
    this.medicationRemainingQty,
    this.dosageInstruction,
    this.dispenseValidFrom,
    this.dispenseValidTo,
    required this.participants,
  });

  factory SkarbPrescriptionData.fromJson(Map<String, dynamic> json) {
    final mr = json['medicationRequest'] as Map<String, dynamic>? ?? {};
    final medInfo = mr['medication_info'] as Map<String, dynamic>? ?? {};
    final person = mr['person'] as Map<String, dynamic>? ?? {};
    final employee = mr['employee'] as Map<String, dynamic>? ?? {};
    final party = employee['party'] as Map<String, dynamic>? ?? {};
    final program = mr['medical_program'] as Map<String, dynamic>? ?? {};
    final division = mr['division'] as Map<String, dynamic>? ?? {};
    final dosageList = mr['dosage_instruction'] as List<dynamic>? ?? [];

    // Parse dosage instruction text
    String? dosageText;
    if (dosageList.isNotEmpty) {
      dosageText = (dosageList.first as Map<String, dynamic>)['text']?.toString();
    }

    // Parse participants
    final participantsJson = json['participants'] as List<dynamic>? ?? [];
    final participants = participantsJson
        .map((p) => SkarbParticipant.fromJson(p as Map<String, dynamic>))
        .toList();

    return SkarbPrescriptionData(
      skipSign: json['skip_sign'] == true,
      medicationRequestId: mr['id']?.toString() ?? '',
      requestNumber: mr['request_number']?.toString() ?? '',
      status: mr['status']?.toString() ?? '',
      medicalProgramId: program['id']?.toString() ?? '',
      medicalProgramName: program['name']?.toString() ?? '',
      fundingSource: program['funding_source']?.toString(),
      patientName: person['short_name']?.toString() ?? '',
      patientAge: person['age'] as int?,
      doctorName: _formatDoctorName(party),
      clinicName: division['name']?.toString(),
      medicationName: medInfo['medication_name']?.toString() ?? '',
      medicationQty: medInfo['medication_qty'] as int? ?? 0,
      medicationRemainingQty: medInfo['medication_remaining_qty'] as int?,
      dosageInstruction: dosageText,
      dispenseValidFrom: _parseDate(mr['dispense_valid_from']?.toString()),
      dispenseValidTo: _parseDate(mr['dispense_valid_to']?.toString()),
      participants: participants,
    );
  }

  static String? _formatDoctorName(Map<String, dynamic> party) {
    final last = party['last_name']?.toString();
    final first = party['first_name']?.toString();
    final second = party['second_name']?.toString();
    if (last == null) return null;
    return [last, first, second].whereType<String>().join(' ');
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

/// Учасник програми реімбурсації (participant з get-data).
class SkarbParticipant {
  final String participantId;
  final String medicationId;
  final String medicationName;
  final String form;
  final String? manufacturerName;
  final String? manufacturerCountry;
  final double consumerPrice;
  final double wholesalePrice;
  final double reimbursementAmount;
  final double estimatedPaymentAmount;
  final int packageQty;
  final int packageMinQty;
  final double? reimbursementDailyDosage;
  final String? registryNumber;

  const SkarbParticipant({
    required this.participantId,
    required this.medicationId,
    required this.medicationName,
    required this.form,
    this.manufacturerName,
    this.manufacturerCountry,
    required this.consumerPrice,
    required this.wholesalePrice,
    required this.reimbursementAmount,
    required this.estimatedPaymentAmount,
    required this.packageQty,
    required this.packageMinQty,
    this.reimbursementDailyDosage,
    this.registryNumber,
  });

  factory SkarbParticipant.fromJson(Map<String, dynamic> json) {
    final manufacturer = json['manufacturer'] as Map<String, dynamic>? ?? {};
    return SkarbParticipant(
      participantId: json['id']?.toString() ?? '',
      medicationId: json['medication_id']?.toString() ?? '',
      medicationName: json['medication_name']?.toString() ?? '',
      form: json['form']?.toString() ?? '',
      manufacturerName: manufacturer['name']?.toString().trim(),
      manufacturerCountry: manufacturer['country']?.toString().trim(),
      consumerPrice: _toDouble(json['consumer_price']),
      wholesalePrice: _toDouble(json['wholesale_price']),
      reimbursementAmount: _toDouble(json['reimbursement_amount']),
      estimatedPaymentAmount: _toDouble(json['estimated_payment_amount']),
      packageQty: json['package_qty'] as int? ?? 0,
      packageMinQty: json['package_min_qty'] as int? ?? 0,
      reimbursementDailyDosage: json['reimbursement_daily_dosage'] as double?,
      registryNumber: json['registry_number']?.toString(),
    );
  }

  static double _toDouble(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Skarb Service
// ═══════════════════════════════════════════════════════════════════════════════

class SkarbService {
  static final _client = http.Client();

  // ── Auth ──────────────────────────────────────────────────────────────────

  /// Авторизація фармацевта. Викликати раз на зміну.
  static Future<SkarbResult<String>> login() async {
    if (ApiConfig.useMock) {
      SkarbConfig.setToken('mock_token');
      return SkarbResult.ok('mock_token');
    }
    if (SkarbConfig.apiKey.isEmpty) {
      return SkarbResult.fail('Skarb API-Key не налаштовано');
    }

    try {
      final uri = Uri.parse('${SkarbConfig.effectiveBaseUrl}/account/login');
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'API-Key': SkarbConfig.apiKey,
            },
            body: jsonEncode({
              'email': SkarbConfig.email,
              'password': SkarbConfig.password,
            }),
          )
          .timeout(SkarbConfig.timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>? ?? {};
        final token = data['token']?.toString() ?? '';
        if (token.isEmpty) return SkarbResult.fail('Порожній токен');
        SkarbConfig.setToken(token);
        debugPrint('Skarb: login OK');
        return SkarbResult.ok(token);
      }
      return SkarbResult.fail('Skarb login: HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('Skarb login error: $e');
      return SkarbResult.fail('Помилка з\'єднання зі Skarb: $e');
    }
  }

  // ── Prescription Data ────────────────────────────────────────────────────

  /// Отримати дані е-рецепта по номеру.
  static Future<SkarbResult<SkarbPrescriptionData>> getPrescriptionData(
      String prescriptionId) async {
    if (ApiConfig.useMock) {
      return SkarbResult.fail('Mock mode — використовуйте локальні дані');
    }

    final result = await _post('/medication/get-data', {
      'id': prescriptionId,
    });
    if (!result.success) return SkarbResult.fail(result.error!);

    try {
      final data = SkarbPrescriptionData.fromJson(result.data!);
      return SkarbResult.ok(data);
    } catch (e) {
      debugPrint('Skarb parse error: $e');
      return SkarbResult.fail('Помилка обробки даних рецепта: $e');
    }
  }

  // ── Payment ──────────────────────────────────────────────────────────────

  /// Розрахувати суму доплати пацієнта.
  static Future<SkarbResult<double>> getPaymentAmount({
    required String medicalProgramId,
    required String medicationRequestId,
    required List<String> medicationIds,
    required List<String> participantIds,
    required List<double> prices,
    required List<int> quantities,
  }) async {
    if (ApiConfig.useMock) return SkarbResult.ok(0);

    final result = await _post('/medication/get-payment-amount', {
      'medicalProgramId': medicalProgramId,
      'medicationRequestId': medicationRequestId,
      'medicationId': medicationIds,
      'participantId': participantIds,
      'price': prices,
      'quantity': quantities,
    });
    if (!result.success) return SkarbResult.fail(result.error!);

    final amount = result.data!['paymentAmount'];
    return SkarbResult.ok((amount is num) ? amount.toDouble() : 0);
  }

  // ── Dispensing ───────────────────────────────────────────────────────────

  /// Погашення через SmartSign (автопідпис).
  static Future<SkarbResult<String>> processDispenseViaSmartSign({
    required String code,
    required String medicalProgramId,
    required String medicationRequestId,
    required List<String> medicationIds,
    required List<String> participantIds,
    required List<double> prices,
    required List<int> quantities,
    required double paymentAmount,
    required String paymentId,
  }) async {
    if (ApiConfig.useMock) return SkarbResult.ok('mock_dispense_id');

    final result =
        await _post('/medication/process-dispense-via-smart-sign', {
      'code': code,
      'medicalProgramId': medicalProgramId,
      'medicationRequestId': medicationRequestId,
      'medicationId': medicationIds,
      'participantId': participantIds,
      'price': prices,
      'quantity': quantities,
      'paymentAmount': paymentAmount,
      'paymentId': paymentId,
    });
    if (!result.success) return SkarbResult.fail(result.error!);

    final id = result.data!['medicationDispenseId']?.toString() ?? '';
    return SkarbResult.ok(id);
  }

  /// Ініціювати погашення з redirect на сторінку підпису (fallback).
  static Future<SkarbResult<({String url, String initId})>> initDispenseForm({
    required String code,
    required String medicalProgramId,
    required String medicationRequestId,
    required List<String> medicationIds,
    required List<String> participantIds,
    required List<double> prices,
    required List<int> quantities,
    required double paymentAmount,
    required String paymentId,
  }) async {
    if (ApiConfig.useMock) {
      return SkarbResult.ok((url: 'https://mock.url', initId: 'mock_init'));
    }

    final result = await _post('/medication/init-dispense-form', {
      'code': code,
      'medicalProgramId': medicalProgramId,
      'medicationRequestId': medicationRequestId,
      'medicationId': medicationIds,
      'participantId': participantIds,
      'price': prices,
      'quantity': quantities,
      'paymentAmount': paymentAmount,
      'paymentId': paymentId,
    });
    if (!result.success) return SkarbResult.fail(result.error!);

    final url = result.data!['url']?.toString() ?? '';
    final initId =
        result.data!['initMedicationDispenseId']?.toString() ?? '';
    return SkarbResult.ok((url: url, initId: initId));
  }

  /// Скасувати погашення.
  static Future<SkarbResult<bool>> rejectDispense(String id) async {
    if (ApiConfig.useMock) return SkarbResult.ok(true);

    final result = await _post('/medication/reject-dispense', {'id': id});
    return result.success
        ? SkarbResult.ok(true)
        : SkarbResult.fail(result.error!);
  }

  /// Перевірити статус погашення.
  static Future<SkarbResult<Map<String, dynamic>>> getDispenseData(
      String id) async {
    if (ApiConfig.useMock) return SkarbResult.ok({});

    return _post('/medication/get-dispense-data', {'id': id});
  }

  /// Отримати список завершених погашень за період.
  static Future<SkarbResult<List<Map<String, dynamic>>>> getCompletedDispenses({
    required String startDate,
    required String finishDate,
    String? divisionId,
  }) async {
    if (ApiConfig.useMock) return SkarbResult.ok([]);

    final result = await _post('/medication/get-completed-dispenses', {
      'startDate': startDate,
      'finishDate': finishDate,
      'divisionId': divisionId,
    });
    if (!result.success) return SkarbResult.fail(result.error!);

    final list = result.data! as List<dynamic>? ?? [];
    return SkarbResult.ok(
        list.map((e) => e as Map<String, dynamic>).toList());
  }

  // ── Rejection ────────────────────────────────────────────────────────────

  /// Отримати довідник причин відхилення (кешувати на клієнті).
  static Future<SkarbResult<Map<String, String>>> getRejectReasons() async {
    if (ApiConfig.useMock) {
      return SkarbResult.ok({
        'NO_REQUEST_NEEDED': 'Відсутність достатньої кількості ліків',
        'NO_SMS': 'Пацієнту не надходить СМС',
        'PATIENT_REJECT': 'Відмова пацієнта',
        'WRONG_DOSAGE': 'Невірна кількість доз',
        'WRONG_PERIOD': 'Невірна кількість днів курсу',
        'WRONG_QTY': 'Невірна лікарська форма',
        'WRONG_SIGNATURE': 'Невірна сигнатура',
        'OTHER': 'Інше',
      });
    }

    final uri =
        Uri.parse('${SkarbConfig.effectiveBaseUrl}/medication/get-reject-reasons');
    try {
      final response = await _client.get(uri, headers: _headers()).timeout(
            SkarbConfig.timeout,
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>? ?? {};
        return SkarbResult.ok(
            data.map((k, v) => MapEntry(k, v.toString())));
      }
      return SkarbResult.fail('HTTP ${response.statusCode}');
    } catch (e) {
      return SkarbResult.fail('Помилка: $e');
    }
  }

  /// Автоматичне відхилення рецепта.
  static Future<SkarbResult<bool>> createAndSendReject({
    required String id,
    required String reasonCode,
    String? reasonText,
  }) async {
    if (ApiConfig.useMock) return SkarbResult.ok(true);

    final body = <String, dynamic>{
      'id': id,
      'reasonCode': reasonCode,
    };
    if (reasonText != null) body['reasonText'] = reasonText;
    final result = await _post('/medication/create-and-send-reject', body);
    return result.success
        ? SkarbResult.ok(true)
        : SkarbResult.fail(result.error!);
  }

  // ── Private HTTP helpers ─────────────────────────────────────────────────

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'API-Key': SkarbConfig.apiKey,
        if (SkarbConfig.token != null)
          'Authorization': 'Bearer ${SkarbConfig.token}',
      };

  /// POST запит з auto-relogin on 401.
  static Future<SkarbResult<Map<String, dynamic>>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    if (!SkarbConfig.isAuthenticated) {
      final loginResult = await login();
      if (!loginResult.success) return SkarbResult.fail(loginResult.error!);
    }

    try {
      final uri = Uri.parse('${SkarbConfig.effectiveBaseUrl}$endpoint');
      var response = await _client
          .post(uri, headers: _headers(), body: jsonEncode(body))
          .timeout(SkarbConfig.timeout);

      // Auto-relogin on 401
      if (response.statusCode == 401) {
        debugPrint('Skarb: 401 → re-login');
        final loginResult = await login();
        if (!loginResult.success) {
          return SkarbResult.fail('Не вдалося переавторизуватися');
        }
        response = await _client
            .post(uri, headers: _headers(), body: jsonEncode(body))
            .timeout(SkarbConfig.timeout);
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final data = json['data'];
        if (data is Map<String, dynamic>) {
          return SkarbResult.ok(data);
        }
        // get-completed-dispenses returns a list in data
        return SkarbResult.ok({'data': data});
      }

      // Error response (422 etc.)
      final errors = json['errors'];
      final errorMsg = errors is Map
          ? errors.values.first?.toString() ?? 'Помилка'
          : 'Помилка Skarb: HTTP ${response.statusCode}';
      return SkarbResult.fail(errorMsg);
    } catch (e) {
      debugPrint('Skarb $endpoint error: $e');
      return SkarbResult.fail('Помилка з\'єднання: $e');
    }
  }
}
