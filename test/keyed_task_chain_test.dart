import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/utils/keyed_task_chain.dart';

/// Код-рев'ю 22.09, п.6: два швидких «+» на одній позиції мають піти на
/// сервер послідовно, і другий має бачити результат першого.
void main() {
  test('задачі з одним ключем виконуються послідовно', () async {
    final chain = KeyedTaskChain();
    final log = <String>[];
    final gate = Completer<void>();

    final a = chain.run('x', () async {
      log.add('a:start');
      await gate.future;
      log.add('a:end');
    });
    final b = chain.run('x', () async {
      log.add('b:start');
    });
    await Future<void>.delayed(Duration.zero);
    expect(log, ['a:start']); // b ще не стартував
    gate.complete();
    await Future.wait([a, b]);
    expect(log, ['a:start', 'a:end', 'b:start']);
    expect(chain.activeKeys, 0);
  });

  test('бажана кількість рахується на старті тіла, а не при постановці',
      () async {
    final chain = KeyedTaskChain();
    var quantity = 1;
    Future<void> plus() => chain.run('drug', () async {
          final want = quantity + 1; // як другий «+», що бачить перший
          await Future<void>.delayed(const Duration(milliseconds: 5));
          quantity = want; // «підтверджено сервером»
        });
    await Future.wait([plus(), plus()]);
    expect(quantity, 3); // без черги обидва просили б 2
  });

  test('різні ключі — паралельно', () async {
    final chain = KeyedTaskChain();
    final gate = Completer<void>();
    var bRan = false;
    final a = chain.run('x', () => gate.future);
    final b = chain.run('y', () async => bRan = true);
    await b;
    expect(bRan, isTrue);
    gate.complete();
    await a;
  });

  test('помилка в задачі не блокує наступну з тим самим ключем', () async {
    final chain = KeyedTaskChain();
    await expectLater(
        chain.run('x', () async => throw StateError('boom')), throwsStateError);
    final v = await chain.run('x', () async => 42);
    expect(v, 42);
    expect(chain.activeKeys, 0);
  });
}
