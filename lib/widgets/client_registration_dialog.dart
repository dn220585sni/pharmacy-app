import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/fiscal_log.dart';
import '../services/loyalty_service.dart';
import '../services/phone_verify_service.dart';

/// Реєстрація нового клієнта Лайк з каси (Андрій, 2026-09-14/15).
///
/// Викликається, коли `checkCard` повернув `UNKNOWN_CARD`. Кроки:
/// 1. дзвінок клієнту → клієнт називає останні 4 цифри номера, з якого
///    подзвонили (`channel`); звіряємо локально;
/// 2. якщо дзвінок не вдався — SMS → клієнт називає код (`code`);
/// 3. `customer/create` → віртуальна картка.
/// Повертає номер картки або null (скасовано / не вдалося).
Future<String?> showClientRegistrationDialog({
  required BuildContext context,
  required String phone,
  required String pharmacistIpn,
  String? cashierName,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ClientRegistrationDialog(
      phone: phone,
      pharmacistIpn: pharmacistIpn,
      cashierName: cashierName,
    ),
  );
}

enum _Step { intro, calling, callCode, smsSending, smsCode, creating, failed }

class _ClientRegistrationDialog extends StatefulWidget {
  final String phone;
  final String pharmacistIpn;
  final String? cashierName;

  const _ClientRegistrationDialog({
    required this.phone,
    required this.pharmacistIpn,
    this.cashierName,
  });

  @override
  State<_ClientRegistrationDialog> createState() =>
      _ClientRegistrationDialogState();
}

class _ClientRegistrationDialogState extends State<_ClientRegistrationDialog> {
  static const _maxAttempts = 3;
  static const _blue = Color(0xFF1E7DC8);
  static const _ink = Color(0xFF1C1C2E);
  static const _grey = Color(0xFF6B7280);
  static const _amber = Color(0xFFB45309);

  _Step _step = _Step.intro;
  String _secret = '';
  String? _error;
  String? _failedMsg;
  bool _callFailed = false;
  int _attempts = 0;
  final _code = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _prettyPhone {
    final d = widget.phone.replaceAll(RegExp(r'\D'), '');
    if (d.length != 12) return widget.phone;
    return '+${d.substring(0, 3)} ${d.substring(3, 5)} ${d.substring(5, 8)} '
        '${d.substring(8, 10)} ${d.substring(10)}';
  }

  // ── дії ─────────────────────────────────────────────────────────────────

  Future<void> _startCall() async {
    setState(() {
      _step = _Step.calling;
      _error = null;
    });
    final r = await PhoneVerifyService.call(
        phone: widget.phone, pharmacistIpn: widget.pharmacistIpn);
    if (!mounted) return;
    if (r.ok) {
      _secret = r.secret;
      _attempts = 0;
      _code.clear();
      setState(() => _step = _Step.callCode);
      _focus.requestFocus();
    } else {
      _callFailed = true;
      setState(() {
        _failedMsg = r.error;
        _step = _Step.failed;
      });
    }
  }

  Future<void> _startSms() async {
    setState(() {
      _step = _Step.smsSending;
      _error = null;
    });
    final r = await PhoneVerifyService.sms(
        phone: widget.phone, pharmacistIpn: widget.pharmacistIpn);
    if (!mounted) return;
    if (r.ok) {
      _secret = r.secret;
      _attempts = 0;
      _code.clear();
      setState(() => _step = _Step.smsCode);
      _focus.requestFocus();
    } else {
      setState(() {
        _failedMsg = r.error;
        _step = _Step.failed;
      });
    }
  }

  void _verify() {
    final typed = _code.text.trim();
    if (typed.isEmpty) return;
    if (typed == _secret) {
      FiscalLog.log('РЕЄСТРАЦІЯ ${widget.phone}: телефон підтверджено '
          '(${_step == _Step.callCode ? "дзвінок" : "SMS"})');
      _create();
      return;
    }
    _attempts++;
    FiscalLog.log('РЕЄСТРАЦІЯ ${widget.phone}: код не збігся '
        '(спроба $_attempts з $_maxAttempts)');
    setState(() {
      _error = _attempts >= _maxAttempts
          ? 'Код не збігся $_maxAttempts рази'
          : 'Не збігається, спробуйте ще раз';
    });
    _code.clear();
    _focus.requestFocus();
  }

  Future<void> _create() async {
    setState(() => _step = _Step.creating);
    final r = await LoyaltyService.createCustomer(widget.phone,
        cashierName: widget.cashierName);
    if (!mounted) return;
    if (r.success) {
      FiscalLog.log('РЕЄСТРАЦІЯ ${widget.phone}: анкету створено, '
          'картка ${r.cardNo}');
      Navigator.of(context).pop(r.cardNo);
      return;
    }
    FiscalLog.log('РЕЄСТРАЦІЯ ${widget.phone}: customer/create '
        '${r.errorCode ?? ""} ${r.errorMsg ?? ""}');
    setState(() {
      _failedMsg = 'Спарта не створила анкету: ${r.errorMsg ?? "помилка"}';
      _step = _Step.failed;
    });
  }

