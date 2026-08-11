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
  "time":"09:11:07","txnType":"1","trnStatus":"1","signVerif":"0"},
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

    test('ParamsPayCard: 21 поле через таб, у точному порядку', () {
      final r = TerminalTxnResult.fromResponse(
          jsonDecode(okJson) as Map<String, dynamic>);
      final params = r.buildParamsPayCard(
        ssum: Money.fromHryvnia(0.60),
        sumCash: Money.zero,
        codeKsTerm: '1103',
      );
      final f = params.split('\t');
      expect(f.length, 21);
      expect(f[0], 'TSTSALE2'); // 1 TerminalID
      expect(f[1], 'TSTTTTTT'); // 2 MerchantID
      expect(f[2], '999999'); // 3 InvoiceNum
      expect(f[3], '0.60'); // 4 Amount транзакції
      expect(f[4], 'VISA'); // 5 IssuerName
      expect(f[5], '4731XXXXXXXX9838'); // 6 pan
      expect(f[6], 'INSTANT/ISSUE'); // 7 CardHolder
      expect(f[7], '999999'); // 8 AuthCode
      expect(f[8], '9999999999999'); // 9 rrn
      expect(f[9], '02/10/2019'); // 10 dt dd/mm/yyyy
      expect(f[10], '09:11:07'); // 11 tm
      expect(f[11], '0'); // 12 SignVerif
      expect(f[12], '1'); // 13 TxnType (Purchase)
      expect(f[13], '0.60'); // 14 ssum сума чека
      expect(f[14], '0.00'); // 15 sumCash
      expect(f[15], ''); // 16 DiscountName (JSON порожньо)
      expect(f[16], ''); // 17 RNK
      expect(f[17], '8888888888888'); // 18 RRNExt
      expect(f[18], '0'); // 19 TrnBatchNum (JSON=0)
      expect(f[19], '1103'); // 20 CodeKsTerm
      expect(f[20], ''); // 21 lastresult
    });

    test('CardHolder: таб усередині → ";" (не ламає роздільник)', () {
      const withTab =
          '{"method":"Purchase","step":0,"params":{"responseCode":"0000",'
          '"cardHolderName":"IVAN\\tPETROV","date":"02.10.2019","time":"09:11:07"},'
          '"error":false}';
      final r = TerminalTxnResult.fromResponse(
          jsonDecode(withTab) as Map<String, dynamic>);
      final f = r
          .buildParamsPayCard(ssum: Money.zero, codeKsTerm: '1')
          .split('\t');
      expect(f.length, 21);
      expect(f[6], 'IVAN;PETROV');
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
