import 'dart:math' as math;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Моделі
// ─────────────────────────────────────────────────────────────────────────────

/// Тип події на зовнішньому кільці. Перелік розширюється, коли сервіс
/// визначить повний список.
enum KpiEventType { cash, card, iz, reimb, doc }

extension KpiEventTypeX on KpiEventType {
  String get label => switch (this) {
        KpiEventType.cash => 'Чек, готівка',
        KpiEventType.card => 'Чек, картка',
        KpiEventType.iz => 'Збір ІЗ',
        KpiEventType.reimb => 'Чек, Реімбурсація',
        KpiEventType.doc => 'АНЦДок',
      };

  Color get color => switch (this) {
        KpiEventType.cash => const Color(0xFF8FCB86),
        KpiEventType.card => const Color(0xFF5FB556),
        KpiEventType.iz => const Color(0xFF5B9BE0),
        KpiEventType.reimb => const Color(0xFFF2C94C),
        KpiEventType.doc => const Color(0xFFB59BE0),
      };
}

/// Подія зміни: хвилина від опівночі + тип.
class KpiActivityEvent {
  final int minute;
  final KpiEventType type;
  const KpiActivityEvent(this.minute, this.type);
}

/// Інтервал присутності клієнтів у торговому залі (хвилини від опівночі).
class KpiPresence {
  final int from;
  final int to;
  const KpiPresence(this.from, this.to);
  int get minutes => to - from;
}

/// Дані для кілець «Активність» за один день.
class KpiActivityData {
  final int shiftStart; // хв від опівночі
  final int shiftEnd;
  final int? now; // null = день завершено (минулий)
  final List<KpiActivityEvent> events;
  final List<KpiPresence> presence;

  const KpiActivityData({
    required this.shiftStart,
    required this.shiftEnd,
    this.now,
    required this.events,
    required this.presence,
  });

  /// Межа заповнення: «зараз» для сьогодні, кінець зміни для минулого дня.
  int get fillTo => now ?? shiftEnd;
}

// ─────────────────────────────────────────────────────────────────────────────
// Віджет
// ─────────────────────────────────────────────────────────────────────────────

/// «Активність»: ¾-дуга зміни (початок зліва внизу → кінець справа внизу).
/// Зовнішнє кільце — події (рисочки кольором за типом), внутрішнє —
/// присутність клієнтів у залі (фіолетовий), темніший фіолетовий — клієнти
/// були, а подій ≥ [idleMinutes] хв не було. Підказка — лише при наведенні.
class KpiActivityRing extends StatefulWidget {
  final KpiActivityData data;

  /// Хвилин без жодної події при клієнтах у залі = «без обслуговування».
  final int idleMinutes;

  const KpiActivityRing({super.key, required this.data, this.idleMinutes = 8});

  static const presenceColor = Color(0xFFC4B5FD);
  static const idleColor = Color(0xFF7C3AED);

  @override
  State<KpiActivityRing> createState() => _KpiActivityRingState();
}

class _KpiActivityRingState extends State<KpiActivityRing> {
  String? _tip;
  Offset? _tipAt;

  late _RingGeometry _geo;

  /// Періоди присутності з позначкою «без обслуговування».
  List<(KpiPresence, bool)> get _presence {
    final d = widget.data;
    return [
      for (final p in d.presence)
        if (p.from <= d.fillTo)
          (
            KpiPresence(p.from, math.min(p.to, d.fillTo)),
            !d.events.any((e) => e.minute >= p.from && e.minute <= p.to) &&
                math.min(p.to, d.fillTo) - p.from >= widget.idleMinutes,
          ),
    ];
  }

  int get _idleMinutes =>
      _presence.where((p) => p.$2).fold(0, (s, p) => s + p.$1.minutes);
  int get _idleCount => _presence.where((p) => p.$2).length;

  void _hover(Offset local) {
    final hit = _geo.hitTest(local, widget.data, _presence);
    if (hit?.$1 != _tip || hit?.$2 != _tipAt) {
      setState(() {
        _tip = hit?.$1;
        _tipAt = hit?.$2;
      });
    }
  }

