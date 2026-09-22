import 'dart:async';

/// Черги асинхронних задач за ключем: задачі з одним ключем виконуються
/// строго послідовно (кожна стартує після завершення попередньої, навіть
/// якщо та впала), з різними ключами — паралельно.
///
/// Навіщо: серверні зміни однієї позиції кошика (sgVRoznSetLock) не можна
/// пускати паралельно — відповіді приходять у довільному порядку, і UI
/// розходиться з резервом на сервері (код-рев'ю 22.09, п.6). Тіло задачі
/// має рахувати бажаний стан у момент СТАРТУ, а не постановки в чергу.
class KeyedTaskChain {
  final _tails = <String, Future<void>>{};

  /// Скільки ключів зараз мають незавершені задачі (для діагностики/тестів).
  int get activeKeys => _tails.length;

  Future<T> run<T>(String key, Future<T> Function() body) async {
    final prev = _tails[key] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[key] = done.future;
    try {
      await prev;
      return await body();
    } finally {
      done.complete();
      if (identical(_tails[key], done.future)) _tails.remove(key);
    }
  }
}
