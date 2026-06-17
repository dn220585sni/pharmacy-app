import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mock shift data (will be replaced by a service layer later)
// ─────────────────────────────────────────────────────────────────────────────

class _ShiftData {
  static const double turnoverFact = 3200;
  static const double turnoverPlan = 5000;
  static const double vtmFact = 2100;   // UAH
  static const double vtmPlan = 3000;   // UAH

  // set to null to hide the alert
  static const _AlertData alert = _AlertData(
    type: _AlertType.warning,
    title: 'Показник Лайк нижче 70%',
    body:
        'Запитуйте номер телефону у кожного клієнта — це нараховані бонуси і '
        'шанс повернути його до вас. Кожен чек з номером покращує ваш показник.',
  );

  static const List<_MetricRow> allMetrics = [
    _MetricRow('Чеків за зміну', '18', _RowStatus.neutral),
    _MetricRow('Середній чек', '177,78', _RowStatus.neutral),
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
  /// Total amount earned since shift start (accumulates with each payment).
  final double earnedAmount;

  const ShiftDashboard({super.key, this.earnedAmount = 0.0});

  @override
  State<ShiftDashboard> createState() => _ShiftDashboardState();
}

class _ShiftDashboardState extends State<ShiftDashboard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  // ── Earned counter animation ─────────────────────────────────────────────
  late AnimationController _earningCtrl;
  late Animation<double> _earningAnim;

  @override
  void initState() {
    super.initState();
    _earningCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _earningAnim = Tween<double>(
      begin: 0.0,
      end: widget.earnedAmount,
    ).animate(CurvedAnimation(parent: _earningCtrl, curve: Curves.easeOut));

    // Animate in on first build if there's already a value
    if (widget.earnedAmount > 0) _earningCtrl.forward();
  }

  @override
  void didUpdateWidget(ShiftDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Animate the counter from the previous value to the new one
    if (oldWidget.earnedAmount != widget.earnedAmount) {
      _earningAnim = Tween<double>(
        begin: oldWidget.earnedAmount,
        end: widget.earnedAmount,
      ).animate(CurvedAnimation(parent: _earningCtrl, curve: Curves.easeOut));
      _earningCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _earningCtrl.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Alert appears only after the first payment has been made
          if (widget.earnedAmount > 0) ...[
            _buildSectionLabel('Зверніть увагу', Icons.info_outline_rounded),
            const SizedBox(height: 10),
            _buildAlert(_ShiftData.alert),
            const SizedBox(height: 16),
          ],
          _buildSectionLabel('Показники за зміну', Icons.bar_chart_rounded),
          const SizedBox(height: 14),

          // ── Earned counter (no goal — just current result) ──────────────
          _buildEarnedCard(),
          const SizedBox(height: 14),

          _buildKpiBar(
            label: 'Товарообіг',
            fact: _ShiftData.turnoverFact,
            plan: _ShiftData.turnoverPlan,
            factLabel: '3 200',
            planLabel: '5 000',
          ),
          const SizedBox(height: 14),
          _buildKpiBar(
            label: 'Продаж ВТМ',
            fact: _ShiftData.vtmFact,
            plan: _ShiftData.vtmPlan,
            factLabel: '2 100',
            planLabel: '3 000',
          ),
          const SizedBox(height: 12),
          _buildExpandable(),
        ],
      ),
    );
  }

  // ── Earned card ──────────────────────────────────────────────────────────

  Widget _buildEarnedCard() {
    return AnimatedBuilder(
      animation: _earningAnim,
      builder: (context, _) {
        final displayValue = _earningAnim.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFFCC00),
                    ),
                    child: const Center(
                      child: Text(
                        'АНЦ',
                        style: TextStyle(
                          color: Color(0xFF1E7DC8),
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Нараховано з початку зміни',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatMoney(displayValue),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C1C2E),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Format [value] as "3 200,00 ₴" (space thousands separator, comma decimal).
  static String _formatMoney(double value) {
    final cents = (value * 100).round();
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    final s = whole.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u00A0'); // narrow space
      buf.write(s[i]);
    }
    return '$buf,$frac';
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

  // Progress bars always use primary blue; % badge uses status colour.
  static const _barColor = Color(0xFF1E7DC8);

  Widget _buildKpiBar({
    required String label,
    required double fact,
    required double plan,
    required String factLabel,
    required String planLabel,
  }) {
    final ratio = (fact / plan).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();

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
                color: const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$pct%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C2E),
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
            valueColor: const AlwaysStoppedAnimation<Color>(_barColor),
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
          const Color(0xFF1E7DC8),
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
                  'Всі показники за зміну',
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
}
