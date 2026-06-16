import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/money.dart';

// Примітка: повноцінний smoke-тест усього PharmacyApp потребує DI/моків
// сервісів (старт додатка йде в мережу) — окремий пункт аудиту. Поки що —
// фокусований widget-тест відображення грошей (без мережі).
void main() {
  testWidgets('Money рендериться у віджеті як "19,99 ₴"', (tester) async {
    final hrn = String.fromCharCode(0x20B4);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Text(19.99.asMoneySymbol))),
    );
    expect(find.text('19,99 $hrn'), findsOneWidget);
  });
}
