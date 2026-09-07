// Дослід: чи віддає ECR-термінал ПОВНИЙ номер картки через ReadBonusCard.
//
// ❄️ РЕЗУЛЬТАТ (07.09.2026, CASTLES S1F3CT): метод РЕАЛІЗОВАНО — термінал
// прийняв команду й почав діалог, але просить ЧІПОВАНУ картку, тобто
// безконтактно повного номера не дає. Це узгоджується з правилами EMV:
// безконтактна картка віддає дані лише в межах платіжної операції.
//
// Задачу «Нацкешбек» після цього заморожено (програму призупинено). Скрипт
// лишаємо: якщо розморозять, з нього починати — він доводить, що метод на
// терміналі є, і показує, як саме його викликати.
//
// Навіщо. `PANFromBaskets` Катерини (перевірка Нацкешбеку) очікує повний
// номер картки з термінала. Але `Purchase` віддає лише маску
// («4731XXXXXXXX9838»), а єдина операція в протоколі ПриватБанку, що читає
// картку БЕЗ списання й показує повний номер, — це `ReadBonusCard` (ECR 5.22).
// Ним не користується ні ПриватБанк з боку Тані, ні Андрій. «Не
// використовували» ще не означає «не працює», тож перевіряємо на живому
// терміналі.
//
// Гроші НЕ рухаються: ReadBonusCard лише читає картку. Але це справжня
// команда справжньому терміналу — запускати на ТЕСТОВОМУ.
//
// Запуск:
//   dart run tool/test_read_bonus_card.dart <host> <port> [enterPIN]
// Приклад:
//   dart run tool/test_read_bonus_card.dart 192.168.1.50 8080
//
// `enterPIN` (0 або 1) — за описом 5.22 керує тим, чи просити ПІН. За
// замовчуванням 0: нам потрібен лише номер.
//
// Що дивитись у виводі: рядок «PAN:». Якщо там 16 цифр без «X» — напрямок
// відкритий. Якщо маска, помилка або methodNotImplemented — закритий, і
// питання переходить до ПриватБанку.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('Використання: dart run tool/test_read_bonus_card.dart '
        '<host> <port> [enterPIN=0]');
    exit(64);
  }
  final host = args[0];
  final port = int.tryParse(args[1]) ?? 0;
  final enterPin = args.length > 2 ? args[2] : '0';
  if (port <= 0) {
    stderr.writeln('Порт має бути числом.');
    exit(64);
  }

  final term = _Terminal(host, port);
  try {
    print('→ Підключення до $host:$port…');
    await term.connect();

    print('→ PingDevice…');
    print('   ${_short(await term.send({'method': 'PingDevice', 'step': 0}))}');

    print('→ ServiceMessage identify…');
    final ident = await term.send({
      'method': 'ServiceMessage',
      'step': 0,
      'params': {'msgType': 'identify'},
    });
    print('   ${_short(ident)}');

    print('');
    print('→ ReadBonusCard. ПРИКЛАДІТЬ КАРТКУ ДО ТЕРМІНАЛА (до 90 с)…');
    // Форма запиту за 5.22.1. `prompt` — рядки, які термінал показує на
    // екрані; без нього він мовчить, бо йому нема чого відобразити. `timeout`
    // у мілісекундах, за описом типово 60 с.
    final res = await term.send(
      {
        'method': 'ReadBonusCard',
        'step': 0,
        'prompt': {
          'line': [
            {'text': 'ПЕРЕВІРКА КАРТКИ', 'font': 'B', 'align': 'C'},
            {'text': 'Прикладіть картку', 'font': 'B', 'align': 'C'},
          ],
        },
        'params': {'enterPIN': enterPin, 'timeout': '60000'},
      },
      timeout: const Duration(seconds: 90),
    );

    print('');
    print('── ВІДПОВІДЬ ──────────────────────────────────────────────');
    print(const JsonEncoder.withIndent('  ').convert(_redact(res)));
    print('───────────────────────────────────────────────────────────');

    final params = res['params'];
    final pan = params is Map ? (params['pan']?.toString() ?? '') : '';
    final rc = params is Map ? (params['responseCode']?.toString() ?? '') : '';
    print('');
    print('PAN: ${pan.isEmpty ? "(немає)" : pan}');
    print('responseCode: ${rc.isEmpty ? "(немає)" : rc}');
    print('error: ${res['error']} ${res['errorDescription'] ?? ""}');
    print('');
    print(_verdict(pan, res));
  } catch (e) {
    print('');
    print('ЗБІЙ: $e');
    print('Якщо це таймаут або відмова зʼєднання — перевірте host/port '
        'та чи не зайнятий термінал іншою операцією.');
    exitCode = 1;
  } finally {
    await term.close();
  }
}

