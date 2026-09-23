import 'dart:async';

/// Виконати [body] для кожного елемента з не більше ніж [limit] одночасно,
/// зберігаючи порядок СТАРТУ. Помилка одного елемента не зупиняє решту
/// (обробляти всередині [body]). [shouldStop] перевіряється перед кожним
/// стартом: коли дані вже нікому не потрібні (відкрили інше замовлення),
/// решту не запускаємо.
Future<void> forEachLimited<T>(
  Iterable<T> items,
  int limit,
  Future<void> Function(T item) body, {
  bool Function()? shouldStop,
}) async {
  assert(limit > 0);
  final queue = List<T>.from(items);
  var next = 0;
  Future<void> worker() async {
    while (next < queue.length) {
      if (shouldStop?.call() == true) return;
      final item = queue[next++];
      try {
        await body(item);
      } catch (_) {
        // Тіло саме вирішує, що робити з помилкою; воркер живе далі.
      }
    }
  }

  final n = limit < queue.length ? limit : queue.length;
  await Future.wait(List.generate(n, (_) => worker()));
}
