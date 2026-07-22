import 'money.dart';

/// Тип локальної (клієнтської) помилки при спілкуванні з терміналом —
/// НЕ відмова банку, а проблема транспорту/логіки на нашому боці.
enum EcrErrorKind {
  none, // немає локальної помилки (дивись responseCode/error від терміналу)
  socket, // не вдалось під'єднатись/розрив зв'язку
  timeout, // термінал не відповів у відведений час
  badResponse, // відповідь не розпарсилась
}

/// Результат транзакції на платіжному терміналі (ECR JSON, ПриватБанк).
///
/// Розбирає конверт відповіді `{method, step, params:{...}, error,
/// errorDescription}` (див. [uPosJson.pas] `TPurchaseParams`). Ті самі поля
/// потрібні і для `pay_terminal` в GetDataRRO, і для сервісу збереження
/// банк-даних (`PutTermData`) — мапінг у [toPayTerminal] / [toPutTermData].
class TerminalTxnResult {
  /// Метод відповіді ("Purchase" / "Refund" / …).
  final String method;

  /// Локальна помилка (транспорт/парсинг). `none` — дійшли до терміналу.
  final EcrErrorKind errorKind;

  /// `error:true` від терміналу (логічна відмова).
  final bool terminalError;

  /// Опис помилки (з `errorDescription` або локальний).
  final String errorDescription;

  // ── params з відповіді терміналу ──────────────────────────────────────────
  final String responseCode; // "0000" = успіх
  final String approvalCode; // код авторизації → auth_code
  final String amount; // сума транзакції (грн, з крапкою)
  final String pan; // маскований PAN → epz
  final String date; // "dd.mm.yyyy"
  final String time; // "hh:mm:ss"
  final String cardHolderName;
  final String invoiceNumber; // № чека терміналу
  final String issuerName;
  final String merchant; // ідентифікатор торгової точки
  final String rrn;
  final String rrnExt;
  final String terminalId;
  final String paymentSystem; // VISA/MASTER → card_type
  final String cardExpiryDate;
  final String discount;
  final String receipt; // текст сліпа для друку

  const TerminalTxnResult({
    required this.method,
    this.errorKind = EcrErrorKind.none,
    this.terminalError = false,
    this.errorDescription = '',
    this.responseCode = '',
    this.approvalCode = '',
    this.amount = '',
    this.pan = '',
    this.date = '',
    this.time = '',
    this.cardHolderName = '',
    this.invoiceNumber = '',
    this.issuerName = '',
    this.merchant = '',
    this.rrn = '',
    this.rrnExt = '',
    this.terminalId = '',
    this.paymentSystem = '',
    this.cardExpiryDate = '',
    this.discount = '',
    this.receipt = '',
  });

  /// Локальна помилка (без відповіді терміналу).
  factory TerminalTxnResult.localError(
    EcrErrorKind kind,
    String message, {
    String method = '',
  }) =>
      TerminalTxnResult(
        method: method,
        errorKind: kind,
        errorDescription: message,
      );

  /// Розібрати конверт відповіді ECR-терміналу.
  factory TerminalTxnResult.fromResponse(Map<String, dynamic> json) {
    final p = (json['params'] as Map?)?.cast<String, dynamic>() ?? const {};
    String s(String k) => p[k]?.toString() ?? '';
    return TerminalTxnResult(
      method: json['method']?.toString() ?? '',
      terminalError: json['error'] == true,
      errorDescription: json['errorDescription']?.toString() ?? '',
      responseCode: s('responseCode'),
      approvalCode: s('approvalCode'),
      amount: s('amount'),
      pan: s('pan'),
      date: s('date'),
      time: s('time'),
      cardHolderName: s('cardHolderName'),
      invoiceNumber: s('invoiceNumber'),
      issuerName: s('issuerName'),
      merchant: s('merchant'),
      rrn: s('rrn'),
      rrnExt: s('rrnExt'),
      terminalId: s('terminalId'),
      paymentSystem: s('paymentSystem'),
      cardExpiryDate: s('cardExpiryDate'),
      discount: s('discount'),
      receipt: s('receipt'),
    );
  }

  /// Успіх: дійшли до терміналу, без помилки, responseCode "0000".
  bool get approved =>
      errorKind == EcrErrorKind.none && !terminalError && responseCode == '0000';

  /// Скасовано користувачем на терміналі (responseCode 1001).
  bool get cancelledByUser => responseCode == '1001';

  // ── Похідні поля для pay_terminal / PutTermData ───────────────────────────

  String get authCode => approvalCode;
  String get epz => pan;
  String get cardType => paymentSystem.isNotEmpty ? paymentSystem : issuerName;

  /// Дата+час у форматі legacy `yymmddhhmmss` (з `date`+`time`); '' якщо не
  /// розпарсилось.
  String get dateTimeCompact {
    // date "dd.mm.yyyy", time "hh:mm:ss"
    final d = date.split('.');
    final t = time.split(':');
    if (d.length != 3 || t.length < 2) return '';
    final yy = d[2].length >= 2 ? d[2].substring(d[2].length - 2) : d[2];
    final ss = t.length >= 3 ? t[2] : '00';
    String two(String v) => v.padLeft(2, '0');
    return '$yy${two(d[1])}${two(d[0])}${two(t[0])}${two(t[1])}${two(ss)}';
  }

  /// Мапінг у блок `pay_terminal` (GetDataRRO) — для довідки/логів.
  Map<String, String> toPayTerminal() => {
        'auth_code': authCode,
        'rrn': rrn,
        'epz': epz,
        'terminal_id': terminalId,
        'card_type': cardType,
        'name': merchant,
        'additional_text': '',
      };

  /// Мапінг у сервіс збереження банк-даних (`PutTermData`).
  /// ⚠️ ПРОВІЗОРНО: точні назви параметрів чекаємо від Каті (контракт сервісу).
  /// [ssum] — сума чека, [sumCash] — сума видачі готівки (ВХІДНІ, що шлемо в
  /// термінал); решта — з відповіді. `trnBatchNum` для JSON завжди 0; `rnk`
  /// у JSON-відповіді Purchase відсутній (лишаємо порожнім).
  Map<String, String> toPutTermData({
    required Money ssum,
    Money sumCash = Money.zero,
  }) {
    String grn(Money m) => (m.kopiykas / 100).toStringAsFixed(2);
    return {
      'ssum': grn(ssum),
      'sumCash': grn(sumCash),
      'amount': amount,
      'invoiceNumber': invoiceNumber,
      'merchantId': merchant,
      'cardHolder': cardHolderName,
      'terminalId': terminalId,
      'authCode': approvalCode,
      'dateTime': dateTimeCompact,
      'rrn': rrn,
      'discountName': discount,
      'pan': pan,
      'rnk': '',
      'rrnExt': rrnExt,
      'trnBatchNum': '0',
    };
  }
}
