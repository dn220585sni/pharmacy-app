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

  group('GetTermBank з termIP/termPort (розширення Каті, 2026-07-21)', () {
    final terminals = PaymentTerminal.listFromResponse(
        jsonDecode(_sampleWithDevices) as Map<String, dynamic>);

    test('фізичні термінали з однаковим kodterm НЕ зливаються', () {
      // КАСА 1 і КАСА 3 — обидві PRIVAT kodterm=1103, але різні IP:
      // резервний пристрій не має губитись при дедуплікації.
      final ips = terminals
          .where((t) => t.kodterm == '1103' && t.canConnect)
          .map((t) => t.termIP)
          .toSet();
      expect(ips, {'10.10.123.72', '10.10.123.71'});
    });

    test('голий запис відкидається, якщо є фізичний із тим же kodterm', () {
      expect(terminals.where((t) => t.kodterm == '1103' && !t.canConnect),
          isEmpty);
      expect(
          terminals.where((t) => t.kodterm == '963' && !t.canConnect), isEmpty);
    });

    test('способи оплати без адреси лишаються', () {
      final bare = terminals.where((t) => !t.canConnect).map((t) => t.bankCode);
      expect(bare,
          containsAll(['BINANCE', 'LIQPAY', 'MONOPART', 'PRIVATQR', 'PUMB']));
    });

    test('основний — першим, з адресою', () {
      expect(terminals.first.isMain, isTrue);
      expect(terminals.first.termIP, '10.10.123.72');
      expect(terminals.first.portNumber, 2000);
    });

    test('протокол за банком: Privat=JSON, Oschad=BPOS', () {
      final privat = terminals.firstWhere((t) => t.termIP == '10.10.123.72');
      final oschad = terminals.firstWhere((t) => t.termIP == '10.10.123.75');
      expect(privat.protocol, TerminalProtocol.json);
      expect(oschad.protocol, TerminalProtocol.bpos);
      // JSON підтримано зараз; BPOS — окрема пізніша фаза.
      expect(privat.isSupported, isTrue);
      expect(oschad.isSupported, isFalse);
      expect(oschad.portNumber, 2100);
    });

    test('connectable() — лише пристрої з адресою', () {
      final ecr = PaymentTerminal.connectable(terminals);
      expect(ecr.length, 3); // КАСА 1, КАСА 2, КАСА 3
      expect(ecr.every((t) => t.canConnect), isTrue);
    });
  });
}

// Реальна відповідь GetTermBank ПІСЛЯ розширення (Катя, 2026-07-21):
// додано termIP / termPort / termLang.
const _sampleWithDevices = '''
{"Status":"OK","Terminals":[
 {"name2":"PRIVAT","name":"КАССА 1, Шевченко б-р, 71 (Копейка)","teg":"PrivatBank","kodterm":"1103","main":"1","termIP":"10.10.123.72","termPort":"2000","termLang":"1"},
 {"name2":"OSHAD","name":"КАССА 2, Шевченко б-р, 71 (Копейка)","teg":"Oschad","kodterm":"963","main":"0","termIP":"10.10.123.75","termPort":"2100","termLang":"1"},
 {"name2":"PRIVAT","name":"КАССА 3, Шевченко б-р, 71 (Копейка)","teg":"PrivatBank","kodterm":"1103","main":"0","termIP":"10.10.123.71","termPort":"2000","termLang":"1"},
 {"name2":"BINANCE","name":"","teg":"","kodterm":"1542","main":"0","termIP":"","termPort":"","termLang":""},
 {"name2":"LIQPAY","name":"","teg":"","kodterm":"1476","main":"0","termIP":"","termPort":"","termLang":""},
 {"name2":"MONOPART","name":"","teg":"","kodterm":"1665","main":"0","termIP":"","termPort":"","termLang":""},
 {"name2":"OSHAD","name":"","teg":"","kodterm":"963","main":"0","termIP":"","termPort":"","termLang":""},
 {"name2":"PRIVAT","name":"","teg":"","kodterm":"1103","main":"0","termIP":"","termPort":"","termLang":""},
 {"name2":"PRIVATQR","name":"","teg":"","kodterm":"1550","main":"0","termIP":"","termPort":"","termLang":""},
 {"name2":"PUMB","name":"","teg":"","kodterm":"330","main":"0","termIP":"","termPort":"","termLang":""}
]}
''';
