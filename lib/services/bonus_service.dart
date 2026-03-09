import 'api_config.dart';
import 'cache_api_client.dart';

/// Результат списання бонусів.
class BonusWriteOffResult {
  final bool success;
  final String? error;

  BonusWriteOffResult({required this.success, this.error});
}

/// Сервіс роботи з бонусами (списання/відміна).
///
/// Caché сервіси: SpisanieBonusov, OtmenaSpisanieBonusov
class BonusService {
  static final _api = CacheApiClient();

  /// Списати бонуси.
  ///
  /// Caché: `GET ?ServiceName=SpisanieBonusov&...`
  static Future<BonusWriteOffResult> writeOff({
    required String clientCode,
    required double amount,
  }) async {
    if (ApiConfig.useMock) return _mockWriteOff(amount);

    final response = await _api.call('SpisanieBonusov', params: {
      'client': clientCode,
      'sum': amount.toStringAsFixed(2),
    });

    if (!response.isOk) {
      return BonusWriteOffResult(
        success: false,
        error: response.result,
      );
    }

    return BonusWriteOffResult(success: true);
  }

  /// Відмінити списання бонусів.
  ///
  /// Caché: `GET ?ServiceName=OtmenaSpisanieBonusov&...`
  static Future<BonusWriteOffResult> cancelWriteOff({
    required String clientCode,
  }) async {
    if (ApiConfig.useMock) return BonusWriteOffResult(success: true);

    final response = await _api.call('OtmenaSpisanieBonusov', params: {
      'client': clientCode,
    });

    if (!response.isOk) {
      return BonusWriteOffResult(
        success: false,
        error: response.result,
      );
    }

    return BonusWriteOffResult(success: true);
  }

  // ---------------------------------------------------------------------------
  // Mock
  // ---------------------------------------------------------------------------

  static Future<BonusWriteOffResult> _mockWriteOff(double amount) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return BonusWriteOffResult(success: true);
  }
}
