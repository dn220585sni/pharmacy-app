import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Масштаб усього інтерфейсу — як зум у браузері: шрифти, колонки таблиці,
/// іконки й відступи ростуть разом, тож пропорції не ламаються і назви
/// виробників не обрізає (на відміну від правки ~500 `fontSize` вручну).
///
/// Навіщо: ~1000 аптек мають 22" 1920×1080 при масштабі Windows 100%
/// (≈100 ppi), фармацевт дивиться з ~1 м. Без масштабу назва препарату
/// (13,5 px) — це ≈8 кутових хвилин при нормі ≥16′ (ISO 9241-303).
/// 125% обрано 11.09.2026 на симуляції.
///
/// Ctrl + / Ctrl − — крок; Ctrl 0 — 100%, тобто вигляд до 11.09 («відкат»
/// прямо на робочому місці). Вибір зберігається на цьому ПК (`ui_zoom.txt`).
///
/// Як працює: застосунок бачить зменшений `MediaQuery.size` (1920×1017 →
/// 1536×814 при 125%) і верстається під нього, а `FittedBox` розтягує
/// результат на все вікно. Діалоги й меню масштабуються теж — вони в
/// Navigator під цим віджетом.
class UiZoom extends StatefulWidget {
  const UiZoom({super.key, required this.child});

  final Widget child;

  static const levels = [1.0, 1.1, 1.2, 1.25, 1.3, 1.4, 1.5];
  static const defaultZoom = 1.25;
  static const _fileName = 'ui_zoom.txt';

  static double _initial = defaultZoom;

  /// Викликати в `main()` до `runApp`, щоб перший кадр одразу був у
  /// збереженому масштабі — без стрибка 125% → свій.
  static Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final v = double.tryParse((await f.readAsString()).trim());
        if (v != null) _initial = _nearest(v);
      }
    } catch (_) {
      // Немає файлу/доступу — лишаємо 125%.
    }
  }

  static double _nearest(double v) => levels
      .reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  @override
  State<UiZoom> createState() => _UiZoomState();
}

class _UiZoomState extends State<UiZoom> {
  double _zoom = UiZoom._initial;
  bool _badge = false;
  Timer? _badgeTimer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _badgeTimer?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    const levels = UiZoom.levels;
    final i = levels.indexOf(_zoom);
    final k = e.logicalKey;
    double? next;
    if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      next = levels[(i + 1).clamp(0, levels.length - 1)];
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      next = levels[(i - 1).clamp(0, levels.length - 1)];
    } else if (k == LogicalKeyboardKey.digit0 ||
        k == LogicalKeyboardKey.numpad0) {
      next = 1.0;
    }
    if (next == null) return false;
    _set(next);
    return true;
  }

  void _set(double z) {
    _badgeTimer?.cancel();
    setState(() {
      _zoom = z;
      _badge = true;
    });
    _badgeTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _badge = false);
    });
    unawaited(_save(z));
  }

  static Future<void> _save(double z) async {
    try {
      await (await UiZoom._file()).writeAsString('$z', flush: true);
    } catch (_) {
      // Не зберіглось — після рестарту буде 125%, не критично.
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final logical = mq.size / _zoom;

    // Дерево однакове при будь-якому масштабі (і при 100% теж) — інакше зміна
    // масштабу перебудувала б застосунок з нуля і скинула кошик.
    return Stack(
      children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: MediaQuery(
              data: mq.copyWith(
                size: logical,
                devicePixelRatio: mq.devicePixelRatio * _zoom,
              ),
              child: SizedBox.fromSize(size: logical, child: widget.child),
            ),
          ),
        ),
        if (_badge)
          Positioned(
            left: 16,
            bottom: 16,
            child: IgnorePointer(
              child: Material(
                color: const Color(0xE6111827),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    'Масштаб ${(_zoom * 100).round()}%   ·   '
                    'Ctrl + / Ctrl −   ·   Ctrl 0 — 100%',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
