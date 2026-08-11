import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/money.dart';
import '../models/payment_terminal.dart';
import '../models/terminal_txn_result.dart';
import 'fiscal_log.dart';

/// ECR-клієнт платіжного терміналу ПриватБанк (пропрієтарний **JSON**-протокол).
///
/// Порт із legacy `docs/uPosJson.pas` (клас `TPosJSON`). Транспорт — TCP;
/// повідомлення — JSON, розділені байтом **`0x00`**; перше повідомлення після
/// конекту — з ВЕДУЧИМ `0x00` (як `AFirstZero` у legacy). Один термінал = одна
/// транзакція за раз.
///
/// Послідовність (як `CommOpenTCP`): connect → `PingDevice` (ведучий 0x00) →
/// `ServiceMessage/identify` → далі команди (`Purchase`/`Refund`/…) по тому ж
/// сокету; відповіді читаються фоновим циклом і зіставляються за `method`.
///
/// ⚠️ КАРКАС (JSON-first). Свідомо НЕ реалізовано (TODO, окремі кроки):
///  - **джерело host:port** терміналу (реєстр `ZSMU\Farm` чи поля `GetTermBank`)
///    — поки передається в конструктор ззовні;
///  - **проміжні статуси** (`deviceBusy`, `ServiceMessage getLastStatMsgCode`,
///    «ОЧІКУЮ КАРТКУ») — наразі лише логуються, чекаємо фінальну відповідь;
///  - **BPOS**-протокол (окрема фаза — COM `ECRCommXLib`, не JSON);
///  - друк сліпа (`receipt`), `Audit`(X)/`Verify`(Z)/`Settlement`;
///  - інтеграція в `cart_panel._sendFiscalReceipt` (Purchase → PutTermData →
///    накладна → GetDataRRO), коли Катя дасть контракт `PutTermData`.
class EcrTerminalClient {
  EcrTerminalClient({
    required this.host,
    required this.port,
    this.connectTimeout = const Duration(seconds: 5),
    this.commandTimeout = const Duration(seconds: 30),
    this.purchaseTimeout = const Duration(seconds: 90),
    this.onStatus,
  });

  /// Колбек проміжних статусів терміналу (напр. «ОЧІКУЮ КАРТКУ») — для UI.
  /// Отримує вже людиночитабельний рядок.
  final void Function(String status)? onStatus;

  /// Клієнт для обраного терміналу з `GetTermBank` (`termIP`/`termPort`).
  /// Повертає `null`, якщо термінал без адреси або не JSON-протоколу
  /// (BPOS/Ощад — окрема пізніша фаза).
  static EcrTerminalClient? forTerminal(
    PaymentTerminal t, {
    void Function(String status)? onStatus,
  }) {
    if (!t.isSupported || t.portNumber <= 0) return null;
    return EcrTerminalClient(
        host: t.termIP, port: t.portNumber, onStatus: onStatus);
  }

  final String host;
  final int port;
  final Duration connectTimeout;
  final Duration commandTimeout;

  /// Purchase/Refund чекають картку — довший таймаут (як в описі ПриватБанк ~60с).
  final Duration purchaseTimeout;

  Socket? _socket;
  final List<int> _rx = [];
  bool _firstSend = true;
  _Pending? _pending;

  bool get isConnected => _socket != null;

  // ── Підключення + хендшейк ────────────────────────────────────────────────

