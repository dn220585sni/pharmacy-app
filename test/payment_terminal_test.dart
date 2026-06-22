import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/payment_terminal.dart';

// Реальна відповідь GetTermBank (без ekkKodKli), 2026-06-19 — kodterm заповнені,
// є дублі за kodterm (1103, 963) і «голі» записи (лише name2 + kodterm).
const _sample = '''
{"Status":"OK","Terminals":[
  {"name2":"PRIVAT","name":"КАССА 1, Шевченко 71","teg":"PrivatBank","kodterm":"1103","main":"1"},
  {"name2":"OSHAD","name":"КАССА 2, Шевченко 71","teg":"Oschad","kodterm":"963","main":"0"},
  {"name2":"PRIVAT","name":"КАССА 3, Шевченко 71","teg":"PrivatBank","kodterm":"1103","main":"0"},
  {"name2":"MONOPART","name":"","teg":"","kodterm":"1665","main":"0"},
  {"name2":"OSHAD","name":"","teg":"","kodterm":"963","main":"0"},
  {"name2":"PRIVAT","name":"","teg":"","kodterm":"1103","main":"0"},
  {"name2":"PRIVATQR","name":"","teg":"","kodterm":"1550","main":"0"},
  {"name2":"PUMB","name":"","teg":"","kodterm":"330","main":"0"}
]}
''';

void main() {
  group('PaymentTerminal.listFromResponse — дедуплікація за kodterm', () {
    final terminals = PaymentTerminal.listFromResponse(
        jsonDecode(_sample) as Map<String, dynamic>);

    test('8 записів → 5 унікальних терміналів', () {
      expect(terminals.length, 5);
      final kods = terminals.map((t) => t.kodterm).toSet();
      expect(kods, {'1103', '963', '1665', '1550', '330'});
    });

    test('основний (1103, КАССА 1) — першим', () {
      expect(terminals.first.isMain, isTrue);
      expect(terminals.first.kodterm, '1103');
      expect(terminals.first.displayName, 'КАССА 1, Шевченко 71');
    });

    test('при дублі лишається запис з описом', () {
      final t963 = terminals.firstWhere((t) => t.kodterm == '963');
      expect(t963.displayName, 'КАССА 2, Шевченко 71');
    });

    test('«голі» записи → displayName «тип · №код»', () {
      final mono = terminals.firstWhere((t) => t.kodterm == '1665');
      expect(mono.displayName, 'MONOPART · №1665');
    });

    test('некоректна відповідь → порожньо', () {
      expect(PaymentTerminal.listFromResponse(null), isEmpty);
      expect(PaymentTerminal.listFromResponse({'Status': 'BAD'}), isEmpty);
    });
  });
}
