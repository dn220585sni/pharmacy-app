import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/sklad_ini.dart';

void main() {
  /// Фрагмент справжнього sklad.ini з тестової каси (D:\CacheSys\Mgr\User).
  /// Закоментовані рядки лишено дослівно — саме через них потрібен розбір
  /// коментарів.
  const real = r'''
[KodPotr]
Kod=1241,1285
[Sklad]
AutoConnect=Yes
;Hook=1
HookAutoRun=0
;MultipleInstance=1
BazaPath=v:\baza
LocalTemp=v:\temp
LocalOut=v:\out
;Graph=e:\sertif\graph\;e:\sertif\gr2
GraphSklad=d:\sertif
[SkladLocal]
LocalOut=V:\skladlocal\
''';

  group('value', () {
    test('дістає LocalOut із секції Sklad', () {
      expect(SkladIni.value(real, 'Sklad', 'LocalOut'), r'v:\out');
    });

    test('секція має значення — у SkladLocal свій LocalOut', () {
      expect(SkladIni.value(real, 'SkladLocal', 'LocalOut'), r'V:\skladlocal\');
    });

    test('регістр секції й ключа не має значення', () {
      expect(SkladIni.value(real, 'sklad', 'localout'), r'v:\out');
      expect(SkladIni.value(real, 'SKLAD', 'LOCALOUT'), r'v:\out');
    });

    test('закоментоване значення не береться', () {
      // У файлі поруч лежать «;Graph=e:\sertif\...» і робочий GraphSklad.
      // Якби ми не пропускали коментарі, можна було б узяти вимкнений шлях.
      expect(SkladIni.value(real, 'Sklad', 'Graph'), isNull);
      expect(SkladIni.value(real, 'Sklad', 'Hook'), isNull);
      expect(SkladIni.value(real, 'Sklad', 'MultipleInstance'), isNull);
    });

    test('відсутній ключ або секція — null', () {
      expect(SkladIni.value(real, 'Sklad', 'НемаєТакого'), isNull);
      expect(SkladIni.value(real, 'НемаєСекції', 'LocalOut'), isNull);
      expect(SkladIni.value('', 'Sklad', 'LocalOut'), isNull);
    });

    test('порожнє значення = ключа немає', () {
      expect(
          SkladIni.value('[Sklad]\nLocalOut=\n', 'Sklad', 'LocalOut'), isNull);
      expect(SkladIni.value('[Sklad]\nLocalOut=   \n', 'Sklad', 'LocalOut'),
          isNull);
    });

    test('пробіли навколо ключа й значення зрізаються', () {
      expect(
        SkladIni.value('[Sklad]\n  LocalOut  =  v:\\out  \n', 'Sklad',
            'LocalOut'),
        r'v:\out',
      );
    });

    test('рядок без «=» не ламає розбір', () {
      expect(
        SkladIni.value(
            '[Sklad]\nсміття\nLocalOut=v:\\out\n', 'Sklad', 'LocalOut'),
        r'v:\out',
      );
    });
  });

  group('candidates', () {
    test('шукаємо по неймспейсу, D: першим — там воно на тестовій касі', () {
      final c = SkladIni.candidates();
      expect(c.first, r'D:\CacheSys\Mgr\User\sklad.ini');
      expect(c, contains(r'C:\CacheSys\Mgr\User\sklad.ini'));
    });

    test('інший неймспейс підставляється в шлях', () {
      expect(SkladIni.candidates(nameSpace: 'FARM').first,
          r'D:\CacheSys\Mgr\FARM\sklad.ini');
    });
  });

  group('кодування файлу', () {
    test('cp1251 не валить читання — саме на цьому воно падало 07.09', () {
      // Реальна помилка: «Failed to decode data using encoding utf-8».
      // Кирилиця в коментарях перетворюється на мотлох, але ключ і шлях —
      // ASCII, і вони доходять цілими.
      final bytes = <int>[
        ...'[Sklad]\n'.codeUnits,
        ...';'.codeUnits, 0xCA, 0xEE, 0xEC, 0xE5, 0xED, 0xF2, // «Комент» cp1251
        ...'\nLocalOut=v:\\out\n'.codeUnits,
      ];
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(SkladIni.value(text, 'Sklad', 'LocalOut'), r'v:\out');
    });
  });
}
