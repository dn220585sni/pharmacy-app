import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// CIET 1303 — МІС Каштан e-prescription API
// Docs: https://documenter.getpostman.com/view/12682091/2s9YsKgsE7
// Preprod: https://preprod.ciet-holding.com/
// ─────────────────────────────────────────────────────────────────────────────

/// Конфігурація CIET 1303 API.
class CietConfig {
  static const baseUrl = 'https://mis-kashtan.dp.ua/api/pharmacy/api';
  static const pharmacyId = '4202';
  static const authKey =
      '0cb7df6a15a93b0cfe682cb92c127b21f8c7fd7933a4bef2b47e54cd0656fe68';
  static const timeout = Duration(seconds: 15);
}

// ── Models ────────────────────────────────────────────────────────────────────

/// Позиція реімбурсації в рецепті 1303.
class CietReimbursement {
  final String innNameLat;
  final String? dozeText;
  final int? qpackInt;         // к-ть в упаковці
  final double? retailPrice;   // роздрібна ціна упаковки
  final double? reimbursePrice; // сума відшкодування за упаковку
  final double? overpay;       // доплата пацієнта
  final int? idMorion;         // Моріон ID
  final String? ehealthUid;    // eHealth UID
  final int? idForm;

  const CietReimbursement({
    required this.innNameLat,
    this.dozeText,
    this.qpackInt,
    this.retailPrice,
    this.reimbursePrice,
    this.overpay,
    this.idMorion,
    this.ehealthUid,
    this.idForm,
  });

