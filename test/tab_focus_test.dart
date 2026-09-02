import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tab — префікс скана від сканера штрихкодів, а не навігація.
///
/// `WidgetsApp` за замовчуванням мапить його на `NextFocusIntent`, і фокус
/// їхав на наступний віджет при кожному скані: рядок нижче в списку, а при
/// порожньому кошику — у сусіднє меню (три баги в беклозі 02.09).
///
/// ⚠️ Обробник у `HardwareKeyboard` цього НЕ зупиняє, хоч і повертає `true`:
/// `KeyEventManager` викликає систему фокуса безумовно. Тому тест саме на
/// поведінку фокуса, а не на результат обробника.
void main() {
  /// Той самий спосіб перекриття, що і в `PharmacyApp`.
  Widget app({required bool blockTab}) {
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    return MaterialApp(
      builder: blockTab
          ? (context, child) => Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.tab): DoNothingIntent(),
                  SingleActivator(LogicalKeyboardKey.tab, shift: true):
                      DoNothingIntent(),
                },
                child: child ?? const SizedBox.shrink(),
              )
          : null,
      home: Scaffold(
        body: Column(
          children: [
            TextField(focusNode: a),
            TextField(focusNode: b),
          ],
        ),
      ),
    );
  }

  testWidgets('без перекриття Tab переводить фокус — саме це й ламало скан',
      (tester) async {
    await tester.pumpWidget(app(blockTab: false));
    final first = tester.widget<TextField>(find.byType(TextField).first);
    first.focusNode!.requestFocus();
    await tester.pump();
    expect(first.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(first.focusNode!.hasFocus, isFalse,
        reason: 'дефолт WidgetsApp: Tab → NextFocusIntent');
  });

  testWidgets('з перекриттям фокус лишається на місці', (tester) async {
    await tester.pumpWidget(app(blockTab: true));
    final first = tester.widget<TextField>(find.byType(TextField).first);
    first.focusNode!.requestFocus();
    await tester.pump();
    expect(first.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(first.focusNode!.hasFocus, isTrue,
        reason: 'Tab належить сканеру — фокус рухатись не має');
  });

  testWidgets('Shift+Tab теж не рухає фокус', (tester) async {
    await tester.pumpWidget(app(blockTab: true));
    final second = tester.widget<TextField>(find.byType(TextField).last);
    second.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(second.focusNode!.hasFocus, isTrue);
  });
}
