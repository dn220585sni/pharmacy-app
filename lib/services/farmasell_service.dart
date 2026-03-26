import 'dart:convert';
import 'package:http/http.dart' as http;

/// Результат запиту знижки "Рука допомоги" від FarmaSell API.
class HelpingHandResult {
  final bool success;
  final double? discountPrice;
  final String? error;

  const HelpingHandResult({
    required this.success,
    this.discountPrice,
    this.error,
  });
}

/// Клієнт FarmaSell API для програми "Рука допомоги".
class FarmaSellService {
  static const _baseUrl = 'https://farmasell.ua/api';
  static const _timeout = Duration(seconds: 10);

  /// Отримати знижку "Рука допомоги" для клієнта.
  static Future<HelpingHandResult> getHelpingHandDiscount({
    required String clientPhone,
    required String sku,
    required double comingPrice,
    required String comingCode,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/helping-hand/discount').replace(
        queryParameters: {
          'phone': clientPhone,
          'sku': sku,
          'comingPrice': comingPrice.toString(),
          'comingCode': comingCode,
        },
      );

      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        return HelpingHandResult(
          success: false,
          error: 'HTTP ${response.statusCode}',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final price = double.tryParse(json['discountPrice']?.toString() ?? '');

      return HelpingHandResult(
        success: json['status'] == 'OK' && price != null,
        discountPrice: price,
      );
    } catch (e) {
      return HelpingHandResult(success: false, error: '$e');
    }
  }
}
