import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/widgets/anc_coin.dart';
import 'package:pharmacy_app/widgets/shift_dashboard.dart';

void main() {
  testWidgets('AncCoin малюється й крутиться при зміні spinKey',
      (tester) async {
    Object? key = 1;
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return Center(child: AncCoin(size: 44, spinKey: key));
            },
          ),
        ),
      ),
    );
    expect(find.byType(AncCoin), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);

    setOuter(() => key = 2);
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);

    // Прокручуємо всю анімацію кадрами — жодних винятків у painter.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AncCoin spinOnMount крутиться після появи', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: AncCoin(spinOnMount: true))),
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ShiftDashboard зі «свіжим» нарахуванням крутить монетку',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShiftDashboard(
            earnedAmount: 12.5,
            lastEarnedAt: DateTime.now(),
          ),
        ),
      ),
    );
    expect(find.byType(AncCoin), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