  void _clear() {
    if (_tip != null) setState(() => _tip = null);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final presence = _presence;
    final counts = <KpiEventType, int>{};
    for (final e in d.events) {
      counts[e.type] = (counts[e.type] ?? 0) + 1;
    }
    final idleMin = _idleMinutes;
    final idleN = _idleCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = w * 274 / 320;
            _geo = _RingGeometry(Size(w, h));
            return SizedBox(
              height: h,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: MouseRegion(
                      onHover: (e) => _hover(e.localPosition),
                      onExit: (_) => _clear(),
                      child: GestureDetector(
                        onTapDown: (e) => _hover(e.localPosition),
                        child: CustomPaint(
                          painter: _RingPainter(
                            data: d,
                            presence: presence,
                            geo: _geo,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Центр: кількість подій + хвилини без обслуговування.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: h * 0.40,
                    child: IgnorePointer(
                      child: Column(
                        children: [
                          Text(
                            '${d.events.length}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: Color(0xFF1C1C2E),
                            ),
                          ),
                          const Text(
                            'подій за зміну',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF6B7280)),
                          ),
                          if (idleN > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '$idleMin хв без обслуговування',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: KpiActivityRing.idleColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_tip != null && _tipAt != null)
                    Positioned(
                      left: (_tipAt!.dx - 90).clamp(0.0, w - 180),
                      top: (_tipAt!.dy - 40).clamp(0.0, h),
                      width: 180,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFFE5E7EB)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              _tip!,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF1C1C2E)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final t in KpiEventType.values)
              _LegendDot(
                color: t.color,
                label:
                    '${t.label}${counts[t] != null ? ' · ${counts[t]}' : ''}',
              ),
            const _LegendDot(
                color: KpiActivityRing.presenceColor, label: 'Клієнти в залі'),
            _LegendDot(
              color: KpiActivityRing.idleColor,
              label: 'Без обслуговування${idleN > 0 ? ' · $idleN' : ''}',
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Геометрія й малювання
// ─────────────────────────────────────────────────────────────────────────────

String kpiHhmm(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

class _RingGeometry {
  final Size size;
  late final double scale = size.width / 320;
  late final Offset center = Offset(160 * scale, 150 * scale);
  late final double r = 108 * scale; // радіус зовнішнього кільця (по центру)
  late final double w = 26 * scale; // товщина зовнішнього
  late final double rIn = r - w / 2 - 9 * scale; // радіус внутрішнього
  late final double wIn = 8 * scale;
  static const a0 = 3 * math.pi / 4; // 135°
  static const sweep = 3 * math.pi / 2; // 270°

  _RingGeometry(this.size);

  double angleOf(int minute, KpiActivityData d) =>
      a0 + sweep * (minute - d.shiftStart) / (d.shiftEnd - d.shiftStart);

  Offset pt(double a, double rad) =>
      center + Offset(math.cos(a) * rad, math.sin(a) * rad);

  Offset pinAt(double a) => pt(a, r + w / 2 + 16 * scale);

  /// Що під курсором: (підказка, точка для підказки) або null.
  (String, Offset)? hitTest(
    Offset p,
    KpiActivityData d,
    List<(KpiPresence, bool)> presence,
  ) {
    // Маркери початку/кінця.
    final startPin = pinAt(a0);
    final endPin = pinAt(a0 + sweep);
    if ((p - startPin).distance <= 9 * scale) {
      return ('Початок зміни, ${kpiHhmm(d.shiftStart)}', startPin);
    }
    if ((p - endPin).distance <= 9 * scale) {
      return ('Кінець зміни, ${kpiHhmm(d.shiftEnd)}', endPin);
    }

    final v = p - center;
    final dist = v.distance;
    var a = math.atan2(v.dy, v.dx);
    if (a < a0) a += 2 * math.pi;
    if (a < a0 || a > a0 + sweep) return null;

    // Зовнішнє кільце: найближча подія в межах ~2.5°.
    if ((dist - r).abs() <= w / 2 + 4 * scale) {
      if (d.now != null) {
        final nowA = angleOf(d.now!, d);
        if ((a - nowA).abs() < 0.02) {
          return ('Зараз, ${kpiHhmm(d.now!)}', pt(nowA, r));
        }
      }
      KpiActivityEvent? best;
      var bestDiff = 0.045;
      for (final e in d.events) {
        final diff = (angleOf(e.minute, d) - a).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          best = e;
        }
      }
      if (best != null) {
        return (
          '${best.type.label}, ${kpiHhmm(best.minute)}',
          pt(angleOf(best.minute, d), r),
        );
      }
      return null;
    }

    // Внутрішнє кільце: інтервал присутності, що містить кут.
    if ((dist - rIn).abs() <= wIn / 2 + 4 * scale) {
      for (final (pr, idle) in presence) {
        final from = angleOf(pr.from, d), to = angleOf(pr.to, d);
        if (a >= from && a <= to) {
          final span = '${kpiHhmm(pr.from)}–${kpiHhmm(pr.to)}';
          return (
            idle
                ? 'Клієнти в залі без обслуговування, $span (${pr.minutes} хв)'
                : 'Клієнти в залі, $span',
            pt((from + to) / 2, rIn),
          );
        }
      }
    }
    return null;
  }
}

class _RingPainter extends CustomPainter {
  final KpiActivityData data;
  final List<(KpiPresence, bool)> presence;
  final _RingGeometry geo;

  const _RingPainter({
    required this.data,
    required this.presence,
    required this.geo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final d = data;
    final outerRect = Rect.fromCircle(center: geo.center, radius: geo.r);
    final innerRect = Rect.fromCircle(center: geo.center, radius: geo.rIn);

    // Фонові дуги.
    canvas.drawArc(
      outerRect,
      _RingGeometry.a0,
      _RingGeometry.sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = geo.w
        ..color = const Color(0xFFEEF0F3),
    );
    canvas.drawArc(
      innerRect,
      _RingGeometry.a0,
      _RingGeometry.sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = geo.wIn
        ..color = const Color(0xFFF4F5F8),
    );

    // Внутрішнє кільце: присутність клієнтів.
    for (final (pr, idle) in presence) {
      final from = geo.angleOf(pr.from, d);
      final to = geo.angleOf(pr.to, d);
      canvas.drawArc(
        innerRect,
        from,
        to - from,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = geo.wIn
          ..color =
              idle ? KpiActivityRing.idleColor : KpiActivityRing.presenceColor,
      );
    }

    // Зовнішнє кільце: рисочки подій.
    final tick = Paint()
      ..strokeWidth = 2.5 * geo.scale
      ..strokeCap = StrokeCap.round;
    for (final e in d.events) {
      final a = geo.angleOf(e.minute, d);
      canvas.drawLine(
        geo.pt(a, geo.r - geo.w / 2 + 2 * geo.scale),
        geo.pt(a, geo.r + geo.w / 2 - 2 * geo.scale),
        tick..color = e.type.color,
      );
    }

    // «Зараз» — тонка темна риска через кільце.
    if (d.now != null) {
      final a = geo.angleOf(d.now!, d);
      canvas.drawLine(
        geo.pt(a, geo.r - geo.w / 2 - 2 * geo.scale),
        geo.pt(a, geo.r + geo.w / 2 + 2 * geo.scale),
        Paint()
          ..strokeWidth = 1.5 * geo.scale
          ..color = const Color(0xFF1C1C2E),
      );
    }

    // Маркери початку (зелений) і кінця (сірий) з «ніжкою» назовні.
    _pin(canvas, _RingGeometry.a0, const Color(0xFF5FB556));
    _pin(canvas, _RingGeometry.a0 + _RingGeometry.sweep,
        const Color(0xFF9CA3AF));

    // Підписи часу під маркерами.
    _label(canvas, kpiHhmm(d.shiftStart),
        geo.pt(_RingGeometry.a0, geo.r + geo.w / 2 + 36 * geo.scale));
    _label(
        canvas,
        kpiHhmm(d.shiftEnd),
        geo.pt(_RingGeometry.a0 + _RingGeometry.sweep,
            geo.r + geo.w / 2 + 36 * geo.scale));
  }

  void _pin(Canvas canvas, double a, Color color) {
    final p1 = geo.pt(a, geo.r + geo.w / 2 + 1 * geo.scale);
    final p2 = geo.pinAt(a);
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..strokeWidth = 1.5 * geo.scale
        ..color = const Color(0xFF9CA3AF),
    );
    canvas.drawCircle(p2, 5 * geo.scale, Paint()..color = color);
  }

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10 * geo.scale, color: const Color(0xFF6B7280)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.data != data || old.presence != presence || old.geo.size != geo.size;
}
