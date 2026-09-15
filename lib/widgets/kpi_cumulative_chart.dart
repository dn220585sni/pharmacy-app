import 'package:flutter/material.dart';

/// Накопичення за місяць: факт наростаючим підсумком (синя область + лінія)
/// проти плану наростаючим підсумком (пунктир від 0 до [monthPlan] на
/// останній день місяця). Точка з підписом — сьогодні.
///
/// План у моку розкладено по днях лінійно; з сервісом лінія плану може бути
/// ламаною (за плановими годинами) — тоді передати [planDays].
class KpiCumulativeChart extends StatelessWidget {
  /// Факт по днях місяця, грн (індекс 0 = 1-ше число).
  final List<double> dayFacts;
  final double monthPlan;

  /// План по днях (не накопичений); null = рівномірно.
  final List<double>? planDays;
  final DateTime today;
  final double height;

  const KpiCumulativeChart({
    super.key,
    required this.dayFacts,
    required this.monthPlan,
    this.planDays,
    required this.today,
    this.height = 110,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CumPainter(
          dayFacts: dayFacts,
          monthPlan: monthPlan,
          planDays: planDays,
          today: today,
        ),
      ),
    );
  }
}

class _CumPainter extends CustomPainter {
  final List<double> dayFacts;
  final double monthPlan;
  final List<double>? planDays;
  final DateTime today;

  static const _blue = Color(0xFF1E7DC8);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);
  static const _state = Color(0xFF9CA3AF);
  static const _monthsShort = [
    'січ', 'лют', 'бер', 'кві', 'тра', 'чер', 'лип', 'сер', 'вер', 'жов',
    'лис', 'гру',
  ];

  const _CumPainter({
    required this.dayFacts,
    required this.monthPlan,
    required this.planDays,
    required this.today,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padT = 12.0, padB = 14.0;
    final w = size.width;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final td = today.day.clamp(1, daysInMonth);

    // Накопичений факт до сьогодні.
    final cum = <double>[];
    var s = 0.0;
    for (var i = 0; i < td; i++) {
      s += i < dayFacts.length ? dayFacts[i] : 0;
      cum.add(s);
    }
    // Накопичений план по днях (лінійно або за planDays).
    final cumPlan = <double>[];
    var p = 0.0;
    for (var i = 0; i < daysInMonth; i++) {
      p += planDays != null && i < planDays!.length
          ? planDays![i]
          : monthPlan / daysInMonth;
      cumPlan.add(p);
    }
    final max = (monthPlan > s ? monthPlan : s) * 1.08;
    double x(num day) => w * day / daysInMonth;
    double y(double v) => padT + (size.height - padT - padB) * (1 - v / max);
    final y0 = y(0);

    // Базова лінія.
    canvas.drawLine(
      Offset(0, y0),
      Offset(w, y0),
      Paint()
        ..color = _border
        ..strokeWidth = 1,
    );

    // Пунктир плану наростаючим підсумком.
    final planPaint = Paint()
      ..color = _state
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final planPath = Path()..moveTo(0, y0);
    for (var i = 0; i < daysInMonth; i++) {
      planPath.lineTo(x(i + 1), y(cumPlan[i]));
    }
    _drawDashed(canvas, planPath, planPaint, 5, 4);

    // Факт: область + лінія.
    final line = Path()..moveTo(0, y0);
    for (var i = 0; i < td; i++) {
      line.lineTo(x(i + 1), y(cum[i]));
    }
    final area = Path.from(line)
      ..lineTo(x(td), y0)
      ..close();
    canvas.drawPath(area, Paint()..color = _blue.withValues(alpha: 0.14));
    canvas.drawPath(
      line,
      Paint()
        ..color = _blue
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Сьогодні: вертикальний пунктир + точка + підпис зліва від точки.
    final tx = x(td), ty = y(s);
    _drawDashed(
      canvas,
      Path()
        ..moveTo(tx, y0)
        ..lineTo(tx, ty + 6),
      Paint()
        ..color = _blue
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
      2,
      2,
    );
    canvas.drawCircle(Offset(tx, ty), 5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(tx, ty), 4, Paint()..color = _blue);
    final met = s >= monthPlan;
    _text(
      canvas,
      '${_int(s)} ₴${met ? ' ✓' : ''}',
      Offset(tx - 8, ty - 8),
      const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _blue),
      alignRight: true,
    );

    // Вісь: 1 <міс>, сьогодні, останній день.
    const axis = TextStyle(fontSize: 10, color: _muted);
    final m = _monthsShort[today.month - 1];
    _text(canvas, '1 $m', Offset(0, size.height - 11), axis);
    _text(canvas, 'сьогодні', Offset(tx, size.height - 11), axis,
        center: true);
    _text(canvas, '$daysInMonth $m', Offset(w, size.height - 11), axis,
        alignRight: true);
  }

  void _drawDashed(
      Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += dash + gap;
      }
    }
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style,
      {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight
        ? at.dx - tp.width
        : center
            ? at.dx - tp.width / 2
            : at.dx;
    tp.paint(canvas, Offset(dx, at.dy - (alignRight && !center ? tp.height / 2 : 0)));
    tp.dispose();
  }

  static String _int(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  bool shouldRepaint(_CumPainter old) =>
      old.dayFacts != dayFacts ||
      old.monthPlan != monthPlan ||
      old.planDays != planDays ||
      old.today != today;
}
