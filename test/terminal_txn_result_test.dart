import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/money.dart';
import 'package:pharmacy_app/models/terminal_txn_result.dart';

void main() {
  group('TerminalTxnResult.fromResponse', () {
    // Приклад успішної Purchase-відповіді (з docs/ecr.txt, 5.1.2).
    const okJson = '''
{"method":"Purchase","step":0,"params":{
  "amount":"0.60","approvalCode":"999999","cardExpiryDate":"2020",
  "cardHolderName":"INSTANT/ISSUE","date":"02.10.2019","discount":"0.00",
  "invoiceNumber":"999999","issuerName":"VISA","merchant":"TSTTTTTT",
  "pan":"4731XXXXXXXX9838","paymentSystem":"VISA","responseCode":"0000",
  "rrn":"9999999999999","rrnExt":"8888888888888","terminalId":"TSTSALE2",
  "time":"09:11:07","txnType":"1","trnStatus":"1"},
  "error":false,"errorDescription":""}''';

    test('успішна оплата → approved, поля розібрані', () {
      final r = TerminalTxnResult.fromResponse(
          jsonDecode(okJson) as Map<String, dynamic>);
      expect(r.approved, isTrue);
      expect(r.responseCode, '0000');
      expect(r.approvalCode, '999999');
      expect(r.rrn, '9999999999999');
      expect(r.rrnExt, '8888888888888');
      expect(r.pan, '4731XXXXXXXX9838');
      expect(r.terminalId, 'TSTSALE2');
      expect(r.merchant, 'TSTTTTTT');
      // Похідні для pay_terminal.
      expect(r.authCode, '999999');
      expect(r.epz, '4731XXXXXXXX9838');
      expect(r.cardType, 'VISA');
    });

    test('dateTimeCompact → yymmddhhmmss', () {
      final r = TerminalTxnResult.fromResponse(
          jsonDecode(okJson) as Map<String, dynamic>);
      // 02.10.2019 09:11:07 → 191002091107
      expect(r.dateTimeCompact, '191002091107');
    });

    test('pay_terminal мапінг', () {
      final r = TerminalTxnResult.fromResponse(
          jsonDecode(okJson) as Map<String, dynamic>);
      final pt = r.toPayTerminal();
      expect(pt['auth_code'], '999999');
      expect(pt['rrn'], '9999999999999');
      expect(pt['epz'], '4731XXXXXXXX9838');
      expect(pt['terminal_id'], 'TSTSALE2');
      expect(pt['card_type'], 'VISA');
      expect(pt['name'], 'TSTTTTTT');
    });

    test('PutTermData: ssum/sumCash — вхідні, trnBatchNum=0', () {
      final r = TerminalTxnResult.fromResponse(
          jsonDecode(okJson) as Map<String, dynamic>);
      final d = r.toPutTermData(
        ssum: Money.fromHryvnia(0.60),
        sumCash: Money.zero,
      );
      expect(d['ssum'], '0.60');
      expect(d['sumCash'], '0.00');
      expect(d['authCode'], '999999');
      expect(d['trnBatchNum'], '0');
      expect(d['rnk'], ''); // у JSON немає
    });

    test('скасовано користувачем (1001) → не approved', () {
      const cancelled =
          '{"method":"Purchase","step":0,"params":{"responseCode":"1001"},'
          '"error":true,"errorDescription":"Скасовано"}';
      final r = TerminalTxnResult.fromResponse(
          jsonDecode(cancelled) as Map<String, dynamic>);
      expect(r.approved, isFalse);
      expect(r.cancelledByUser, isTrue);
      expect(r.terminalError, isTrue);
    });

    test('локальна помилка (timeout) → не approved', () {
      final r =
          TerminalTxnResult.localError(EcrErrorKind.timeout, 'немає відповіді');
      expect(r.approved, isFalse);
      expect(r.errorKind, EcrErrorKind.timeout);
    });
  });
}