  /// Відкрити TCP, зробити хендшейк (`PingDevice` → `identify`). `true` — готово.
  Future<bool> connect() async {
    await close();
    try {
      _socket = await Socket.connect(host, port, timeout: connectTimeout);
      _firstSend = true;
      _rx.clear();
      _socket!.listen(
        _onData,
        onError: _onSocketError,
        onDone: _onSocketDone,
        cancelOnError: true,
      );
    } catch (e) {
      FiscalLog.log('ECR connect FAIL $host:$port — $e');
      _socket = null;
      return false;
    }

    // 1) PingDevice (ведучий 0x00) — «розбудити»/перевірити зв'язок.
    final ping = await _command(
      responseMethod: 'PingDevice',
      request: {'method': 'PingDevice', 'step': 0},
    );
    if (ping.errorKind != EcrErrorKind.none || ping.terminalError) {
      FiscalLog.log('ECR handshake: PingDevice FAIL — ${ping.errorDescription}');
      await close();
      return false;
    }

    // 2) ServiceMessage identify — валідація/вендор-модель.
    final ident = await _command(
      responseMethod: 'ServiceMessage',
      request: {
        'method': 'ServiceMessage',
        'step': 0,
        'params': {'msgType': 'identify'},
      },
    );
    if (ident.errorKind != EcrErrorKind.none || ident.terminalError) {
      FiscalLog.log('ECR handshake: identify FAIL — ${ident.errorDescription}');
      await close();
      return false;
    }

    FiscalLog.log('ECR connected $host:$port (handshake ok)');
    return true;
  }

  Future<void> close() async {
    final s = _socket;
    _socket = null;
    final p = _pending;
    _pending = null;
    if (p != null && !p.completer.isCompleted) {
      p.completer.complete(TerminalTxnResult.localError(
          EcrErrorKind.socket, 'зʼєднання закрито',
          method: p.responseMethod));
    }
    if (s != null) {
      try {
        await s.close();
      } catch (_) {}
      s.destroy();
    }
  }

  // ── Команди ───────────────────────────────────────────────────────────────

  /// Оплата: [amount] — сума до сплати. `merchantId` за замовч. 1 (константа
  /// роздробу, Андрій). Повертає результат (перевіряти `approved`).
  Future<TerminalTxnResult> purchase(Money amount, {int merchantId = 1}) async {
    final amt = _grn(amount);
    FiscalLog.log('ECR Purchase → $host:$port amount=$amt merchant=$merchantId');
    final res = await _command(
      responseMethod: 'Purchase',
      timeout: purchaseTimeout,
      request: {
        'method': 'Purchase',
        'step': 0,
        'params': {
          'amount': amt,
          'discount': '',
          'merchantId': '$merchantId',
          'facepay': 'false',
        },
      },
    );
    FiscalLog.log('ECR Purchase ← approved=${res.approved} '
        'rc=${res.responseCode} rrn=${res.rrn} auth=${res.approvalCode}'
        '${res.approved ? '' : ' err=${res.errorDescription}'}');
    return res;
  }

  /// Повернення за [rrn] початкової оплати на суму [amount].
  Future<TerminalTxnResult> refund(Money amount, String rrn,
      {int merchantId = 1}) async {
    final amt = _grn(amount);
    FiscalLog.log('ECR Refund → amount=$amt rrn=$rrn');
    final res = await _command(
      responseMethod: 'Refund',
      timeout: purchaseTimeout,
      request: {
        'method': 'Refund',
        'step': 0,
        'params': {
          'amount': amt,
          'discount': '0.00',
          'merchantId': '$merchantId',
          'rrn': rrn,
        },
      },
    );
    FiscalLog.log('ECR Refund ← approved=${res.approved} rc=${res.responseCode}');
    return res;
  }

  /// Перевірка зв'язку з терміналом (`PingDevice`).
  Future<bool> ping() async {
    final res = await _command(
      responseMethod: 'PingDevice',
      request: {'method': 'PingDevice', 'step': 0},
    );
    return res.errorKind == EcrErrorKind.none && !res.terminalError;
  }

  // ── Транспорт ─────────────────────────────────────────────────────────────

  String _grn(Money m) => (m.kopiykas / 100).toStringAsFixed(2);

