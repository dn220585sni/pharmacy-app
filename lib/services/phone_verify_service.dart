import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'crm_params_service.dart';
import 'fiscal_log.dart';

/// Підтвердження, що телефон у руках клієнта (сервіс ANC `node.anctm.biz:3100`).
///
/// Джерело: лист Андрія 2026-09-14/15 + apidoc сервісу. Два канали:
/// - **дзвінок** `GET /api/originate/{380…}/{ІПН провізора}/{pin}` →
///   `{"pin":"…","channel":"0157"}` — клієнту телефонують, `channel` = останні
///   4 цифри номера, з якого прийшов дзвінок; клієнт називає їх фармацевту;
/// - **SMS** `GET /api/sms/{380…}/{ІПН}/{pin}` → `{"pin":"…","code":"4423"}` —
///   `code` = код із SMS (НЕ pin з URL).
/// Авторизація Basic `login:pass` з `GetParamPr&TypePr=CRM` (per-аптека).
/// `pin` — наш унікальний 4-значний код, щоб зіставити відповідь із запитом
/// (сервер його повертає); генеруємо на кожен запит.
///
/// Той самий механізм планується для верифікації списання бонусів від
/// `VerifySPLSum` — тому сервіс не знає нічого про реєстрацію.
class PhoneVerifyResult {
  final bool ok;

  /// Що має назвати/ввести клієнт: 4 цифри номера (дзвінок) або код (SMS).
  final String secret;
  final String? error;

  const PhoneVerifyResult.ok(this.secret)
      : ok = true,
        error = null;
  const PhoneVerifyResult.fail(this.error)
      : ok = false,
        secret = '';
}

class PhoneVerifyService {
  static const baseUrl = 'http://node.anctm.biz:3100';
  static const timeout = Duration(seconds: 20);
  static final _client = http.Client();
  static final _rnd = Random();

  static String _pin() => (1000 + _rnd.nextInt(9000)).toString();

  /// Лише цифри з міжнародним кодом без «+»: `+380676178803` → `380676178803`.
  static String _tel(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  /// Подзвонити клієнту. У результаті — останні 4 цифри номера-відправника.
  static Future<PhoneVerifyResult> call({
    required String phone,
    required String pharmacistIpn,
  }) =>
      _request('originate', phone: phone, ipn: pharmacistIpn, field: 'channel');

  /// Надіслати SMS. У результаті — код із повідомлення.
  static Future<PhoneVerifyResult> sms({
    required String phone,
    required String pharmacistIpn,
  }) =>
      _request('sms', phone: phone, ipn: pharmacistIpn, field: 'code');

  static Future<PhoneVerifyResult> _request(
    String kind, {
    required String phone,
    required String ipn,
    required String field,
  }) async {
    final tel = _tel(phone);
    final pin = _pin();
    if (ApiConfig.useMock) {
      // Мок: дзвінок «з номера …0157», SMS з кодом 4423 (як у прикладі Андрія).
      await Future.delayed(const Duration(milliseconds: 600));
      return PhoneVerifyResult.ok(kind == 'sms' ? '4423' : '0157');
    }
    final crm = await CrmParamsService.fetch();
    if (crm == null) {
      FiscalLog.log('ВЕРИФІКАЦІЯ $kind $tel: немає логіна/пароля CRM (GetParamPr)');
      return const PhoneVerifyResult.fail(
          'Немає доступу до сервісу підтвердження (параметри CRM)');
    }
    // ІПН — ідентифікатор того, хто надіслав запит; без нього шлемо логін.
    final user = ipn.isNotEmpty ? ipn : crm.login;
    final uri = Uri.parse('$baseUrl/api/$kind/$tel/'
        '${Uri.encodeComponent(user)}/$pin');
    final auth = 'Basic ${base64Encode(utf8.encode('${crm.login}:${crm.pass}'))}';
    try {
      final resp = await _client
          .get(uri, headers: {'Authorization': auth})
          .timeout(timeout);
      final body = utf8.decode(resp.bodyBytes);
      if (resp.statusCode != 200) {
        FiscalLog.log('ВЕРИФІКАЦІЯ $kind $tel: HTTP ${resp.statusCode} '
            '${body.trim().split('\n').first}');
        return PhoneVerifyResult.fail(switch (resp.statusCode) {
          403 => 'Сервіс підтвердження відхилив авторизацію аптеки',
          401 => 'Помилка підсистеми авторизації сервісу підтвердження',
          500 => kind == 'sms'
              ? 'Не вдалося надіслати SMS'
              : 'Не вдалося здійснити дзвінок',
          _ => 'Сервіс підтвердження: HTTP ${resp.statusCode}',
        });
      }
      final j = jsonDecode(body) as Map<String, dynamic>;
      final echoedPin = j['pin']?.toString() ?? '';
      final secret = j[field]?.toString() ?? '';
      if (echoedPin.isNotEmpty && echoedPin != pin) {
        FiscalLog.log('ВЕРИФІКАЦІЯ $kind $tel: pin у відповіді $echoedPin ≠ наш $pin');
        return const PhoneVerifyResult.fail(
            'Відповідь сервісу не відповідає запиту (pin)');
      }
      if (secret.isEmpty) {
        FiscalLog.log('ВЕРИФІКАЦІЯ $kind $tel: порожнє поле $field у відповіді $body');
        return const PhoneVerifyResult.fail('Сервіс не повернув код підтвердження');
      }
      // Сам код у лог не пишемо — лише факт.
      FiscalLog.log('ВЕРИФІКАЦІЯ $kind $tel: OK (pin $pin)');
      return PhoneVerifyResult.ok(secret);
    } catch (e) {
      debugPrint('PhoneVerifyService $kind ERROR: $e');
      FiscalLog.log('ВЕРИФІКАЦІЯ $kind $tel: помилка звʼязку $e');
      return const PhoneVerifyResult.fail(
          'Сервіс підтвердження недоступний (звʼязок)');
    }
  }
}
