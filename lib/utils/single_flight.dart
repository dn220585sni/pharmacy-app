import 'dart:async';

/// Одна активна операція: поки попередня не завершилась, [run] повертає її
/// ж future, а не стартує нову.
///
/// ⚠️ Навіщо окремий клас. Наївне
/// `return _f ??= _body();` з `finally { _f = null; }` усередині `_body`
/// ламається, коли тіло завершується БЕЗ жодного await: async-функція до
/// першого await виконується синхронно, тож `finally` обнуляє поле ще ДО
/// присвоєння, а потім туди лягає вже виконаний future — і всі наступні
/// виклики повертають його, нічого не роблячи. Так 22.09–25.09 не
/// відправлявся `SetBonusOpl`: бонус не потрапляв у сеанс, решта рахувалась
/// без списання (Микола 25.09).
class SingleFlight<T> {
  Future<T>? _inFlight;

  bool get isRunning => _inFlight != null;

  Future<T> run(Future<T> Function() body) {
    final existing = _inFlight;
    if (existing != null) return existing;
    late final Future<T> f;
    f = body().whenComplete(() {
      if (identical(_inFlight, f)) _inFlight = null;
    });
    _inFlight = f;
    return f;
  }
}
