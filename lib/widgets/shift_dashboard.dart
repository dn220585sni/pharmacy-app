import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mock shift data (will be replaced by a service layer later)
// ─────────────────────────────────────────────────────────────────────────────

class _ShiftData {
  static const double turnoverFact = 3200;
  static const double turnoverPlan = 5000;
  static const int vtmFact = 10;
  static const int vtmPlan = 12;

  // null = no alert to show right now
  static const _AlertData? alert = _AlertData(
    type: _AlertType.warning,
    title: 'Показник Лайк нижче 70%',
    body:
        'Запитуйте номер телефону у кожного клієнта — це нараховані бонуси і '
        'шанс повернути його до вас. Кожен чек з номером покращує ваш показник.',
  );

  static const List<_MetricRow> allMetrics = [
    _MetricRow('Чеків за зміну', '18', _RowStatus.neutral),
    _MetricRow('Середній чек', '177.78 грн', _RowStatus.neutral),
    _MetricRow('Показник Лайк', '62%', _RowStatus.bad),
    _MetricRow('ТПК (з клієнтів)', '44%', _RowStatus.warning),
    _MetricRow('Препаратів відпущено', '24 уп.', _RowStatus.neutral),
    _MetricRow('Повернень', '0', _RowStatus.good),
  ];
}

enum _AlertType { warning, tip, success }

enum _RowStatus { neutral, good, warning, bad }

class _AlertData {
  final _AlertType type;
  final String title;
  final String body;
  const _AlertData({required this.type, required this.title, required this.body});
}

class _MetricRow {
  final String label;
  final String value;
  final _RowStatus status;
  const _MetricRow(this.label, this.value, this.status);
}

// ─────────────────────────────────────────────────────────────────────────────
// ShiftDashboard
// ─────────────────────────────────────────────────────────────────────────────

class ShiftDashboard extends StatefulWidget {
  const ShiftDashboard({super.key});

  @override
  State<ShiftDashboard> createState() => _ShiftDashboardState();
}

class _ShiftDashboardState extends State<ShiftDashboard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionLabel('Показники зміни', Icons.bar_chart_rounded),
          const SizedBox(height: 14),
          _buildKpiBar(
            label: 'Товарообіг',
            fact: _ShiftData.turnoverFact,
            plan: _ShiftData.turnoverPlan,
            factLabel: '3 200 грн',
            planLabel: '5 000 грн',
          ),
          const SizedBox(height: 14),
          _buildKpiBar(
            label: 'Продаж ВТМ',
            fact: _ShiftData.vtmFact.toDouble(),
            plan: _ShiftData.vtmPlan.toDouble(),
            factLabel: '10 поз',
            planLabel: '12 поз',
          ),
          if (_ShiftData.alert != null) ...[
            const SizedBox(height: 20),
            _buildAlert(_ShiftData.alert!),
          ],
          const SizedBox(height: 12),
          _buildExpandable(),
        ],
      ),
    );
  }

  // ── Section label ───────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF9CA3AF),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ── KPI progress bar ────────────────────────────────────────────────────────

  Widget _buildKpiBar({
    required String label,
    required double fact,
    required double plan,
    required String factLabel,
    required String planLabel,
  }) {
    final ratio = (fact / plan).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();
    final color = _progressColor(ratio);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C2E),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 9,
            backgroundColor: const Color(0xFFF0F2F5),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Text(
              factLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
            const Spacer(),
            Text(
              'план $planLabel',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ],
    );
  }

  // ── Alert card ──────────────────────────────────────────────────────────────

  Widget _buildAlert(_AlertData alert) {
    final (bgColor, accentColor, icon) = switch (alert.type) {
      _AlertType.tip => (
          const Color(0xFFEFF6FF),
          const Color(0xFF4F6EF7),
          Icons.lightbulb_outline_rounded,
        ),
      _AlertType.success => (
          const Color(0xFFF0FDF4),
          const Color(0xFF22C55E),
          Icons.check_circle_outline_rounded,
        ),
      _AlertType.warning => (
          const Color(0xFFFFFBEB),
          const Color(0xFFF59E0B),
          Icons.warning_amber_rounded,
        ),
    };

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent strip
            Container(width: 4, color: accentColor),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 14, color: accentColor),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            alert.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      alert.body,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF374151),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Expandable all-metrics block ────────────────────────────────────────────

  Widget _buildExpandable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toggle button
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Text(
                  'Всі показники зміни',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded content
        if (_expanded) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < _ShiftData.allMetrics.length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
                  _buildMetricRow(_ShiftData.allMetrics[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricRow(_MetricRow row) {
    final valueColor = switch (row.status) {
      _RowStatus.good => const Color(0xFF22C55E),
      _RowStatus.warning => const Color(0xFFF59E0B),
      _RowStatus.bad => const Color(0xFFEF4444),
      _RowStatus.neutral => const Color(0xFF1C1C2E),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Text(
            row.label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const Spacer(),
          Text(
            row.value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Color _progressColor(double ratio) {
    if (ratio >= 0.90) return const Color(0xFF22C55E);
    if (ratio >= 0.70) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}
