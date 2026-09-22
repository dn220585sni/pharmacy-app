import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/api_scheduler.dart';

/// Код-рев'ю 22.09, п.12: пошук не має стояти в черзі за префетчем акцій.
void main() {
  test('фон займає не більше maxBackground слотів', () async {
    final s = ApiScheduler(maxConcurrent: 3, maxBackground: 1);
    expect(await s.acquire(ApiPriority.background), isTrue);
    final second = s.acquire(ApiPriority.background);
    expect(s.active, 1);
    expect(s.queuedBackground, 1);
    // Інтерактивні слоти вільні.
    expect(await s.acquire(ApiPriority.interactive), isTrue);
    expect(await s.acquire(ApiPriority.interactive), isTrue);
    expect(s.active, 3);
    s.release(ApiPriority.background);
    expect(await second, isTrue);
    expect(s.activeBackground, 1);
  });

  test('інтерактивний пускається перед фоновими з черги', () async {
    final s = ApiScheduler(maxConcurrent: 1, maxBackground: 1);
    expect(await s.acquire(ApiPriority.background), isTrue);
    final bg = s.acquire(ApiPriority.background);
    final ui = s.acquire(ApiPriority.interactive);
    final order = <String>[];
    unawaitedOrder(bg, 'bg', order);
    unawaitedOrder(ui, 'ui', order);
    s.release(ApiPriority.background);
    await ui;
    expect(order, ['ui']);
    s.release(ApiPriority.interactive);
    await bg;
    expect(order, ['ui', 'bg']);
  });

  test('застарілий фоновий запит не стартує', () async {
    final s = ApiScheduler(maxConcurrent: 1, maxBackground: 1);
    expect(await s.acquire(ApiPriority.interactive), isTrue);
    var gen = 1;
    final stale = s.acquire(ApiPriority.background, isStale: () => gen != 1);
    final fresh = s.acquire(ApiPriority.background, isStale: () => false);
    gen = 2; // результати пошуку змінились, поки чекали
    s.release(ApiPriority.interactive);
    expect(await stale, isFalse);
    expect(await fresh, isTrue);
    expect(s.active, 1);
  });

  test('уже застарілий не займає слот одразу', () async {
    final s = ApiScheduler();
    expect(await s.acquire(ApiPriority.background, isStale: () => true),
        isFalse);
    expect(s.active, 0);
  });
}

void unawaitedOrder(Future<bool> f, String tag, List<String> order) {
  f.then((_) => order.add(tag));
}
