import 'dart:async';

import 'package:flutter/material.dart';

import '../models/money.dart';
import '../models/payment_terminal.dart';
import '../models/terminal_txn_result.dart';
import '../services/ecr_terminal_client.dart';
import '../services/fiscal_log.dart';

/// Етап карткової сесії (для UI).
enum _CardStage {
  connecting, // під'єднуємось до терміналу
  waitingCard, // «ОЧІКУЮ КАРТКУ»
  processing, // «Виконується підтвердження оплати»
  verifying, // відповіді немає — звіряємо GetReceiptInfo
  success, // «Оплата успішна»
  declined, // відмова/помилка — retry / відкат-у-готівку
  unknown, // звірка не вдалась — лише ручне врегулювання
}

/// Модальне вікно карткової оплати через ECR-термінал (ПриватБанк JSON).
///
/// За описом Europharma: надсилає суму на термінал (`Purchase`), показує
/// статуси («ОЧІКУЮ КАРТКУ» → «підтвердження…»), при успіху авто-закривається,
/// при відмові дає **повторити** або **відмінити БГ → оплата готівкою**.
///
/// Невідомий результат (таймаут/розрив ПІСЛЯ надсилання Purchase) — НЕ
/// відмова: гроші могли списатись. Спершу звірка `GetReceiptInfo`
/// (останній чек терміналу); якщо вона не вдалась — «РЕЗУЛЬТАТ НЕВІДОМИЙ»
/// і будь-який наступний платіж (карткою чи готівкою) лише після того, як
/// касир підтвердить, що перевірив термінал.
///
/// Повертає:
/// - `TerminalTxnResult` (approved) — оплата пройшла;
/// - `null` — касир обрав «відміна БГ / готівка» (або закрив вікно).
class CardPaymentDialog extends StatefulWidget {
  const CardPaymentDialog({
    super.key,
    required this.terminal,
    required this.amount,
    this.demoOutcome,
  });

  final PaymentTerminal terminal;
  final Money amount;

  /// Демо-прев'ю без реального терміналу: `'success'`, `'declined'` або
  /// `'unknown'`. `null` — бойовий режим (реальний `Purchase`). Для перегляду
  /// UI на касі.
  final String? demoOutcome;

  static Future<TerminalTxnResult?> show(
    BuildContext context, {
    required PaymentTerminal terminal,
    required Money amount,
    String? demoOutcome,
  }) {
    return showDialog<TerminalTxnResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CardPaymentDialog(
          terminal: terminal, amount: amount, demoOutcome: demoOutcome),
    );
  }

  @override
  State<CardPaymentDialog> createState() => _CardPaymentDialogState();
}

class _CardPaymentDialogState extends State<CardPaymentDialog> {
  static const _blue = Color(0xFF1E7DC8);
  static const _green = Color(0xFF15803D);
  static const _red = Color(0xFFDC2626);
  static const _amber = Color(0xFFB45309);
  static const _grey = Color(0xFF6B7280);