/// Прибрати з виводу те, що не має лежати в консолі.
///
/// `track2` — повна доріжка магнітної смуги (номер, термін дії, сервісний
/// код), `pinblock` — зашифрований ПІН. Для нашого досліду вони не потрібні:
/// перевіряємо лише, чи приходить повний `pan`. Показуємо, що поле є і яку
/// має довжину, але не саме значення.
Map<String, dynamic> _redact(Map<String, dynamic> res) {
  const secret = {'track2', 'pinblock', 'track1', 'track3'};
  final out = Map<String, dynamic>.from(res);
  final p = out['params'];
  if (p is Map) {
    final params = Map<String, dynamic>.from(p);
    for (final k in params.keys.toList()) {
      if (!secret.contains(k.toLowerCase())) continue;
      final len = params[k]?.toString().length ?? 0;
      params[k] = '<приховано, $len символів>';
    }
    out['params'] = params;
  }
  return out;
}

String _verdict(String pan, Map<String, dynamic> res) {
  final digits = pan.replaceAll(RegExp(r'\D'), '');
  if (pan.toUpperCase().contains('X')) {
    return 'ВИСНОВОК: номер замаскований — для PANFromBaskets не годиться.';
  }
  if (digits.length >= 13) {
    return 'ВИСНОВОК: повний номер отримано (${digits.length} цифр). '
        'Напрямок відкритий — ReadBonusCard можна використовувати.';
  }
  if (res['error'] == true) {
    return 'ВИСНОВОК: термінал відмовив. Якщо це methodNotImplemented — '
        'операція не підтримується, питання до ПриватБанку.';
  }
  return 'ВИСНОВОК: номера немає. Дивіться повну відповідь вище.';
}

String _short(Map<String, dynamic> m) {
  final s = jsonEncode(m);
  return s.length > 220 ? '${s.substring(0, 220)}…' : s;
}

/// Мінімальний ECR-клієнт: те саме обрамлення, що в `EcrTerminalClient` —
/// UTF-8 JSON, завершальний 0x00, і ведучий 0x00 у першому повідомленні.
class _Terminal {
  _Terminal(this.host, this.port);

  final String host;
  final int port;

  Socket? _socket;
  final _rx = <int>[];
  var _firstSend = true;
  Completer<Map<String, dynamic>>? _pending;
  String _awaiting = '';

  Future<void> connect() async {
    final s = await Socket.connect(host, port,
        timeout: const Duration(seconds: 5));
    _socket = s;
    s.listen(_onData, onError: (Object e) => print('   [сокет] $e'));
  }

  Future<Map<String, dynamic>> send(
    Map<String, dynamic> request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final s = _socket;
    if (s == null) throw StateError('сокет не відкритий');
    _awaiting = request['method'].toString();
    final completer = Completer<Map<String, dynamic>>();
    _pending = completer;

    final bytes = <int>[];
    if (_firstSend) {
      bytes.add(0);
      _firstSend = false;
    }
    bytes
      ..addAll(utf8.encode(jsonEncode(request)))
      ..add(0);
    s.add(bytes);

    try {
      return await completer.future.timeout(timeout);
    } finally {
      _pending = null;
    }
  }

  void _onData(List<int> data) {
    for (final b in data) {
      if (b != 0) {
        _rx.add(b);
        continue;
      }
      if (_rx.isEmpty) continue;
      final raw = utf8.decode(_rx, allowMalformed: true);
      _rx.clear();
      Map<String, dynamic>? msg;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) msg = decoded;
      } catch (_) {}
      if (msg == null) {
        print('   [не JSON] $raw');
        continue;
      }
      final method = msg['method']?.toString() ?? '';
      final p = _pending;
      if (p != null && !p.isCompleted && method == _awaiting) {
        p.complete(msg);
      } else {
        // Проміжні статуси терміналу — «ОЧІКУЮ КАРТКУ» тощо.
        print('   [статус] $method ${jsonEncode(msg['params'] ?? {})}');
      }
    }
  }

  Future<void> close() async {
    final s = _socket;
    _socket = null;
    if (s == null) return;
    try {
      await s.close();
    } catch (_) {}
    s.destroy();
  }
}
