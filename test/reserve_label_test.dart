import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/utils/reserve_label.dart';

void main() {
  test('прізвище: щонайменше 3 літери, пробіли й знаки не рахуються', () {
    expect(isValidReserveSurname('Жук'), isTrue);
    expect(isValidReserveSurname("Д'яч"), isTrue); // 3 літери + апостроф
    expect(isValidReserveSurname("Ґ'ї"), isFalse); // апостроф — не літера
    expect(isValidReserveSurname('Ли'), isFalse);
    expect(isValidReserveSurname(' Л - и '), isFalse);
    expect(isValidReserveSurname('123'), isFalse);
    expect(isValidReserveSurname('Іваненко'), isTrue);
  });

  test('телефон → 0XXXXXXXXX з різних записів', () {
    expect(normalizeReservePhone('097 828 88 88'), '0978288888');
    expect(normalizeReservePhone('+380978288888'), '0978288888');
    expect(normalizeReservePhone('380978288888'), '0978288888');
    expect(normalizeReservePhone('978288888'), '0978288888');
    expect(normalizeReservePhone('09782888'), isNull);
    expect(normalizeReservePhone(''), isNull);
  });

  test('підпис як у старих резервах: «ЖУК 0978288888»', () {
    expect(buildReserveLabel(' жук ', '0978288888'), 'ЖУК 0978288888');
    expect(buildReserveLabel('Нечуй  Левицький', '0501112233'),
        'НЕЧУЙ ЛЕВИЦЬКИЙ 0501112233');
  });
}
