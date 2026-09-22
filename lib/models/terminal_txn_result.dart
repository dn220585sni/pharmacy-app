import 'money.dart';

/// Тип локальної (клієнтської) помилки при спілкуванні з терміналом —
/// НЕ відмова банку, а проблема транспорту/логіки на нашому боці.
enum EcrErrorKind {
  none, // немає локальної помилки (дивись responseCode/error від терміналу)
  socket, // не вдалось під'єднатись — запит до термінала НЕ дійшов
  timeout, // термінал не відповів у відведений час (запит ще не надсилався)
  badResponse, // відповідь не розпарсилась

  /// Запит НАДІСЛАНО, а відповіді немає (таймаут або розрив після надсилання).
  /// Термінал міг виконати операцію — результат НЕВІДОМИЙ. Для Purchase це
  /// означає: не «відмова», а «звірити через GetReceiptInfo або руками».
  unknown,
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
  final String discountName; // назва знижки (getDiscountName; у JSON зазвичай '')
  final String rnk; // РНК клієнта (у JSON Purchase зазвичай відсутній)
  final String signVerif; // 0 — підпис не потрібен, 1 — потрібен
  final String txnType; // 1 Purchase / 2 Refund / 3 Void
  final String receipt; // текст сліпа для друку (CurrentReceiptCard)

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
    this.discountName = '',
    this.rnk = '',
    this.signVerif = '',
    this.txnType = '',
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
      discountName: s('discountName'),
      rnk: s('rnk'),
      signVerif: s('signVerif'),
      txnType: s('txnType'),
      receipt: s('receipt'),
    );
  }

  /// Успіх: дійшли до терміналу, без помилки, responseCode "0000".
  bool get approved =>
      errorKind == EcrErrorKind.none && !terminalError && responseCode == '0000';

  /// Скасовано користувачем на терміналі (responseCode 1001).
  bool get cancelledByUser => responseCode == '1001';

  /// Результат операції невідомий: запит пішов у термінал, відповіді немає.
  bool get resultUnknown => errorKind == EcrErrorKind.unknown;

  /// `date` + `time` терміналу як момент часу (локальний); `null`, якщо
  /// не розпарсились.
  DateTime? get dateTime {
    final d = date.split('.');
    final t = time.split(':');
    if (d.length != 3 || t.length < 2) return null;
    final day = int.tryParse(d[0]), mon = int.tryParse(d[1]);
    var year = int.tryParse(d[2]);
    final hh = int.tryParse(t[0]), mm = int.tryParse(t[1]);
    final ss = t.length >= 3 ? int.tryParse(t[2]) ?? 0 : 0;
    if (day == null || mon == null || year == null || hh == null || mm == null) {
      return null;
    }
    if (year < 100) year += 2000;
    return DateTime(year, mon, day, hh, mm, ss);
  }

  /// Сума транзакції як [Money]; `null`, якщо не число.
  Money? get amountMoney => Money.tryParse(amount.replaceAll(',', '.'));

  /// Чи цей чек (з `GetReceiptInfo`) — саме наша оплата: схвалена Purchase на
  /// [amount], проведена не раніше [notBefore] (момент, коли ми надіслали
  /// Purchase, з запасом на розбіжність годинників). Використовується після
  /// невідомого результату, щоб відрізнити «оплата пройшла, відповідь
  /// загубилась» від «останній чек терміналу — чужий/старий».
  bool isPurchaseOf(Money amount, {required DateTime notBefore}) {
    if (!approved) return false;
    // txnType порожній у старих прошивках — не відкидаємо, лише явний не-Purchase.
    if (txnType.isNotEmpty && txnType != '1') return false;
    if (amountMoney != amount) return false;
    final at = dateTime;
    if (at == null) return false;
    return !at.isBefore(notBefore.subtract(const Duration(minutes: 5)));
  }

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

  /// Дата у форматі PutTermData `dd/mm/yyyy` (з JSON `date` "dd.mm.yyyy").
  String get dateSlash => date.contains('.') ? date.replaceAll('.', '/') : date;

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

  /// Скласти `ParamsPayCard` для сервісу `PutTermData` (Катя, контракт
  /// TFS.OschadTrxComplete): **21 поле, роздільник — ТАБУЛЯЦІЯ**, у точному
  /// порядку. [ssum] — сума чека, [sumCash] — сума видачі готівки (ВХІДНІ, що
  /// шлемо в термінал); [codeKsTerm] — `kodterm` обраного терміналу (до якої
  /// каси прив'язаний). Оригінальний чек (`CurrentReceiptCard`) — це [receipt],
  /// передається окремим параметром сервісу.
  String buildParamsPayCard({
    required Money ssum,
    Money sumCash = Money.zero,
    required String codeKsTerm,
  }) {
    String grn(Money m) => (m.kopiykas / 100).toStringAsFixed(2);
    // Прибрати табуляцію всередині значень, щоб не зламати роздільник полів.
    String f(String v) => v.replaceAll('\t', ' ');
    final fields = <String>[
      f(terminalId), // 1
      f(merchant), // 2
      f(invoiceNumber), // 3
      f(amount.replaceAll(',', '.')), // 4 — сума транзакції
      f(issuerName), // 5 — тип карти
      f(pan), // 6
      cardHolderName.replaceAll('\t', ';'), // 7
      f(approvalCode), // 8
      f(rrn), // 9
      f(dateSlash), // 10 — dd/mm/yyyy
      f(time), // 11 — hh:mm:ss
      f(signVerif), // 12
      f(txnType), // 13 — 1 Purchase / 2 Refund / 3 Void
      grn(ssum), // 14 — сума чека
      grn(sumCash), // 15 — сума видачі готівки
      f(discountName), // 16
      f(rnk), // 17
      f(rrnExt), // 18
      '0', // 19 — TrnBatchNum (JSON завжди 0)
      f(codeKsTerm), // 20 — CodeKsTerm
      '', // 21 — lastresult (порожньо)
    ];
    return fields.join('\t');
  }
}