  /// Надіслати запит і дочекатись відповіді з `method == responseMethod`.
  /// Проміжні повідомлення (інший method) — логуються, чекаємо далі.
  Future<TerminalTxnResult> _command({
    required String responseMethod,
    required Map<String, dynamic> request,
    Duration? timeout,
  }) async {
    final s = _socket;
    if (s == null) {
      return TerminalTxnResult.localError(
          EcrErrorKind.socket, 'сокет не відкритий', method: responseMethod);
    }
    if (_pending != null && !_pending!.completer.isCompleted) {
      return TerminalTxnResult.localError(
          EcrErrorKind.socket, 'термінал зайнятий іншою операцією',
          method: responseMethod);
    }

    final completer = Completer<TerminalTxnResult>();
    _pending = _Pending(responseMethod, completer);

    try {
      _write(s, jsonEncode(request));
    } catch (e) {
      _pending = null;
      return TerminalTxnResult.localError(
          EcrErrorKind.socket, 'помилка надсилання: $e',
          method: responseMethod);
    }

    try {
      return await completer.future.timeout(timeout ?? commandTimeout);
    } on TimeoutException {
      return TerminalTxnResult.localError(
          EcrErrorKind.timeout, 'термінал не відповів', method: responseMethod);
    } finally {
      _pending = null;
    }
  }

  /// UTF8(json) + завершальний 0x00; перше повідомлення на сокеті — з ведучим
  /// 0x00 (як `StringToByteArray(AFirstZero)` у legacy).
  void _write(Socket s, String json) {
    final bytes = <int>[];
    if (_firstSend) {
      bytes.add(0);
      _firstSend = false;
    }
    bytes.addAll(utf8.encode(json));
    bytes.add(0);
    s.add(bytes);
  }

  void _onData(List<int> data) {
    for (final b in data) {
      if (b == 0) {
        if (_rx.isNotEmpty) {
          final raw = utf8.decode(_rx, allowMalformed: true);
          _rx.clear();
          _dispatch(raw);
        }
      } else {
        _rx.add(b);
      }
    }
  }

  void _dispatch(String raw) {
    Map<String, dynamic>? msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) msg = decoded;
    } catch (_) {}
    if (msg == null) {
      FiscalLog.log('ECR RX (не JSON): ${raw.length > 200 ? raw.substring(0, 200) : raw}');
      return;
    }

    final method = msg['method']?.toString() ?? '';
    final p = _pending;
    if (p != null && !p.completer.isCompleted && method == p.responseMethod) {
      p.completer.complete(TerminalTxnResult.fromResponse(msg));
    } else {
      // Проміжний статус (deviceBusy / ServiceMessage / інший method) —
      // логуємо і віддаємо в UI (напр. «ОЧІКУЮ КАРТКУ»).
      FiscalLog.log('ECR RX async: method=$method params=${msg['params']}');
      final params = msg['params'];
      final status = params is Map
          ? (params['statMsgDescription'] ??
                  params['description'] ??
                  params['result'] ??
                  method)
              .toString()
          : method;
      if (status.isNotEmpty) onStatus?.call(status);
    }
  }

  void _onSocketError(Object e) {
    FiscalLog.log('ECR socket error: $e');
    final p = _pending;
    _pending = null;
    if (p != null && !p.completer.isCompleted) {
      p.completer.complete(TerminalTxnResult.localError(
          EcrErrorKind.socket, 'помилка сокета: $e',
          method: p.responseMethod));
    }
    _socket = null;
  }

  void _onSocketDone() {
    FiscalLog.log('ECR socket closed by terminal');
    final p = _pending;
    _pending = null;
    if (p != null && !p.completer.isCompleted) {
      p.completer.complete(TerminalTxnResult.localError(
          EcrErrorKind.socket, 'термінал розірвав зʼєднання',
          method: p.responseMethod));
    }
    _socket = null;
  }
}

class _Pending {
  _Pending(this.responseMethod, this.completer);
  final String responseMethod;
  final Completer<TerminalTxnResult> completer;
}