  _CardStage _stage = _CardStage.connecting;
  String _status = 'Підключення до терміналу…';
  String _log = '';
  EcrTerminalClient? _client;
  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    _client?.close();
    super.dispose();
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() => _log = _log.isEmpty ? line : '$_log\n$line');
  }

  /// Провести оплату: connect → Purchase → результат. Використовується і для
  /// повторної спроби (кнопка «повторити»).
  Future<void> _run() async {
    _autoClose?.cancel();
    await _client?.close();
    if (!mounted) return;

    setState(() {
      _stage = _CardStage.connecting;
      _status = 'Підключення до терміналу…';
      _log = '';
    });

    if (widget.demoOutcome != null) {
      await _runDemo(widget.demoOutcome!);
      return;
    }

    final client = EcrTerminalClient.forTerminal(
      widget.terminal,
      onStatus: (s) {
        if (!mounted) return;
        setState(() => _status = s);
        _appendLog(s);
      },
    );
    if (client == null) {
      _fail('Термінал не підтримується (${widget.terminal.protocol.name})');
      return;
    }
    _client = client;

    final ok = await client.connect();
    if (!mounted) return;
    if (!ok) {
      _fail('Немає зв\'язку з терміналом '
          '${widget.terminal.termIP}:${widget.terminal.termPort}');
      return;
    }

    setState(() {
      _stage = _CardStage.waitingCard;
      _status = 'ОЧІКУЮ КАРТКУ';
    });

    _purchaseSentAt = DateTime.now();
    final res = await client.purchase(widget.amount);
    if (!mounted) return;

    if (res.approved) {
      _succeed(res);
    } else if (res.resultUnknown) {
      _appendLog(_techLine(res));
      await _verifyUnknown();
    } else {
      _appendLog(_techLine(res));
      setState(() {
        _stage = _CardStage.declined;
        _status = _declineTitle(res);
      });
    }
  }

  /// Момент надсилання Purchase — нижня межа часу для звірки чека.
  DateTime _purchaseSentAt = DateTime.now();

  void _succeed(TerminalTxnResult res) {
    setState(() {
      _stage = _CardStage.success;
      _status = 'Оплата успішна';
    });
    _appendLog('Схвалено: RRN ${res.rrn}, код ${res.approvalCode}');
    _autoClose = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) Navigator.of(context).pop(res);
    });
  }

  /// Відповіді на Purchase немає → питаємо термінал про останній чек.
  /// Наш → успіх; чужий/старий → відмова (повтор дозволено); не вдалось
  /// спитати → «невідомо», далі лише руками.
  Future<void> _verifyUnknown() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _stage = _CardStage.verifying;
      _status = 'Перевіряю результат на терміналі…';
    });
    _appendLog('Відповіді немає — звірка останнього чека (GetReceiptInfo)');
    final v = await client.verifyPurchase(widget.amount,
        sentAt: _purchaseSentAt);
    if (!mounted) return;
    if (v.approved) {
      _appendLog('Оплата знайдена в терміналі');
      _succeed(v);
    } else if (v.errorKind == EcrErrorKind.none) {
      _appendLog(v.errorDescription);
      setState(() {
        _stage = _CardStage.declined;
        _status = 'ОПЛАТИ НЕ БУЛО';
      });
    } else {
      _appendLog('Звірка не вдалась: ${v.errorDescription}');
      setState(() {
        _stage = _CardStage.unknown;
        _status = 'РЕЗУЛЬТАТ ОПЛАТИ НЕВІДОМИЙ';
      });
    }
  }

  /// Касир підтверджує, що подивився на термінал/сліп і оплати НЕ було.
  /// Без цього після невідомого результату новий платіж не запускаємо —
  /// інакше клієнт може заплатити двічі.
  Future<bool> _confirmNoPayment() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Перевірте термінал',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Термінал не підтвердив результат оплати на '
          '${(widget.amount.kopiykas / 100).asMoneySymbol}.\n\n'
          'Якщо оплата пройшла, термінал надрукував сліп (або показав '
          '«Схвалено»). Тоді НЕ приймайте гроші повторно — викличте '
          'адміністратора.\n\n'
          'Підтверджуєте, що на терміналі оплати НЕ було?',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Так, оплати не було'),
          ),
        ],
      ),
    );
    FiscalLog.log('Картка: невідомий результат — касир '
        '${ok == true ? "ПІДТВЕРДИВ, що оплати не було" : "повернувся до перевірки"}');
    return ok == true;
  }

  Future<void> _retryAfterUnknown() async {
    if (!await _confirmNoPayment()) return;
    if (mounted) await _run();
  }

  Future<void> _cashAfterUnknown() async {
    if (!await _confirmNoPayment()) return;
    if (mounted) _cancelToCash();
  }

  /// Симуляція станів для прев'ю UI (без терміналу й без грошей).
  Future<void> _runDemo(String outcome) async {
    Future<void> wait(int ms) => Future.delayed(Duration(milliseconds: ms));
    await wait(600);
    if (!mounted) return;
    setState(() {
      _stage = _CardStage.waitingCard;
      _status = 'ОЧІКУЮ КАРТКУ';
    });
    _appendLog('[демо] надіслано суму на термінал');
    await wait(1100);
    if (!mounted) return;
    setState(() {
      _stage = _CardStage.processing;
      _status = 'Виконується підтвердження оплати';
    });
    await wait(1100);
    if (!mounted) return;
    if (outcome == 'success') {
      setState(() {
        _stage = _CardStage.success;
        _status = 'Оплата успішна';
      });
      _appendLog('[демо] Схвалено: RRN 000123456789, код 123456');
      _autoClose = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) Navigator.of(context).pop();
      });
    } else if (outcome == 'unknown') {
      _appendLog('[демо] термінал не відповів за 90 с');
      setState(() {
        _stage = _CardStage.verifying;
        _status = 'Перевіряю результат на терміналі…';
      });
      await wait(900);
      if (!mounted) return;
      _appendLog('[демо] звірка не вдалась: немає звʼязку для звірки');
      setState(() {
        _stage = _CardStage.unknown;
        _status = 'РЕЗУЛЬТАТ ОПЛАТИ НЕВІДОМИЙ';
      });
    } else {
      _appendLog('[демо] RC=1000 · transaction declined (host)');
      setState(() {
        _stage = _CardStage.declined;
        _status = 'ОПЕРАЦІЯ ВІДХИЛЕНА!';
      });
    }
  }

  void _fail(String message) {
    _appendLog(message);
    setState(() {
      _stage = _CardStage.declined;
      _status = message;
    });
  }

  /// Заголовок відмови.
  String _declineTitle(TerminalTxnResult r) {
    if (r.cancelledByUser) return 'ОПЕРАЦІЯ СКАСОВАНА';
    if (r.errorKind == EcrErrorKind.timeout ||
        r.errorKind == EcrErrorKind.unknown) {
      return 'ТЕРМІНАЛ НЕ ВІДПОВІВ';
    }
    if (r.errorKind == EcrErrorKind.socket) return 'НЕМАЄ ЗВʼЯЗКУ';
    return 'ОПЕРАЦІЯ ВІДХИЛЕНА!';
  }

  /// Технічний рядок для нижнього логу.
  String _techLine(TerminalTxnResult r) {
    final parts = <String>[
      if (r.responseCode.isNotEmpty) 'RC=${r.responseCode}',
      if (r.errorDescription.isNotEmpty) r.errorDescription,
    ];
    return parts.isEmpty ? 'Помилка операції' : parts.join(' · ');
  }

  void _cancelToCash() {
    FiscalLog.log('Картка: касир обрав відкат у готівку '
        '(${widget.terminal.termIP}:${widget.terminal.termPort})');
    Navigator.of(context).pop(); // null → викликач переходить на готівку
  }

  @override
  Widget build(BuildContext context) {
    final busy = _stage == _CardStage.connecting ||
        _stage == _CardStage.waitingCard ||
        _stage == _CardStage.processing ||
        _stage == _CardStage.verifying;
    final success = _stage == _CardStage.success;
    final declined = _stage == _CardStage.declined;
    final unknown = _stage == _CardStage.unknown;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Заголовок
              Row(
                children: [
                  const Icon(Icons.credit_card_rounded, color: _blue, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Оплата банк.карткою',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    (widget.amount.kopiykas / 100).asMoneySymbol,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _blue),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.terminal.displayName,
                  style: const TextStyle(fontSize: 11.5, color: _grey),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 20),

              // Центральний індикатор + статус
              _buildCenter(
                  busy: busy,
                  success: success,
                  declined: declined,
                  unknown: unknown),
              const SizedBox(height: 18),

              // Технічний лог
              if (_log.isNotEmpty)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 96),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: success
                        ? const Color(0xFFEFFDF3)
                        : const Color(0xFFF4F5F8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: success
                            ? const Color(0xFFBBF7D0)
                            : const Color(0xFFE5E7EB)),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Text(_log,
                        style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: success ? _green : _grey,
                            fontFeatures: const [])),
                  ),
                ),

              // Кнопки — лише при відмові
              if (declined) ...[
                const SizedBox(height: 16),
                _button(
                  label: 'Повторити спробу оплати карткою',
                  color: _green,
                  icon: Icons.refresh_rounded,
                  onTap: _run,
                ),
                const SizedBox(height: 8),
                _button(
                  label: 'Відміна БГ / оплата готівкою',
                  color: _red,
                  icon: Icons.money_rounded,
                  filled: false,
                  onTap: _cancelToCash,
                ),
              ],

              // Невідомий результат — новий платіж лише після підтвердження,
              // що касир перевірив термінал.
              if (unknown) ...[
                const SizedBox(height: 16),
                _button(
                  label: 'Перевірити результат ще раз',
                  color: _blue,
                  icon: Icons.sync_rounded,
                  onTap: _verifyUnknown,
                ),
                const SizedBox(height: 8),
                _button(
                  label: 'Оплати не було — повторити карткою',
                  color: _green,
                  icon: Icons.refresh_rounded,
                  filled: false,
                  onTap: _retryAfterUnknown,
                ),
                const SizedBox(height: 8),
                _button(
                  label: 'Оплати не було — оплата готівкою',
                  color: _red,
                  icon: Icons.money_rounded,
                  filled: false,
                  onTap: _cashAfterUnknown,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenter(
      {required bool busy,
      required bool success,
      required bool declined,
      required bool unknown}) {
    final Widget indicator;
    if (busy) {
      indicator = const SizedBox(
        width: 46,
        height: 46,
        child: CircularProgressIndicator(strokeWidth: 3, color: _blue),
      );
    } else if (success) {
      indicator = Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 30),
      );
    } else if (unknown) {
      indicator = Container(
        width: 52,
        height: 52,
        decoration:
            const BoxDecoration(color: _amber, shape: BoxShape.circle),
        child: const Icon(Icons.question_mark_rounded,
            color: Colors.white, size: 30),
      );
    } else {
      // declined
      indicator = Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
      );
    }

    return Column(
      children: [
        indicator,
        const SizedBox(height: 14),
        Text(
          _status,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: success
                ? _green
                : declined
                    ? _red
                    : unknown
                        ? _amber
                        : const Color(0xFF1C1C2E),
          ),
        ),
        if (busy) ...[
          const SizedBox(height: 6),
          const Text(
            'Дочекайтесь завершення операції на терміналі',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: _grey),
          ),
        ],
        if (unknown) ...[
          const SizedBox(height: 6),
          const Text(
            'Термінал не підтвердив і не відхилив оплату. Подивіться на '
            'термінал: чи є сліп або «Схвалено». Гроші могли списатись.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: _grey, height: 1.35),
          ),
        ],
      ],
    );
  }

  Widget _button({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
    bool filled = true,
  }) {
    return SizedBox(
      height: 40,
      child: filled
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(backgroundColor: color),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18, color: color),
              label: Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: color)),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: color.withValues(alpha: 0.5))),
            ),
    );
  }
}
