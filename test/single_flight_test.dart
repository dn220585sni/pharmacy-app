import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/utils/single_flight.dart';

void main() {
  test('тіло без await не «залипає»: наступний виклик знову виконує тіло',
      () async {
    // Регресія 25.09: перший синк бонусу (0 == 0) нічого не робив, і всі
    // наступні повертали той самий старий future — SetBonusOpl не йшов.
    final sf = SingleFlight<bool>();
    var calls = 0;
    Future<bool> body() async {
      calls++;
      return true;
    }

    await sf.run(body);
    expect(sf.isRunning, isFalse);
    await sf.run(body);
    expect(calls, 2);
  });

  test('поки операція в дорозі — повертається та сама, тіло не дублюється',
      () async {
    final sf = SingleFlight<int>();
    final gate = Completer<int>();
    var calls = 0;
    Future<int> body() {
      calls++;
      return gate.future;
    }

    final a = sf.run(body);
    final b = sf.run(body);
    expect(identical(a, b), isTrue);
    gate.complete(7);
    expect(await a, 7);
    expect(calls, 1);
    expect(sf.isRunning, isFalse);
  });

  test('помилка теж звільняє слот', () async {
    final sf = SingleFlight<int>();
    await expectLater(sf.run(() async => throw StateError('x')),
        throwsStateError);
    expect(sf.isRunning, isFalse);
    expect(await sf.run(() async => 1), 1);
  });
}
