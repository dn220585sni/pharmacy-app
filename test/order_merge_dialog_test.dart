import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/internet_order.dart';
import 'package:pharmacy_app/widgets/orders/order_merge_dialog.dart';

/// Вікно підтвердження об'єднання показує ПОВНИЙ склад кожного замовлення
/// (Микола, 24.09): позиції, кількість × ціна, знижку на чек, разом.
void main() {
  InternetOrder order(String no, List<OrderItem> items, double total) =>
      InternetOrder(
        id: no,
        reserveNumber: no,
        dateTime: DateTime(2026, 9, 24, 10, 15),
        total: total,
        status: OrderStatus.collected,
        type: OrderType.tabletkiUA,
        customerPhone: '(067)1112233',
        customerName: 'Іваненко Іван',
        items: items,
      );

  final orders = [
    order('181618169', [
      OrderItem(
          sku: '1', name: 'АЛЕРЗИН ТАБЛ. 5МГ №14', quantity: 2, price: 190,
          total: 380),
      OrderItem(
          sku: '2', name: 'ЙОДУ РОЗЧИН 5% 20МЛ', quantity: 1, price: 25.5,
          total: 25.5, strikeOut: true),
      OrderItem(
          sku: '', name: 'Знижка на чек', quantity: 1, price: -0.1,
          total: -0.1),
    ], 405.4),
    order('184550439', [
      OrderItem(
          sku: '3', name: 'ПАКЕТ МАЙКА 30Х50', quantity: 1, price: 3.1,
          total: 3.1),
    ], 3.1),
  ];

  testWidgets('склад обох замовлень, підсумок і кнопки', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async =>
                  result = await showOrderMergeDialog(ctx, orders),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.text('Об\'єднання 2 замовлень в один чек'), findsOneWidget);
    expect(find.textContaining('Іваненко Іван'), findsOneWidget);
    // Обидва номери й усі позиції.
    expect(find.textContaining('№181618169'), findsOneWidget);
    expect(find.textContaining('№184550439'), findsOneWidget);
    expect(find.text('АЛЕРЗИН ТАБЛ. 5МГ №14'), findsOneWidget);
    expect(find.text('ЙОДУ РОЗЧИН 5% 20МЛ'), findsOneWidget);
    expect(find.text('ПАКЕТ МАЙКА 30Х50'), findsOneWidget);
    expect(find.text('Знижка на чек'), findsOneWidget);
    // Кількість × ціна і разом (3 товарні позиції, службова не рахується).
    expect(find.text('2 × 190,00'), findsOneWidget);
    expect(find.text('Разом · 3 поз.'), findsOneWidget);
    expect(find.text('408,50 ₴'), findsOneWidget);

    await t.tap(find.text('Об\'єднати'));
    await t.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('«Скасувати» повертає false', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async =>
                result = await showOrderMergeDialog(ctx, orders),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Скасувати'));
    await t.pumpAndSettle();
    expect(result, isFalse);
  });
}
