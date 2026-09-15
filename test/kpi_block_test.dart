import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/widgets/kpi_block.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 420, child: child),
        ),
      ),
    );

void main() {
  testWidgets('KpiBlock: три показники з планом і бейджами', (tester) async {
    await tester.pumpWidget(_wrap(KpiBlock(today: DateTime(2026, 9, 23))));
    expect(find.text('Товарообіг'), findsOneWidget);
    expect(find.text('Продаж ВТМ'), findsOneWidget);
    expect(find.text('Частка ЗФ'), findsOneWidget);
    // Мої: 3200/5000 = 64%, 2100/3000 = 70%, 13,67/13 = 105%.
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('105%'), findsOneWidget);
    expect(find.text('13,67%'), findsOneWidget);
    expect(find.text('план 13%'), findsOneWidget);
  });

  testWidgets('KpiBlock: перемикач «Показники аптеки» міняє цифри',
      (tester) async {
    await tester.pumpWidget(_wrap(KpiBlock(today: DateTime(2026, 9, 23))));
    await tester.tap(find.text('Показники аптеки'));
    await tester.pumpAndSettle();
    // Аптека: 41200/60000 = 69%, 12,41/13 = 95%.
    expect(find.text('69%'), findsOneWidget);
    expect(find.text('95%'), findsOneWidget);
    expect(find.text('12,41%'), findsOneWidget);
    expect(find.text('64%'), findsNothing);
  });

  testWidgets('KpiBlock: клік по рядку відкриває деталізацію, «Назад» повертає',
      (tester) async {
    await tester.pumpWidget(_wrap(KpiBlock(today: DateTime(2026, 9, 23))));
    await tester.tap(find.text('Частка ЗФ'));
    await tester.pumpAndSettle();
    expect(find.text('Частка ЗФ · мої показники'), findsOneWidget);
    expect(find.text('план на вересень 13%'), findsOneWidget);
    expect(find.text('11 / 18'), findsOneWidget);
    expect(find.byType(KpiDayChart), findsOneWidget);
    expect(find.text('Товарообіг'), findsNothing);

    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    expect(find.text('Товарообіг'), findsOneWidget);
    expect(find.byType(KpiDayChart), findsNothing);
  });

  testWidgets('KpiBlock: деталізація Товарообігу та ВТМ без винятків',
      (tester) async {
    await tester.pumpWidget(_wrap(KpiBlock(today: DateTime(2026, 9, 23))));
    await tester.tap(find.text('Товарообіг'));
    await tester.pumpAndSettle();
    expect(find.text('Товарообіг · мої показники'), findsOneWidget);
    expect(find.text('177,78'), findsOneWidget);
    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продаж ВТМ'));
    await tester.pumpAndSettle();
    expect(find.text('Продаж ВТМ · мої показники'), findsOneWidget);
    expect(find.text('65,6%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('kpi форматування', () {
    expect(kpiInt(3200), '3 200');
    expect(kpiInt(41200), '41 200');
    expect(kpiPct(13.67), '13,67%');
    expect(kpiPct(13, 0), '13%');
    expect(kpiMoney(177.78), '177,78');
  });
}
