import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/auth_service.dart';

void main() {
  group('flagZA → isManager', () {
    PharmacistInfo parse(Object? flag) => AuthService.userFromJson({
          'user': 'Іванова І.І.',
          'ipn': '1234567890',
          'flagZA': flag,
        });

    test('«1» — завідувач', () {
      expect(parse('1').isManager, isTrue);
      expect(parse(1).isManager, isTrue);
    });

    test('true і yes теж приймаємо — форма прапорців у нас плаває', () {
      expect(parse(true).isManager, isTrue);
      expect(parse('true').isManager, isTrue);
      expect(parse('YES').isManager, isTrue);
    });

    test('«0», порожньо, відсутнє — не завідувач', () {
      expect(parse('0').isManager, isFalse);
      expect(parse('').isManager, isFalse);
      expect(parse('   ').isManager, isFalse);
      expect(parse(null).isManager, isFalse);
    });

    test('несподіване значення трактуємо як «ні», а не як «так»', () {
      // Права безпечніше недодати, ніж додати помилково: зайвий резерв
      // доведеться розбирати, а відмову — лише перелогінитись.
      expect(parse('можливо').isManager, isFalse);
      expect(parse('2').isManager, isFalse);
    });

    test('flagZA не плутається з typezuser', () {
      final u = AuthService.userFromJson({
        'user': 'Петрова П.П.',
        'ipn': '1',
        'typezuser': '1',
      });
      expect(u.isSpecial, isTrue);
      expect(u.isManager, isFalse);
    });
  });
}