  void _cancel() {
    FiscalLog.log('РЕЄСТРАЦІЯ ${widget.phone}: скасовано на кроці $_step');
    Navigator.of(context).pop(null);
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _icon(),
              const SizedBox(height: 16),
              Text(_title(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
              const SizedBox(height: 8),
              Text(_subtitle(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: _grey, height: 1.5)),
              const SizedBox(height: 20),
              ..._body(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _icon() {
    final busy = _step == _Step.calling ||
        _step == _Step.smsSending ||
        _step == _Step.creating;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: _step == _Step.failed
            ? const Color(0xFFFEF3C7)
            : const Color(0xFFE8F3FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(strokeWidth: 2.5, color: _blue))
          : Icon(
              switch (_step) {
                _Step.intro => Icons.person_add_alt_1_rounded,
                _Step.callCode => Icons.phone_in_talk_rounded,
                _Step.smsCode => Icons.sms_rounded,
                _Step.failed => Icons.error_outline_rounded,
                _ => Icons.person_add_alt_1_rounded,
              },
              size: 26,
              color: _step == _Step.failed ? _amber : _blue),
    );
  }

  String _title() => switch (_step) {
        _Step.intro => 'Клієнта немає в Лайк',
        _Step.calling => 'Телефонуємо клієнту…',
        _Step.callCode => 'Клієнту дзвонять',
        _Step.smsSending => 'Надсилаємо SMS…',
        _Step.smsCode => 'Клієнту надіслано SMS',
        _Step.creating => 'Створюємо анкету…',
        _Step.failed => 'Не вдалося',
      };

  String _subtitle() => switch (_step) {
        _Step.intro => 'Номер $_prettyPhone не зареєстровано. Щоб створити '
            'анкету, підтвердимо номер дзвінком: клієнт назве останні 4 '
            'цифри номера, з якого йому подзвонили.',
        _Step.calling => 'Зачекайте кілька секунд.',
        _Step.callCode => 'Попросіть клієнта назвати останні 4 цифри номера, '
            'з якого надійшов дзвінок, і введіть їх.',
        _Step.smsSending => 'Зачекайте кілька секунд.',
        _Step.smsCode => 'Попросіть клієнта продиктувати код із SMS '
            'і введіть його.',
        _Step.creating => 'Реєструємо клієнта в Лайк.',
        _Step.failed => _failedMsg ?? 'Помилка',
      };

  List<Widget> _body() {
    switch (_step) {
      case _Step.intro:
        return [
          _buttons(secondary: ('Скасувати', _cancel), primary: ('Подзвонити', _startCall)),
        ];
      case _Step.calling:
      case _Step.smsSending:
      case _Step.creating:
        return [
          _buttons(secondary: ('Скасувати', _cancel), primary: null),
        ];
      case _Step.callCode:
      case _Step.smsCode:
        final isCall = _step == _Step.callCode;
        final exhausted = _attempts >= _maxAttempts;
        return [
          TextField(
            controller: _code,
            focusNode: _focus,
            autofocus: true,
            enabled: !exhausted,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(isCall ? 4 : 8),
            ],
            textAlign: TextAlign.center,
            onSubmitted: (_) => _verify(),
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 6),
            decoration: InputDecoration(
              hintText: isCall ? '• • • •' : 'код',
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
              errorText: _error,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _blue, width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),
          if (isCall)
            TextButton(
              onPressed: _startSms,
              child: const Text('Дзвінка немає — надіслати SMS',
                  style: TextStyle(color: _blue, fontWeight: FontWeight.w600)),
            )
          else
            TextButton(
              onPressed: _startSms,
              child: const Text('Надіслати SMS ще раз',
                  style: TextStyle(color: _blue, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          _buttons(
            secondary: ('Скасувати', _cancel),
            primary: exhausted ? null : ('Підтвердити', _verify),
          ),
        ];
      case _Step.failed:
        // Після невдалого дзвінка — SMS; після невдалого SMS/створення —
        // повторити той самий крок.
        final (String, VoidCallback) retry = _callFailed && _secret.isEmpty
            ? ('Надіслати SMS', _startSms)
            : ('Спробувати ще раз', _secret.isEmpty ? _startSms : _create);
        return [
          _buttons(secondary: ('Скасувати', _cancel), primary: retry),
        ];
    }
  }

  Widget _buttons({
    required (String, VoidCallback) secondary,
    required (String, VoidCallback)? primary,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: secondary.$2,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            child: Text(secondary.$1,
                style: const TextStyle(
                    color: _grey, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ),
        if (primary != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: primary.$2,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(primary.$1,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ],
      ],
    );
  }
}
