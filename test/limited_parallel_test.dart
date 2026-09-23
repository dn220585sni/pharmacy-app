import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/utils/limited_parallel.dart';

/// Відгук 23.09, п.3: збагачення позицій замовлення має йти паралельно з
/// обмеженням, а не послідовно.
void main() {
  test('одночасно не більше limit', () async {
    var running = 0, peak = 0;
    await forEachLimited(List.generate(10, (i) => i), 3, (i) async {
      running++;
      if (running > peak) peak = running;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      running--;
    });
    expect(peak, 3);
  });

  test('усі елементи оброблено, порядок старту збережено', () async {
    final started = <int>[];
    await forEachLimited(List.generate(7, (i) => i), 2, (i) async {
      started.add(i);
      await Future<void>.delayed(Duration(milliseconds: i.isEven ? 6 : 2));
    });
    expect(started, [0, 1, 2, 3, 4, 5, 6]);
  });

  test('помилка одного не зупиняє решту', () async {
    final done = <int>[];
    await forEachLimited([1, 2, 3], 2, (i) async {
      if (i == 2) throw StateError('boom');
      done.add(i);
    });
    expect(done, [1, 3]);
  });

  test('shouldStop зупиняє нові старти', () async {
    var stop = false;
    final done = <int>[];
    await forEachLimited(List.generate(6, (i) => i), 1, (i) async {
      done.add(i);
      if (i == 2) stop = true;
    }, shouldStop: () => stop);
    expect(done, [0, 1, 2]);
  });

  test('порожній список нічого не робить', () async {
    var calls = 0;
    await forEachLimited(<int>[], 3, (_) async => calls++);
    expect(calls, 0);
  });
}
