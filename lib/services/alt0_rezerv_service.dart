import 'cache_api_client.dart';
import 'fiscal_log.dart';

/// Дані для відпуску «складного» ІЗ (код видачі, страхова, кур'єр) —
/// `Alt0Rezerv&NumNakl`, Катя 26.10 (док специфікації, кінець).
class Alt0Info {
  /// Код видачі, з яким звіряємо введене (клієнт називає; НЕ показувати).
  final String lblPass;

  /// Код, який вписує фармацевт замість клієнта (напр. відпуск за PlanB).
  final String edPass;

  /// "BN" — при відпуску немає пробиття чека, є «Відпущено» (доставка —
  /// «передано кур'єру»).
  final String tNakl;

  /// Телефон з ІЗ; порожній — треба ідентифікувати клієнта.
  final String phone;

  /// Віртуальний термінал оплати (LIQPAY/BINANCE/PRIVATQR/Ліки24).
  final String virtTermKod;
  final String virtTermName;

  const Alt0Info({
    this.lblPass = '',
    this.edPass = '',
    this.tNakl = '',
    this.phone = '',
    this.virtTermKod = '',
    this.virtTermName = '',
  });

  bool get needsCode => lblPass.isNotEmpty;
  bool get noFiscalOnIssue => tNakl.trim().toUpperCase() == 'BN';
}

class Alt0RezervService {
  static String _s(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// null — сервіс недоступний або відповів помилкою.
  static Future<Alt0Info?> fetch(String numNakl) async {
    try {
      final r = await CacheApiClient()
          .call('Alt0Rezerv', params: {'NumNakl': numNakl});
      if (!r.isOk) {
        FiscalLog.log('Alt0Rezerv $numNakl FAIL: ${r.result}');
        return null;
      }
      final d = r.data;
      final info = Alt0Info(
        lblPass: _s(d, ['lblPass', 'LblPass']),
        edPass: _s(d, ['edPass', 'EdPass']),
        tNakl: _s(d, ['tNakl', 'TNakl']),
        phone: _s(d, ['phone', 'Phone']),
        virtTermKod: _s(d, ['LblvirttermKod', 'lblvirttermKod']),
        virtTermName: _s(d, ['LblvirttermName', 'lblvirttermName']),
      );
      // Сам код у журнал НЕ пишемо — лише чи він є.
      FiscalLog.log('Alt0Rezerv $numNakl: код видачі '
          '${info.needsCode ? "є" : "немає"}, edPass '
          '${info.edPass.isNotEmpty ? "є" : "немає"}, tNakl="${info.tNakl}", '
          'термінал="${info.virtTermKod}"');
      return info;
    } catch (e) {
      FiscalLog.log('Alt0Rezerv $numNakl помилка: $e');
      return null;
    }
  }
}
