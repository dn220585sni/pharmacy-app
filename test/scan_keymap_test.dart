import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/utils/scan_keymap.dart';

/// Зібрати код так, як це робить `_appendScanKey`: з ФІЗИЧНИХ клавіш.
/// [keys] — послідовність (клавіша, чи натиснуто Shift).
String decode(List<(PhysicalKeyboardKey, bool)> keys) {
  final b = StringBuffer();
  for (final (key, shift) in keys) {
    if (isScanTerminator(key)) break;
    if (isIgnoredForScan(key)) continue;
    final ch = scanCharFor(key, shift: shift);
    if (ch != null) b.write(ch);
  }
  return b.toString();
}

void main() {
  group('scanCharFor — літери', () {
    test('без Shift — маленькі, з Shift — великі', () {
      expect(scanCharFor(PhysicalKeyboardKey.keyQ, shift: false), 'q');
      expect(scanCharFor(PhysicalKeyboardKey.keyQ, shift: true), 'Q');
      expect(scanCharFor(PhysicalKeyboardKey.keyZ, shift: false), 'z');
      expect(scanCharFor(PhysicalKeyboardKey.keyZ, shift: true), 'Z');
    });

    test('ВЕСЬ алфавіт присутній у мапі', () {
      const keys = [
        PhysicalKeyboardKey.keyA, PhysicalKeyboardKey.keyB,
        PhysicalKeyboardKey.keyC, PhysicalKeyboardKey.keyD,
        PhysicalKeyboardKey.keyE, PhysicalKeyboardKey.keyF,
        PhysicalKeyboardKey.keyG, PhysicalKeyboardKey.keyH,
        PhysicalKeyboardKey.keyI, PhysicalKeyboardKey.keyJ,
        PhysicalKeyboardKey.keyK, PhysicalKeyboardKey.keyL,
        PhysicalKeyboardKey.keyM, PhysicalKeyboardKey.keyN,
        PhysicalKeyboardKey.keyO, PhysicalKeyboardKey.keyP,
        PhysicalKeyboardKey.keyQ, PhysicalKeyboardKey.keyR,
        PhysicalKeyboardKey.keyS, PhysicalKeyboardKey.keyT,
        PhysicalKeyboardKey.keyU, PhysicalKeyboardKey.keyV,
        PhysicalKeyboardKey.keyW, PhysicalKeyboardKey.keyX,
        PhysicalKeyboardKey.keyY, PhysicalKeyboardKey.keyZ,
      ];
      final got = keys.map((k) => scanCharFor(k, shift: false)).join();
      expect(got, 'abcdefghijklmnopqrstuvwxyz');
    });
  });

  group('scanCharFor — цифри й символи', () {
    test('верхній ряд без Shift — цифри', () {
      expect(scanCharFor(PhysicalKeyboardKey.digit1, shift: false), '1');
      expect(scanCharFor(PhysicalKeyboardKey.digit0, shift: false), '0');
    });

    test('верхній ряд із Shift — не великі цифри, а символи', () {
      expect(scanCharFor(PhysicalKeyboardKey.digit1, shift: true), '!');
      expect(scanCharFor(PhysicalKeyboardKey.digit2, shift: true), '@');
      expect(scanCharFor(PhysicalKeyboardKey.digit0, shift: true), ')');
    });

    test('пунктуація, яка трапляється в кодах', () {
      expect(scanCharFor(PhysicalKeyboardKey.minus, shift: false), '-');
      expect(scanCharFor(PhysicalKeyboardKey.minus, shift: true), '_');
      expect(scanCharFor(PhysicalKeyboardKey.period, shift: false), '.');
      expect(scanCharFor(PhysicalKeyboardKey.slash, shift: false), '/');
      expect(scanCharFor(PhysicalKeyboardKey.backslash, shift: false), r'\');
      expect(scanCharFor(PhysicalKeyboardKey.bracketLeft, shift: true), '{');
    });

    test('цифрова панель дає ті самі цифри', () {
      expect(scanCharFor(PhysicalKeyboardKey.numpad7, shift: false), '7');
      expect(scanCharFor(PhysicalKeyboardKey.numpadDecimal, shift: false), '.');
      expect(scanCharFor(PhysicalKeyboardKey.numpadSubtract, shift: false), '-');
    });
  });

  group('керуючі клавіші', () {
    test('модифікатори й навігація ігноруються, а не рахуються невідомими', () {
      for (final k in [
        PhysicalKeyboardKey.shiftLeft,
        PhysicalKeyboardKey.controlLeft,
        PhysicalKeyboardKey.capsLock,
        PhysicalKeyboardKey.tab,
        PhysicalKeyboardKey.arrowLeft,
      ]) {
        expect(isIgnoredForScan(k), isTrue, reason: '$k має ігноруватись');
        expect(scanCharFor(k, shift: false), isNull);
      }
    });

    test('Enter завершує скан', () {
      expect(isScanTerminator(PhysicalKeyboardKey.enter), isTrue);
      expect(isScanTerminator(PhysicalKeyboardKey.numpadEnter), isTrue);
      expect(isScanTerminator(PhysicalKeyboardKey.keyA), isFalse);
    });

    test('невідома клавіша не мапиться і НЕ ігнорується (піде в лог)', () {
      // F5 сканер слати не повинен; якщо шле — хочемо це побачити в журналі.
      expect(scanCharFor(PhysicalKeyboardKey.f5, shift: false), isNull);
      expect(isIgnoredForScan(PhysicalKeyboardKey.f5), isFalse);
    });
  });

  group('розбір повного скана', () {
    test('цифровий EAN-13', () {
      const seq = [
        (PhysicalKeyboardKey.digit4, false),
        (PhysicalKeyboardKey.digit8, false),
        (PhysicalKeyboardKey.digit2, false),
        (PhysicalKeyboardKey.digit0, false),
        (PhysicalKeyboardKey.digit0, false),
        (PhysicalKeyboardKey.digit1, false),
        (PhysicalKeyboardKey.digit7, false),
      ];
      expect(decode(seq), '4820017');
    });

    test('код із літерами — те, що ламалось кирилицею', () {
      // Фізично це клавіші Q-W-E-R-T-Y; при українській розкладці система
      // віддала б «ЙЦУКЕН», а ми беремо позицію, тож розкладка не впливає.
      const seq = [
        (PhysicalKeyboardKey.keyQ, true),
        (PhysicalKeyboardKey.keyW, true),
        (PhysicalKeyboardKey.keyE, true),
        (PhysicalKeyboardKey.minus, false),
        (PhysicalKeyboardKey.digit1, false),
        (PhysicalKeyboardKey.digit2, false),
        (PhysicalKeyboardKey.keyR, false),
      ];
      expect(decode(seq), 'QWE-12r');
    });

    test('Shift-клавіша в потоці не додає символу', () {
      const seq = [
        (PhysicalKeyboardKey.shiftLeft, false),
        (PhysicalKeyboardKey.keyA, true),
        (PhysicalKeyboardKey.keyB, true),
      ];
      expect(decode(seq), 'AB');
    });

    test('усе після Enter відкидається', () {
      const seq = [
        (PhysicalKeyboardKey.digit1, false),
        (PhysicalKeyboardKey.digit2, false),
        (PhysicalKeyboardKey.enter, false),
        (PhysicalKeyboardKey.digit9, false),
      ];
      expect(decode(seq), '12');
    });
  });
}
