import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/payment_terminal.dart';

// Реальна відповідь GetTermBank (ekkKodKli=1334), 2026-06-17.
const _sample = '''
{"Status":"OK","Terminals":[
  {"name2":"PRIVAT","name":"КАССА 1, Шевченко б-р, 71","teg":"PrivatBank","kodterm":"1103","main":"0"},
  {"name2":"OSHAD","name":"КАССА 2, Шевченко б-р, 71","teg":"Oschad","kodterm":"963","main":"1"},
  {"name2":"PRIVAT","name":"КАССА 3, Шевченко б-р, 71","teg":"PrivatBank","kodterm":"1103","main":"0"},
  {"name2":"","name":"","teg":"","kodterm":"","main":"0"},
  {"name2":"MONOPART","name":"","teg":"","kodterm":"","main":"0"},
  {"name2":"PUMB","name":"","teg":"","kodterm":"","main":"0"}
]}
''';

void main() {
  group('PaymentTerminal.listFromResponse', () {
    final data = jsonDecode(_sample) as Map<String, dynamic>;
    final terminals = PaymentTerminal.listFromResponse(data);

    test('фільтрує порожні слоти (лише з kodterm)', () {
      expect(terminals.length, 3); // 6 записів → 3 налаштовані
      expect(terminals.every((t) => t.kodterm.isNotEmpty), isTrue);
    });

    test('основний (main=1) — першим', () {
      expect(terminals.first.isMain, isTrue);
      expect(terminals.first.kodterm, '963');
      expect(terminals.first.bank, 'Oschad');
    });

    test('рівно один основний', () {
      expect(terminals.where((t) => t.isMain).length, 1);
    });

    test('поля розпарсені', () {
      final main = terminals.first;
      expect(main.name, 'КАССА 2, Шевченко б-р, 71');
      expect(main.bankCode, 'OSHAD');
      expect(main.displayName, 'КАССА 2, Шевченко б-р, 71');
    });

    test('некоректна відповідь → порожній список', () {
      expect(PaymentTerminal.listFromResponse(null), isEmpty);
      expect(PaymentTerminal.listFromResponse({'Status': 'BAD'}), isEmpty);
    });
  });
}
