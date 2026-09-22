import 'dart:async';

/// Пріоритет запиту до Caché.
enum ApiPriority {
  /// Те, чого людина чекає просто зараз: пошук, кошик, ціни, каса, оплата.
  interactive,

  /// Фон: префетч акцій для таблиці/топ-500 тощо. Не має займати слоти,
  /// потрібні інтерактивним запитам.
  background,
}

/// Планувальник слотів до Caché (код-рев'ю 22.09, п.12).
///
/// Ліцензії Caché обмежені → не більше [maxConcurrent] одночасних запитів.
/// Раніше черга була одна, FIFO: префетч акцій батчами по 8 займав усі 3
/// слоти, і пошук ішов ДЕВ'ЯТИМ. Тепер:
/// - фон займає щонайбільше [maxBackground] слотів із [maxConcurrent];
/// - при звільненні слота спершу пускаємо інтерактивних, потім фон;
/// - фоновий запит, що застарів до старту ([isStale]), не виконується.
class ApiScheduler {
  ApiScheduler({this.maxConcurrent = 3, this.maxBackground = 1})
      : assert(maxBackground <= maxConcurrent);

  final int maxConcurrent;
  final int maxBackground;

  int _active = 0;
  int _activeBackground = 0;
  final _interactive = <_Waiter>[];
  final _background = <_Waiter>[];

  int get active => _active;
  int get activeBackground => _activeBackground;
  int get queuedInteractive => _interactive.length;
  int get queuedBackground => _background.length;

  bool _canStart(ApiPriority p) =>
      _active < maxConcurrent &&
      (p != ApiPriority.background || _activeBackground < maxBackground);

  void _start(ApiPriority p) {
    _active++;
    if (p == ApiPriority.background) _activeBackground++;
  }

  /// Дочекатись слота. `true` — слот отримано, після роботи ОБОВ'ЯЗКОВО
  /// [release]. `false` — запит скасовано як застарілий ще до старту
  /// (слот не займався, [release] не викликати).
  Future<bool> acquire(ApiPriority p, {bool Function()? isStale}) {
    if (isStale?.call() == true) return Future.value(false);
    if (_canStart(p)) {
      _start(p);
      return Future.value(true);
    }
    final w = _Waiter(p, isStale);
    (p == ApiPriority.background ? _background : _interactive).add(w);
    return w.completer.future;
  }

  void release(ApiPriority p) {
    _active--;
    if (p == ApiPriority.background) _activeBackground--;
    _dispatch();
  }

  void _dispatch() {
    while (_active < maxConcurrent) {
      final w = _next();
      if (w == null) break;
      if (w.isStale?.call() == true) {
        w.completer.complete(false);
        continue;
      }
      _start(w.priority);
      w.completer.complete(true);
    }
  }

  _Waiter? _next() {
    if (_interactive.isNotEmpty) return _interactive.removeAt(0);
    if (_background.isNotEmpty && _activeBackground < maxBackground) {
      return _background.removeAt(0);
    }
    return null;
  }
}

class _Waiter {
  _Waiter(this.priority, this.isStale);
  final ApiPriority priority;
  final bool Function()? isStale;
  final completer = Completer<bool>();
}