  factory CietReimbursement.fromJson(Map<String, dynamic> json) {
    return CietReimbursement(
      innNameLat: json['inn_name_lat']?.toString() ?? '',
      dozeText: json['doze_text']?.toString(),
      qpackInt: _toInt(json['qpack_int']),
      retailPrice: _toDouble(json['c_retail_pack']),
      reimbursePrice: _toDouble(json['s_reimburse_pack']),
      overpay: _toDouble(json['s_overpay']),
      idMorion: _toInt(json['id_morion']),
      ehealthUid: json['ehealth_uid']?.toString(),
      idForm: _toInt(json['id_form']),
    );
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

/// Рецепт 1303 (МІС Каштан).
class CietRecipe {
  final String recipeNumber;
  final int recipeId;
  final int positionId;
  final String position;          // назва: "PARACETAMOL таблетки по 200 мг"
  final String nameInnUa;         // МНН укр: "ПАРАЦЕТАМОЛ"
  final String nameInnLat;        // МНН лат: "PARACETAMOL"
  final String? nameRegUa;        // торгова назва: "ПАРАЦЕТАМОЛ"
  final String? comment;          // дозування: "по 1 доз(і) 2 р/д 25 дн."
  final int? drugsNeedBought;     // кількість доз
  final String? doctorRecommendedManufacturer;
  final DateTime? recipeCreated;
  final DateTime? recipeValidFrom;
  final DateTime? recipeValidTo;
  final int recipeType;           // 1=е-рецепт, 2=пільговий, 3=звичайний
  final int patientId;
  final String patientName;
  final String? patientAge;
  final int? institutionId;
  final String? institutionName;
  final String? institutionEdrpou;
  final int? doctorId;
  final String? doctorName;
  final String? doctorSpeciality;
  final int? category1303Id;
  final String? category1303Name;
  final int? category1303DiscountPercent;
  final List<CietReimbursement> reimbursement;

  const CietRecipe({
    required this.recipeNumber,
    required this.recipeId,
    required this.positionId,
    required this.position,
    required this.nameInnUa,
    required this.nameInnLat,
    this.nameRegUa,
    this.comment,
    this.drugsNeedBought,
    this.doctorRecommendedManufacturer,
    this.recipeCreated,
    this.recipeValidFrom,
    this.recipeValidTo,
    required this.recipeType,
    required this.patientId,
    required this.patientName,
    this.patientAge,
    this.institutionId,
    this.institutionName,
    this.institutionEdrpou,
    this.doctorId,
    this.doctorName,
    this.doctorSpeciality,
    this.category1303Id,
    this.category1303Name,
    this.category1303DiscountPercent,
    this.reimbursement = const [],
  });

  factory CietRecipe.fromJson(Map<String, dynamic> json) {
    final reimbList = (json['reimbursement'] as List<dynamic>?)
            ?.map((e) => CietReimbursement.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return CietRecipe(
      recipeNumber: json['recipe_number']?.toString() ?? '',
      recipeId: json['recipe_id'] as int? ?? 0,
      positionId: json['position_id'] as int? ?? 0,
      position: json['position']?.toString() ?? '',
      nameInnUa: json['name_inn_ua']?.toString() ?? '',
      nameInnLat: json['name_inn_lat']?.toString() ?? '',
      nameRegUa: _nonEmpty(json['name_reg_ua']),
      comment: _nonEmpty(json['comment']),
      drugsNeedBought: int.tryParse(json['drugs_need_bought']?.toString() ?? ''),
      doctorRecommendedManufacturer: _nonEmpty(json['doctor_recommended_manufacturer']),
      recipeCreated: _parseDate(json['recipe_created']),
      recipeValidFrom: _parseDate(json['recipe_valid_from']),
      recipeValidTo: _parseDate(json['recipe_valid_to']),
      recipeType: json['recipe_type'] as int? ?? 0,
      patientId: json['patient_id'] as int? ?? 0,
      patientName: json['patient_name']?.toString() ?? '',
      patientAge: json['patient_age']?.toString(),
      institutionId: json['institution_id'] as int?,
      institutionName: _nonEmpty(json['institution_name']),
      institutionEdrpou: _nonEmpty(json['institution_edrpou']),
      doctorId: json['doctor_id'] as int?,
      doctorName: _nonEmpty(json['doctor_name']),
      doctorSpeciality: _nonEmpty(json['doctor_speciality']),
      category1303Id: json['category_1303_id'] as int?,
      category1303Name: _nonEmpty(json['category_1303_name']),
      category1303DiscountPercent: json['category_1303_discount_percent'] as int?,
      reimbursement: reimbList,
    );
  }

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString().trim();
    return (s != null && s.isNotEmpty) ? s : null;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  /// Тип рецепту — мітка.
  String get recipeTypeLabel {
    switch (recipeType) {
      case 1:
        return 'Е-рецепт';
      case 2:
        return 'Пільговий';
      case 3:
        return 'Звичайний';
      default:
        return 'Тип $recipeType';
    }
  }

  /// Чи є реімбурсація.
  bool get hasReimbursement => reimbursement.isNotEmpty;

  /// Чи є знижка 1303.
  bool get has1303Discount =>
      category1303DiscountPercent != null && category1303DiscountPercent! > 0;

  /// Чи рецепт ще дійсний.
  bool get isValid {
    if (recipeValidTo == null) return true; // безстроковий
    return DateTime.now().isBefore(recipeValidTo!.add(const Duration(days: 1)));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════════════════════

class CietService {
  static final _client = http.Client();

  /// Отримати рецепти з МІС Каштан (1303).
  ///
  /// [recipeNumber] — опціональний номер рецепту для пошуку конкретного.
  /// Без нього — повертає всі рецепти для аптеки.
  static Future<CietResult<List<CietRecipe>>> getRecipes({
    String? recipeNumber,
  }) async {
    try {
      final params = <String, String>{
        'pharmacy_id': CietConfig.pharmacyId,
      };
      if (recipeNumber != null && recipeNumber.isNotEmpty) {
        params['recipe_number'] = recipeNumber;
      }

      final uri = Uri.parse('${CietConfig.baseUrl}/get-recipes')
          .replace(queryParameters: params);

      final response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${CietConfig.authKey}',
      }).timeout(CietConfig.timeout);

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (json['status'] == 'success') {
        final dataList = json['data'] as List<dynamic>? ?? [];
        final recipes = dataList
            .map((e) => CietRecipe.fromJson(e as Map<String, dynamic>))
            .toList();
        debugPrint('CIET 1303: loaded ${recipes.length} recipes');
        return CietResult.ok(recipes);
      }

      final message = json['message']?.toString() ?? 'Невідома помилка';
      debugPrint('CIET 1303: $message');
      return CietResult.fail(message);
    } catch (e) {
      debugPrint('CIET 1303 error: $e');
      return CietResult.fail('Помилка з\'єднання: $e');
    }
  }

  /// Створити замовлення (погашення рецепту) в МІС Каштан.
  ///
  /// [positionId] — ID позиції рецепту
  /// [morionId] — Моріон ID обраного препарату
  /// [tradename] — торгова назва
  /// [releaseForm] — форма випуску ("таблетки", "сироп", тощо)
  /// [dosage] — дозування ("200", "500")
  /// [unit] — одиниця ("мг", "мкг", "мл")
  /// [pharmacyOrderId] — внутрішній ID чека/замовлення
  /// [pharmacistName] — ПІБ фармацевта
  /// [pharmacistId] — ІПН фармацевта
  /// [drugs] — список відпущених препаратів (серія, ціна, к-ть)
  static Future<CietResult<Map<String, dynamic>>> createOrder({
    required int positionId,
    required int morionId,
    required String tradename,
    required String releaseForm,
    required String dosage,
    required String unit,
    required String pharmacyOrderId,
    required String pharmacistName,
    String? pharmacistId,
    required List<CietOrderDrug> drugs,
  }) async {
    try {
      final uri = Uri.parse('${CietConfig.baseUrl}/orders-create');
      final now = DateTime.now();
      final orderDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      final request = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${CietConfig.authKey}'
        ..fields['position_id'] = positionId.toString()
        ..fields['morion_id'] = morionId.toString()
        ..fields['tradename'] = tradename
        ..fields['release_form'] = releaseForm
        ..fields['dosage'] = dosage
        ..fields['unit'] = unit
        ..fields['pharmacy_order_id'] = pharmacyOrderId
        ..fields['pharmacy_id'] = CietConfig.pharmacyId
        ..fields['pharmacy_name'] = 'Аптека АНЦ'
        ..fields['pharmacist_id'] = pharmacistId ?? ''
        ..fields['pharmacist'] = pharmacistName
        ..fields['order_date'] = orderDate
        ..fields['drugs'] = jsonEncode(
            drugs.map((d) => d.toJson()).toList());

      final streamed = await _client.send(request).timeout(CietConfig.timeout);
      final response = await http.Response.fromStream(streamed);

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (json['status'] == 'success') {
        debugPrint('CIET 1303: order created for position $positionId');
        return CietResult.ok(json);
      }

      final message = json['message']?.toString() ?? 'Невідома помилка';
      debugPrint('CIET 1303 order error: $message');
      return CietResult.fail(message);
    } catch (e) {
      debugPrint('CIET 1303 order error: $e');
      return CietResult.fail('Помилка з\'єднання: $e');
    }
  }

  /// Отримати довідник категорій 1303 (пільгові групи).
  static Future<CietResult<List<Map<String, dynamic>>>> getGroups1303() async {
    try {
      final uri = Uri.parse('${CietConfig.baseUrl}/group1303');
      final response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${CietConfig.authKey}',
      }).timeout(CietConfig.timeout);

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (json['status'] == 'success') {
        final data = json['data'] as List<dynamic>? ?? [];
        return CietResult.ok(
            data.map((e) => e as Map<String, dynamic>).toList());
      }

      return CietResult.fail(json['message']?.toString() ?? 'Помилка');
    } catch (e) {
      debugPrint('CIET 1303 group1303 error: $e');
      return CietResult.fail('Помилка: $e');
    }
  }

  /// Авторизація через CIET (отримати URL для логіну).
  ///
  /// [callbackUrl] — URL для callback після авторизації
  static Future<CietResult<Map<String, dynamic>>> authorizeLogin({
    required String callbackUrl,
  }) async {
    try {
      final uri = Uri.parse(
          'https://api.preprod.ciet-holding.com/api/v1/authorize/login');

      final request = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${CietConfig.authKey}'
        ..fields['callback_url'] = callbackUrl;

      final streamed = await _client.send(request).timeout(CietConfig.timeout);
      final response = await http.Response.fromStream(streamed);

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (json['status'] == 'success' || json['data'] != null || json['url'] != null) {
        return CietResult.ok(json);
      }

      return CietResult.fail(json['message']?.toString() ?? 'Помилка');
    } catch (e) {
      debugPrint('CIET v1 authorize error: $e');
      return CietResult.fail('Помилка: $e');
    }
  }

  /// Підписати та завершити погашення рецепту (CIET v1).
  ///
  /// [dispenseId] — UUID погашення (з відповіді dispense-recipe: id)
  /// [employeeEmail] — email фармацевта для підпису
  /// [signedData] — підписані дані (base64 CMS/CAdES)
  static Future<CietResult<Map<String, dynamic>>> signDispenseV1({
    required String dispenseId,
    required String employeeEmail,
    required String signedData,
  }) async {
    try {
      final uri = Uri.parse(
          'https://api.preprod.ciet-holding.com/api/v1/medications/signed-medication-dispense/$dispenseId');

      final data = jsonEncode({
        'signed_medication_dispense': signedData,
      });

      final request = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${CietConfig.authKey}'
        ..fields['employee_email'] = employeeEmail
        ..fields['data'] = data;

      final streamed = await _client.send(request).timeout(CietConfig.timeout);
      final response = await http.Response.fromStream(streamed);

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (json['status'] == 'success' || json['data'] != null) {
        debugPrint('CIET v1: sign dispense OK');
        return CietResult.ok(json);
      }

      return CietResult.fail(json['message']?.toString() ?? 'Помилка');
    } catch (e) {
      debugPrint('CIET v1 sign dispense error: $e');
      return CietResult.fail('Помилка: $e');
    }
  }

  /// Погасити рецепт (dispense) через CIET v1 API.
  ///
  /// [pharmacyId] — ID аптеки в системі CIET
  /// [employeeId] — UUID співробітника
  /// [medicationRequestId] — UUID рецепту
  /// [medicalProgramId] — UUID медичної програми
  /// [dispenseDetails] — деталі відпуску (medication_id, qty, ціни)
  static Future<CietResult<Map<String, dynamic>>> dispenseRecipeV1({
    required String pharmacyId,
    required String employeeId,
    required String medicationRequestId,
    required String medicalProgramId,
    required List<Map<String, dynamic>> dispenseDetails,
  }) async {
    try {
      final uri = Uri.parse(
          'https://api.preprod.ciet-holding.com/api/v1/medications/dispense-recipe/$pharmacyId');

      final data = jsonEncode({
        'medication_dispense': {
          'medication_request_id': medicationRequestId,
          'medical_program_id': medicalProgramId,
          'dispense_details': dispenseDetails,
        },
      });

      final request = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${CietConfig.authKey}'
        ..fields['employee_id'] = employeeId
        ..fields['data'] = data;

      final streamed = await _client.send(request).timeout(CietConfig.timeout);
      final response = await http.Response.fromStream(streamed);

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (json['status'] == 'success' || json['data'] != null) {
        debugPrint('CIET v1: dispense OK');
        return CietResult.ok(json);
      }

      return CietResult.fail(json['message']?.toString() ?? 'Помилка');
    } catch (e) {
      debugPrint('CIET v1 dispense error: $e');
      return CietResult.fail('Помилка: $e');
    }
  }

  /// Отримати список препаратів для погашення рецепту (CIET v1).
  ///
  /// [medicationRequestId] — UUID рецепту (з get-recipe відповіді: id)
  /// [medicalProgramId] — UUID медичної програми (з get-recipe: medical_program.id)
  /// [medicationQty] — к-ть (з get-recipe: medication_info.medication_qty)
  /// [employeeId] — UUID співробітника
  static Future<CietResult<Map<String, dynamic>>> getDrugListV1({
    required String medicationRequestId,
    required String medicalProgramId,
    required int medicationQty,
    required String employeeId,
  }) async {
    try {
      final uri = Uri.parse(
          'https://api.preprod.ciet-holding.com/api/v1/medications/get-drug-list/'
          '$medicationRequestId/$medicalProgramId/$medicationQty');

      final request = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${CietConfig.authKey}'
        ..fields['employee_id'] = employeeId;

      final streamed = await _client.send(request).timeout(CietConfig.timeout);
      final response = await http.Response.fromStream(streamed);

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (json['status'] == 'success' || json['data'] != null) {
        return CietResult.ok(json);
      }

      return CietResult.fail(json['message']?.toString() ?? 'Помилка');
    } catch (e) {
      debugPrint('CIET v1 get-drug-list error: $e');
      return CietResult.fail('Помилка: $e');
    }
  }

  /// Отримати рецепт з preprod API (CIET v1).
  ///
  /// [recipeNumber] — номер рецепту (напр. "0000-85T8-K878-HP71")
  /// [employeeId] — UUID співробітника
  static Future<CietResult<Map<String, dynamic>>> getRecipeV1({
    required String recipeNumber,
    required String employeeId,
  }) async {
    try {
      final uri = Uri.parse(
          'https://api.preprod.ciet-holding.com/api/v1/medications/get-recipe/$recipeNumber');

      final request = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${CietConfig.authKey}'
        ..fields['employee_id'] = employeeId;

      final streamed = await _client.send(request).timeout(CietConfig.timeout);
      final response = await http.Response.fromStream(streamed);

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (json['status'] == 'success' || json['data'] != null) {
        return CietResult.ok(json);
      }

      return CietResult.fail(json['message']?.toString() ?? 'Помилка');
    } catch (e) {
      debugPrint('CIET v1 get-recipe error: $e');
      return CietResult.fail('Помилка: $e');
    }
  }

  /// Отримати довідник медикаментів eHealth.
  ///
  /// [source] — джерело ("ehealth")
  /// [page] — номер сторінки (500 записів на сторінку, всього ~24 сторінки)
  static Future<CietResult<Map<String, dynamic>>> getDictionary({
    String source = 'ehealth',
    int page = 1,
  }) async {
    try {
      final uri = Uri.parse('${CietConfig.baseUrl}/get-dictionary')
          .replace(queryParameters: {
        'source': source,
        'page': page.toString(),
      });

      final response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${CietConfig.authKey}',
      }).timeout(CietConfig.timeout);

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      // Paginated response — data is in json['data']
      if (json['data'] != null) {
        return CietResult.ok(json);
      }

      return CietResult.fail(json['message']?.toString() ?? 'Помилка');
    } catch (e) {
      debugPrint('CIET 1303 dictionary error: $e');
      return CietResult.fail('Помилка: $e');
    }
  }

  /// Створити кошик (cart) для пацієнта.
  ///
  /// [visitId] — UUID візиту
  /// [cartLink] — URL кошика
  static Future<CietResult<Map<String, dynamic>>> createCart({
    required String visitId,
    required String cartLink,
  }) async {
    try {
      final uri = Uri.parse('${CietConfig.baseUrl}/cart-create');

      final request = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${CietConfig.authKey}'
        ..fields['visit_id'] = visitId
        ..fields['cart_link'] = cartLink
        ..fields['pharmacy_id'] = CietConfig.pharmacyId;

      final streamed = await _client.send(request).timeout(CietConfig.timeout);
      final response = await http.Response.fromStream(streamed);

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (json['status'] == 'success') {
        debugPrint('CIET 1303: cart created for visit $visitId');
        return CietResult.ok(json);
      }

      final message = json['message']?.toString() ?? 'Невідома помилка';
      debugPrint('CIET 1303 cart error: $message');
      return CietResult.fail(message);
    } catch (e) {
      debugPrint('CIET 1303 cart error: $e');
      return CietResult.fail('Помилка з\'єднання: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Data models
// ═══════════════════════════════════════════════════════════════════════════════

/// Препарат у замовленні CIET.
class CietOrderDrug {
  final int count;
  final double retailPriceWithoutVat;
  final double retailPriceWithVat;
  final double priceWithoutVat;
  final double priceWithVat;
  final double amountWithoutVat;
  final double amountWithVat;
  final String drugSeries;
  final String seriesExpirationDate; // "DD.MM.YYYY"

  const CietOrderDrug({
    required this.count,
    required this.retailPriceWithoutVat,
    required this.retailPriceWithVat,
    required this.priceWithoutVat,
    required this.priceWithVat,
    required this.amountWithoutVat,
    required this.amountWithVat,
    required this.drugSeries,
    required this.seriesExpirationDate,
  });

  Map<String, String> toJson() => {
        'count': count.toString(),
        'retail_price_without_vat': retailPriceWithoutVat.toStringAsFixed(2),
        'retail_price_with_vat': retailPriceWithVat.toStringAsFixed(2),
        'price_without_vat': priceWithoutVat.toStringAsFixed(2),
        'price_with_vat': priceWithVat.toStringAsFixed(2),
        'amount_without_vat': amountWithoutVat.toStringAsFixed(2),
        'amount_with_vat': amountWithVat.toStringAsFixed(2),
        'drug_series': drugSeries,
        'series_expiration_date': seriesExpirationDate,
      };
}

/// Result wrapper.
class CietResult<T> {
  final bool success;
  final T? data;
  final String? error;

  const CietResult({required this.success, this.data, this.error});

  factory CietResult.ok(T data) => CietResult(success: true, data: data);
  factory CietResult.fail(String error) =>
      CietResult(success: false, error: error);
}
