import 'package:flutter/services.dart';

/// Розкладко-незалежне читання скана штрихкода.
///
/// Сканер — це HID-клавіатура: він шле НАТИСКАННЯ КЛАВІШ, а не текст. Тому
/// `KeyEvent.character` залежить від активної розкладки Windows: та сама
/// фізична клавіша при українській розкладці дає «Й», при англійській — «Q».
/// Цифри від розкладки не залежать, тож чисті EAN-13 працювали й так, а от
/// стікери маркування та картки лояльності з літерами читались покаліченими
/// (зауваження Андрія, 31.08).
///
/// Рішення: беремо `KeyEvent.physicalKey` — це USB HID-код, тобто ФІЗИЧНА
/// позиція клавіші, яка не залежить від розкладки взагалі, — і самі мапимо
/// його в символ US-розкладки.
///
/// Свідомо НЕ перемикаємо розкладку Windows, як це роблять у Delphi-модулі:
/// сканер «друкує» по 5-10 мс на символ, а перемикання через Win32 асинхронне
/// відносно черги подій Flutter — ми не встигли б до першої літери. Плюс це
/// глобальний побічний ефект: аварія посеред скана лишила б касира з чужою
/// розкладкою.

/// Символ US-розкладки без Shift.
final _base = <PhysicalKeyboardKey, String>{
  PhysicalKeyboardKey.keyA: 'a',
  PhysicalKeyboardKey.keyB: 'b',
  PhysicalKeyboardKey.keyC: 'c',
  PhysicalKeyboardKey.keyD: 'd',
  PhysicalKeyboardKey.keyE: 'e',
  PhysicalKeyboardKey.keyF: 'f',
  PhysicalKeyboardKey.keyG: 'g',
  PhysicalKeyboardKey.keyH: 'h',
  PhysicalKeyboardKey.keyI: 'i',
  PhysicalKeyboardKey.keyJ: 'j',
  PhysicalKeyboardKey.keyK: 'k',
  PhysicalKeyboardKey.keyL: 'l',
  PhysicalKeyboardKey.keyM: 'm',
  PhysicalKeyboardKey.keyN: 'n',
  PhysicalKeyboardKey.keyO: 'o',
  PhysicalKeyboardKey.keyP: 'p',
  PhysicalKeyboardKey.keyQ: 'q',
  PhysicalKeyboardKey.keyR: 'r',
  PhysicalKeyboardKey.keyS: 's',
  PhysicalKeyboardKey.keyT: 't',
  PhysicalKeyboardKey.keyU: 'u',
  PhysicalKeyboardKey.keyV: 'v',
  PhysicalKeyboardKey.keyW: 'w',
  PhysicalKeyboardKey.keyX: 'x',
  PhysicalKeyboardKey.keyY: 'y',
  PhysicalKeyboardKey.keyZ: 'z',
  PhysicalKeyboardKey.digit1: '1',
  PhysicalKeyboardKey.digit2: '2',
  PhysicalKeyboardKey.digit3: '3',
  PhysicalKeyboardKey.digit4: '4',
  PhysicalKeyboardKey.digit5: '5',
  PhysicalKeyboardKey.digit6: '6',
  PhysicalKeyboardKey.digit7: '7',
  PhysicalKeyboardKey.digit8: '8',
  PhysicalKeyboardKey.digit9: '9',
  PhysicalKeyboardKey.digit0: '0',
  PhysicalKeyboardKey.minus: '-',
  PhysicalKeyboardKey.equal: '=',
  PhysicalKeyboardKey.bracketLeft: '[',
  PhysicalKeyboardKey.bracketRight: ']',
  PhysicalKeyboardKey.backslash: r'\',
  PhysicalKeyboardKey.semicolon: ';',
  PhysicalKeyboardKey.quote: "'",
  PhysicalKeyboardKey.backquote: '`',
  PhysicalKeyboardKey.comma: ',',
  PhysicalKeyboardKey.period: '.',
  PhysicalKeyboardKey.slash: '/',
  PhysicalKeyboardKey.space: ' ',
  // Цифрова панель — частина сканерів шле саме її.
  PhysicalKeyboardKey.numpad0: '0',
  PhysicalKeyboardKey.numpad1: '1',
  PhysicalKeyboardKey.numpad2: '2',
  PhysicalKeyboardKey.numpad3: '3',
  PhysicalKeyboardKey.numpad4: '4',
  PhysicalKeyboardKey.numpad5: '5',
  PhysicalKeyboardKey.numpad6: '6',
  PhysicalKeyboardKey.numpad7: '7',
  PhysicalKeyboardKey.numpad8: '8',
  PhysicalKeyboardKey.numpad9: '9',
  PhysicalKeyboardKey.numpadDecimal: '.',
  PhysicalKeyboardKey.numpadDivide: '/',
  PhysicalKeyboardKey.numpadMultiply: '*',
  PhysicalKeyboardKey.numpadSubtract: '-',
  PhysicalKeyboardKey.numpadAdd: '+',
  PhysicalKeyboardKey.numpadEqual: '=',
};

