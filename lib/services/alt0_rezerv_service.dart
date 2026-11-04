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

  /// ЄДРПОУ страхової (`lblIns`); непорожній — страхове ІЗ.
  final String lblIns;

  /// Служба доставки (`lblwds`).
  final String lblWds;

  /// Накладні замовлення (`NumNakls`, через «;»).
  final String numNakls;

  /// Номер ІЗ (`idorder`).
  final String idOrder;

  /// `BtnOtpuskBN` — чи активна кнопка «Відпущено» для BN.
  final bool btnOtpuskBN;

  const Alt0Info({
    this.lblPass = '',
    this.edPass = '',
    this.tNakl = '',
    this.phone = '',
    this.virtTermKod = '',
    this.virtTermName = '',
    this.lblIns = '',
    this.lblWds = '',
    this.numNakls = '',
    this.idOrder = '',
    this.btnOtpuskBN = true,
  });

  bool get needsCode => lblPass.isNotEmpty;
  bool get noFiscalOnIssue => tNakl.trim().toUpperCase() == 'BN';

  /// Страхове ІЗ: відпуск — OtpuskRecipe + друк заявки (PrintZCheck).
  bool get isInsurance => lblIns.isNotEmpty;
}

/// Результат OtpuskRecipe / SetStatusWds:
/// `{"Status":"OK","Result":"...","Count":N,"Nakls":[...]}`.
class BnIssueResult {
  final bool ok;
  final String message;
  final int count;
  const BnIssueResult(this.ok, this.message, this.count);
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
        lblIns: _s(d, ['lblIns', 'LblIns']),
        lblWds: _s(d, ['lblwds', 'lblWds', 'Lblwds']),
        numNakls: _s(d, ['NumNakls', 'numNakls']),
        idOrder: _s(d, ['idorder', 'idOrder']),
        // Порожньо — вважаємо активною: сервер не заборонив.
        btnOtpuskBN: _s(d, ['BtnOtpuskBN', 'btnOtpuskBN']) != '0',
      );
      // Сам код у журнал НЕ пишемо — лише чи він є.
      FiscalLog.log('Alt0Rezerv $numNakl: код видачі '
          '${info.needsCode ? "є" : "немає"}, edPass '
          '${info.edPass.isNotEmpty ? "є" : "немає"}, tNakl="${info.tNakl}", '
          'термінал="${info.virtTermKod}", страхова="${info.lblIns}", '
          'доставка="${info.lblWds}", BtnOtpuskBN=${info.btnOtpuskBN ? 1 : 0}');
      return info;
    } catch (e) {
      FiscalLog.log('Alt0Rezerv $numNakl помилка: $e');
      return null;
    }
  }

  static Future<BnIssueResult> _bn(
      String service, Map<String, String> params) async {
    try {
      final r = await CacheApiClient().call(service, params: params);
      final count = int.tryParse(r.data['Count']?.toString() ?? '') ?? 0;
      FiscalLog.log('$service ${params['NumNakl']}: '
          '${r.isOk ? "OK" : "FAIL"} ${r.result} Count=$count');
      return BnIssueResult(r.isOk, r.result, count);
    } catch (e) {
      FiscalLog.log('$service ${params['NumNakl']} помилка: $e');
      return BnIssueResult(false, '$e', 0);
    }
  }

  /// Відпуск страхового ІЗ (Катя, док специфікації). [numNakls] — через «;».
  static Future<BnIssueResult> otpuskRecipe(String numNakls) =>
      _bn('OtpuskRecipe', {'NumNakl': numNakls});

  /// Доставка: `stat=courier` — передано кур'єру.
  static Future<BnIssueResult> setStatusWds(String numNakls,
          {String stat = 'courier'}) =>
      _bn('SetStatusWds', {'NumNakl': numNakls, 'stat': stat});

  /// Рядки заявки для страхової (`PrintZCheck`): `Lines` + ширина
  /// `strlength`. null — сервіс не дав рядків.
  static Future<(List<String>, int)?> printZCheck(
      String numNakl, String idOrder) async {
    try {
      final r = await CacheApiClient().call('PrintZCheck',
          params: {'NumNakl': numNakl, 'idorder': idOrder});
      final lines = r.data['Lines'];
      if (!r.isOk || lines is! List || lines.isEmpty) {
        FiscalLog.log('PrintZCheck $numNakl/$idOrder FAIL: ${r.result} '
            'Lines=${lines is List ? lines.length : "—"}');
        return null;
      }
      final width = int.tryParse(r.data['strlength']?.toString() ?? '') ?? 0;
      FiscalLog.log('PrintZCheck $numNakl/$idOrder: ${lines.length} рядків, '
          'ширина $width, idReq=${r.data['idReq'] ?? ""}');
      return (lines.map((l) => l?.toString() ?? '').toList(), width);
    } catch (e) {
      FiscalLog.log('PrintZCheck $numNakl/$idOrder помилка: $e');
      return null;
    }
  }
}
