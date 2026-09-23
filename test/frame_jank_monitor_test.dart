import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/frame_jank_monitor.dart';

void main() {
  test('без довгих кадрів підсумку немає', () {
    final w = JankWindow();
    for (var i = 0; i < 100; i++) {
      w.add(total: const Duration(milliseconds: 16));
    }
    expect(w.frames, 100);
    expect(w.summary(), isNull);
  });

  test('рахує довгі кадри, найдовший з build/raster', () {
    final w = JankWindow();
    w.add(total: const Duration(milliseconds: 16));
    w.add(
        total: const Duration(milliseconds: 40),
        build: const Duration(milliseconds: 30),
        raster: const Duration(milliseconds: 8));
    w.add(
        total: const Duration(milliseconds: 90),
        build: const Duration(milliseconds: 70),
        raster: const Duration(milliseconds: 15));
    expect(w.jank, 2);
    final s = w.summary()!;
    expect(s, contains('2 з 3 кадрів'));
    expect(s, contains('найдовший 90 мс'));
    expect(s, contains('build 70'));
    expect(s, contains('raster 15'));
    expect(s, contains('разом 130 мс'));
  });

  test('reset очищає вікно', () {
    final w = JankWindow();
    w.add(total: const Duration(milliseconds: 50));
    w.reset();
    expect(w.frames, 0);
    expect(w.summary(), isNull);
  });
}
