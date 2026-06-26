@TestOn('vm')
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/spl_params.dart';
import 'package:pharmacy_app/services/sparta_service.dart';

/// Інтеграційний smoke-тест проти DEMO-сервера Спарти (мережа!).
/// Запуск лише вручну: `SPARTA_DEMO=1 flutter test test/sparta_service_demo_test.dart`.
/// За замовчуванням пропускається (CI не ходить у зовнішню мережу).
void main() {
  final enabled = Platform.environment['SPARTA_DEMO'] == '1';

  // Публічні тестові креди demo (надав Андрій Попов).
  const config = SplParams(
    posKey: '87SNRM9ERH7YP6J6',
    placeCode: 'MR_TEST_PLACE',
    apiToken: 'ukw4kztxvael528f5ufpnk67r6xzyvc5fm2dghu7',
    baseUrl: 'https://demo.spartaloyalty.com/TestAnc2/api/',
    fallbackUrls: [],
    hostIps: [],
    pingCount: 0,
    timeoutSeconds: 30,
    allowBonusSpend: true,
    ngdMode: true,
    cardPrefixes: ['ANC'],
    globId: '129',
  );

  test('order → orderModify → orderStatusChange (demo)', () async {
    final svc = SpartaService(config, posCode: '1334');
    final now = DateTime.now();
    final no = 'IT${now.millisecondsSinceEpoch % 1000000}';
    final orderNo = config.orderNoFor(no);
    final basket = [
      {
        'productCode': '1038906', 'productCode2': '25482890', 'quantity': 1,
        'unitPriceGross': 79.5, 'amountGross': 79.5, 'discountGross': 0,
        'notPromoted': false, 'skipRD': false, 'skipCB': false, 'discounts': [],
      }
    ];
    final mops = [
      {'amount': 79.5, 'payCardNo': '', 'type': 'C'}
    ];
    final params = [
      {'code': 'pro_type', 'value': '2'}
    ];

    final ord = await svc.order(
      no: no, orderNo: orderNo, date: now, cardNo: 'TS00000103',
      basket: basket, mops: mops, params: params, amountGross: 79.5,
    );
    expect(ord.ok, isTrue, reason: 'order: ${ord.errorCode} ${ord.msg}');

    final mod = await svc.orderModify(
      no: no, orderNo: orderNo, date: now, cardNo: 'TS00000103',
      basket: basket, mops: mops, params: params, amountGross: 79.5,
      cashReceiptLinkUrl: 'https://test.cashdesk.com.ua/check/demo/html',
    );
    expect(mod.ok, isTrue, reason: 'orderModify: ${mod.errorCode} ${mod.msg}');

    final st = await svc.orderStatusChange(orderNo: orderNo, date: now);
    expect(st.ok, isTrue, reason: 'statusChange: ${st.errorCode} ${st.msg}');
  }, skip: enabled ? false : 'set SPARTA_DEMO=1 to run live demo test');
}
