import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/crm_params_service.dart';
import 'package:pharmacy_app/services/loyalty_service.dart';

/// Реєстрація клієнта з каси: гілки за кодом помилки checkCard і параметри CRM.
void main() {
  group('LoyaltyCheckResult', () {
    test('UNKNOWN_CARD → реєстрація, не офлайн', () {
      final r = LoyaltyCheckResult(
          success: false, errorCode: 'UNKNOWN_CARD', errorMsg: 'Невідома карта');
      expect(r.isUnknownCard, isTrue);
      expect(r.isOffline, isFalse);
    });

    test('NETWORK_ERROR / HTTP_5xx → офлайн, не реєстрація', () {
      for (final code in ['NETWORK_ERROR', 'HTTP_502', 'HTTP_504']) {
        final r = LoyaltyCheckResult(success: false, errorCode: code);
        expect(r.isOffline, isTrue, reason: code);
        expect(r.isUnknownCard, isFalse, reason: code);
      }
    });

    test('інша помилка Спарти → ні те, ні інше (просто снекбар)', () {
      final r = LoyaltyCheckResult(success: false, errorCode: 'CARD_BLOCKED');
      expect(r.isOffline, isFalse);
      expect(r.isUnknownCard, isFalse);
    });

    test('успіх без коду', () {
      final r = LoyaltyCheckResult(success: true);
      expect(r.isOffline, isFalse);
      expect(r.isUnknownCard, isFalse);
    });
  });

  group('CrmParams', () {
    test('розбір відповіді GetParamPr TypePr=CRM', () {
      final p = CrmParams.fromJson({
        'Status': 'OK',
        'login': 'APT748',
        'pass': 'secret',
        'idT': '41',
      });
      expect(p.login, 'APT748');
      expect(p.pass, 'secret');
      expect(p.idT, '41');
      expect(p.isUsable, isTrue);
      // Пароль ніколи не потрапляє в лог.
      expect(p.toString(), isNot(contains('secret')));
    });

    test('без логіна/пароля — непридатні', () {
      expect(CrmParams.fromJson({'Status': 'OK'}).isUsable, isFalse);
      expect(CrmParams.fromJson({'login': 'APT1'}).isUsable, isFalse);
    });
  });
}