/// Символ US-розкладки з Shift — лише там, де він НЕ зводиться до великої
/// літери (літери обробляються через `toUpperCase`).
final _shifted = <PhysicalKeyboardKey, String>{
  PhysicalKeyboardKey.digit1: '!',
  PhysicalKeyboardKey.digit2: '@',
  PhysicalKeyboardKey.digit3: '#',
  PhysicalKeyboardKey.digit4: r'$',
  PhysicalKeyboardKey.digit5: '%',
  PhysicalKeyboardKey.digit6: '^',
  PhysicalKeyboardKey.digit7: '&',
  PhysicalKeyboardKey.digit8: '*',
  PhysicalKeyboardKey.digit9: '(',
  PhysicalKeyboardKey.digit0: ')',
  PhysicalKeyboardKey.minus: '_',
  PhysicalKeyboardKey.equal: '+',
  PhysicalKeyboardKey.bracketLeft: '{',
  PhysicalKeyboardKey.bracketRight: '}',
  PhysicalKeyboardKey.backslash: '|',
  PhysicalKeyboardKey.semicolon: ':',
  PhysicalKeyboardKey.quote: '"',
  PhysicalKeyboardKey.backquote: '~',
  PhysicalKeyboardKey.comma: '<',
  PhysicalKeyboardKey.period: '>',
  PhysicalKeyboardKey.slash: '?',
};

/// Клавіші, які під час скана нічого не додають і НЕ є «невідомими»:
/// модифікатори, керуючі, навігація. Потрібні, щоб лог невідомих клавіш не
/// засмічувався очікуваним.
final _ignored = <PhysicalKeyboardKey>{
  PhysicalKeyboardKey.shiftLeft,
  PhysicalKeyboardKey.shiftRight,
  PhysicalKeyboardKey.controlLeft,
  PhysicalKeyboardKey.controlRight,
  PhysicalKeyboardKey.altLeft,
  PhysicalKeyboardKey.altRight,
  PhysicalKeyboardKey.metaLeft,
  PhysicalKeyboardKey.metaRight,
  PhysicalKeyboardKey.capsLock,
  PhysicalKeyboardKey.numLock,
  PhysicalKeyboardKey.scrollLock,
  PhysicalKeyboardKey.tab,
  PhysicalKeyboardKey.enter,
  PhysicalKeyboardKey.numpadEnter,
  PhysicalKeyboardKey.escape,
  PhysicalKeyboardKey.backspace,
  PhysicalKeyboardKey.delete,
  PhysicalKeyboardKey.insert,
  PhysicalKeyboardKey.home,
  PhysicalKeyboardKey.end,
  PhysicalKeyboardKey.pageUp,
  PhysicalKeyboardKey.pageDown,
  PhysicalKeyboardKey.arrowUp,
  PhysicalKeyboardKey.arrowDown,
  PhysicalKeyboardKey.arrowLeft,
  PhysicalKeyboardKey.arrowRight,
};

/// Символ US-розкладки для ФІЗИЧНОЇ клавіші [key].
///
/// `null` — клавіша не друкована або невідома; відрізнити одне від одного
/// можна через [isIgnoredForScan].
String? scanCharFor(PhysicalKeyboardKey key, {required bool shift}) {
  if (shift) {
    final s = _shifted[key];
    if (s != null) return s;
    return _base[key]?.toUpperCase();
  }
  return _base[key];
}

/// Чи є [key] очікувано «мовчазною» під час скана (модифікатор, Enter, ...).
bool isIgnoredForScan(PhysicalKeyboardKey key) => _ignored.contains(key);

/// Чи завершує [key] скан. Наш сканер налаштований без Enter (флаш по паузі),
/// але деякі шлють його суфіксом — тоді не чекаємо таймаут даремно.
bool isScanTerminator(PhysicalKeyboardKey key) =>
    key == PhysicalKeyboardKey.enter || key == PhysicalKeyboardKey.numpadEnter;
