import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'fiscal_log.dart';

/// Збирає довгі кадри й раз на хвилину пише підсумок у fiscal_log
/// (відгук 23.09: «вплив на плавність інтерфейсу ще потрібно виміряти»).
///
/// Поріг 32 мс = два пропущені кадри при 60 Гц. Пишемо лише коли такі кадри
/// були: тихий екран не засмічує журнал. Лише release/profile: у debug
/// цифри кадрів нічого не означають.
class FrameJankMonitor {
  FrameJankMonitor._();
  static final instance = FrameJankMonitor._();

  static const jankThreshold = Duration(milliseconds: 32);
  static const reportEvery = Duration(minutes: 1);

  final _window = JankWindow();
  DateTime _windowStart = DateTime.now();
  bool _installed = false;

  void install() {
    if (_installed || kDebugMode) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _window.add(
        total: t.totalSpan,
        build: t.buildDuration,
        raster: t.rasterDuration,
      );
    }
    final now = DateTime.now();
    if (now.difference(_windowStart) >= reportEvery) {
      final line = _window.summary();
      if (line != null) FiscalLog.log('КАДРИ: $line');
      _window.reset();
      _windowStart = now;
    }
  }
}

/// Агрегат довгих кадрів за вікно часу. Окремо від Flutter-типів, щоб
/// покривався тестами.
class JankWindow {
  JankWindow({this.threshold = FrameJankMonitor.jankThreshold});

  final Duration threshold;
  int frames = 0;
  int jank = 0;
  Duration worst = Duration.zero;
  Duration worstBuild = Duration.zero;
  Duration worstRaster = Duration.zero;
  Duration jankTotal = Duration.zero;

  void add({required Duration total, Duration? build, Duration? raster}) {
    frames++;
    if (total < threshold) return;
    jank++;
    jankTotal += total;
    if (total > worst) {
      worst = total;
      worstBuild = build ?? Duration.zero;
      worstRaster = raster ?? Duration.zero;
    }
  }

  /// `null`: довгих кадрів не було, писати нічого.
  String? summary() {
    if (jank == 0) return null;
    return 'за хвилину $jank з $frames кадрів довші за '
        '${threshold.inMilliseconds} мс (разом ${jankTotal.inMilliseconds} мс); '
        'найдовший ${worst.inMilliseconds} мс '
        '(build ${worstBuild.inMilliseconds}, raster ${worstRaster.inMilliseconds})';
  }

  void reset() {
    frames = 0;
    jank = 0;
    worst = Duration.zero;
    worstBuild = Duration.zero;
    worstRaster = Duration.zero;
    jankTotal = Duration.zero;
  }
}
