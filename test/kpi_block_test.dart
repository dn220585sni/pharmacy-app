import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/widgets/kpi_activity_ring.dart';
import 'package:pharmacy_app/widgets/kpi_block.dart';
import 'package:pharmacy_app/widgets/kpi_cumulative_chart.dart';
import 'package:pharmacy_app/widgets/kpi_plan_calendar.dart';

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
    expect(find.byType(KpiPlanCalendar), findsOneWidget);
    expect(find.byType(KpiActivityRing), findsOneWidget);
    expect(find.text('ПОТЕНЦІАЛ РОСТУ'), findsOneWidget);
    expect(find.text('Конверсія ТПК в ІЗ'), findsOneWidget);
    expect(find.text('Знижки «Рука допомоги»'), findsOneWidget);
    // Дві плашки: Чеків і Середній чек; «Днів із планом» немає.
    expect(find.text('ДНІВ ІЗ ПЛАНОМ'), findsNothing);
    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продаж ВТМ'));
    await tester.pumpAndSettle();
    expect(find.text('Продаж ВТМ · мої показники'), findsOneWidget);
    expect(find.text('11 / 18'), findsOneWidget);
    expect(find.text('ЧАСТКА ВТМ'), findsNothing);
    // Мої: накопичений факт (38 500) > план місяця (22 000) → бонус є.
    expect(find.text('175%'), findsOneWidget);
    expect(find.textContaining('Йдете на бонус +20%: близько +248 балів'),
        findsOneWidget);
    expect(find.byType(KpiCumulativeChart), findsOneWidget);
    expect(find.text('ПРОПУЩЕНІ ЗАМІНИ НА ВТМ'), findsOneWidget);
    expect(find.text('Разом'), findsOneWidget);
    expect(find.text('+306 ₴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ВТМ: в «Показниках аптеки» бонусу немає, план місяця 64%',
      (tester) async {
    await tester.pumpWidget(_wrap(KpiBlock(today: DateTime(2026, 9, 23))));
    await tester.tap(find.text('Показники аптеки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продаж ВТМ'));
    await tester.pumpAndSettle();
    expect(find.text('64%'), findsOneWidget);
    expect(find.textContaining('Йдете на бонус'), findsNothing);
    expect(find.text('148 / 236'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Календар: клік по даті міняє «Потенціал росту» й «Активність»',
      (tester) async {
    await tester.pumpWidget(_wrap(KpiBlock(today: DateTime(2026, 9, 23))));
    await tester.tap(find.text('Товарообіг'));
    await tester.pumpAndSettle();
    // Типово обрано сьогодні: два підписи секцій + легенда календаря.
    expect(find.text('сьогодні'), findsNWidgets(3));
    final growthToday = KpiMockData.growthRows(23).first.my;
    expect(find.text(growthToday), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('cal-day-8')));
    await tester.tap(find.byKey(const ValueKey('cal-day-8')));
    await tester.pumpAndSettle();
    expect(find.text('8 вересня'), findsNWidgets(2));
    final growth8 = KpiMockData.growthRows(8).first.my;
    expect(find.text(growth8), findsOneWidget);
    expect(find.text(growthToday), findsNothing);

    // Майбутній день не клікається (без InkWell з ключем).
    expect(find.byKey(const ValueKey('cal-day-30')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('KpiActivityRing: наведення показує підказку події',
      (tester) async {
    const data = KpiActivityData(
      shiftStart: 8 * 60,
      shiftEnd: 20 * 60,
      now: 14 * 60,
      events: [KpiActivityEvent(8 * 60, KpiEventType.cash)],
      presence: [KpiPresence(9 * 60, 9 * 60 + 30)],
    );
    await tester.pumpWidget(_wrap(const KpiActivityRing(data: data)));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Без обслуговування · 1'), findsOneWidget);
    expect(find.text('30 хв без обслуговування'), findsOneWidget);

    // Подія о 08:00 стоїть на початку дуги (135°): наводимо на цю точку.
    // Полотно кілець починається у верхньому лівому куті віджета.
    final box = tester.getRect(find.byType(KpiActivityRing));
    final scale = box.width / 320;
    final center = box.topLeft + Offset(160 * scale, 150 * scale);
    final r = 108 * scale;
    final at = center + Offset(r * -0.7071, r * 0.7071);
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(g.removePointer);
    await g.moveTo(at);
    await tester.pumpAndSettle();
    expect(find.text('Чек, готівка, 08:00'), findsOneWidget);
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
