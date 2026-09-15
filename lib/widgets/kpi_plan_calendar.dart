import 'package:flutter/material.dart';

/// Календар місяця з виконанням денного плану.
///
/// Зелений кружечок — план дня виконано, сірий — ні, сьогодні — синій із
/// кільцем (акцент завжди на поточній даті), майбутні дні — без кружечка.
/// Клік по минулому дню або сьогодні → [onSelect]; вибраний день (якщо не
/// сьогодні) отримує синє кільце.
class KpiPlanCalendar extends StatelessWidget {
  /// Факт по днях місяця (індекс 0 = 1-ше число). Може бути коротшим за місяць.
  final List<double> dayFacts;

  /// Денний план (один на місяць).
  final double dayPlan;

  /// Сьогодні — визначає місяць, «сьогодні» й межу майбутнього.
  final DateTime today;

  /// Вибраний день (1..31), за замовчуванням сьогодні.
  final int selectedDay;

  final ValueChanged<int> onSelect;

  const KpiPlanCalendar({
    super.key,
    required this.dayFacts,
    required this.dayPlan,
    required this.today,
    required this.selectedDay,
    required this.onSelect,
  });

  static const _green = Color(0xFF22C55E);
  static const _grey = Color(0xFFE5E7EB);
  static const _blue = Color(0xFF1E7DC8);
  static const _muted = Color(0xFF6B7280);
  static const _state = Color(0xFF9CA3AF);
  static const _future = Color(0xFFC4C9D2);

  bool isMet(int day) =>
      day - 1 < dayFacts.length && dayFacts[day - 1] >= dayPlan;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(today.year, today.month, 1);
    final lead = (first.weekday - 1) % 7; // зсув до понеділка
    final total = DateTime(today.year, today.month + 1, 0).day;
    const dows = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];

    final cells = <Widget>[
      for (final d in dows)
        Center(
          child: Text(
            d.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              color: _state,
              letterSpacing: 0.3,
            ),
          ),
        ),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var day = 1; day <= total; day++) _cell(day),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 4,
          childAspectRatio: 1.25,
          children: cells,
        ),
        const SizedBox(height: 8),
        const Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _LegendDot(color: _green, label: 'план виконано'),
            _LegendDot(color: _grey, label: 'не виконано'),
            _LegendDot(color: _blue, label: 'сьогодні'),
          ],
        ),
      ],
    );
  }

  Widget _cell(int day) {
    final isToday = day == today.day;
    final isFuture = day > today.day;
    final met = !isFuture && !isToday && isMet(day);
    final selected = day == selectedDay && !isToday;

    final Color bg;
    final Color fg;
    if (isToday) {
      bg = _blue;
      fg = Colors.white;
    } else if (isFuture) {
      bg = Colors.transparent;
      fg = _future;
    } else if (met) {
      bg = _green;
      fg = Colors.white;
    } else {
      bg = _grey;
      fg = _muted;
    }

    final fact = day - 1 < dayFacts.length ? dayFacts[day - 1] : null;
    final circle = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: (isToday || selected)
            ? Border.all(color: Colors.white, width: 2)
            : null,
        boxShadow: (isToday || selected)
            ? const [BoxShadow(color: _blue, spreadRadius: 2)]
            : null,
      ),
      child: Text(
        '$day',
        style: TextStyle(
          fontSize: 12,
          fontWeight: isToday
              ? FontWeight.w800
              : isFuture
                  ? FontWeight.w500
                  : FontWeight.w600,
          color: fg,
        ),
      ),
    );

    if (isFuture) return Center(child: circle);
    return Center(
      child: Tooltip(
        message: fact == null
            ? ''
            : '${isToday ? 'сьогодні: ' : ''}${_int(fact)} з ${_int(dayPlan)}'
                '${met ? ' ✓' : ''}',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          key: ValueKey('cal-day-$day'),
          customBorder: const CircleBorder(),
          onTap: () => onSelect(day),
          child: circle,
        ),
      ),
    );
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
