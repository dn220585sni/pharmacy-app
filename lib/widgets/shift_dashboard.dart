import 'package:flutter/material.dart';

import 'anc_coin.dart';
import 'kpi_block.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mock shift data (will be replaced by a service layer later)
// ─────────────────────────────────────────────────────────────────────────────

class _ShiftData {
  // Товарообіг / ВТМ / Частка ЗФ — у KpiBlock (kpi_block.dart, KpiMockData).

  static const List<_MetricRow> allMetrics = [
    _MetricRow('Чеків за зміну', '18', _RowStatus.neutral),
    _MetricRow('Середній чек', '177,78', _RowStatus.neutral),
    _MetricRow('Показник Лайк', '62%', _RowStatus.bad),
    _MetricRow('ТПК (з клієнтів)', '44%', _RowStatus.warning),
    _MetricRow('Препаратів відпущено', '24 уп.', _RowStatus.neutral),
    _MetricRow('Повернень', '0', _RowStatus.good),
  ];
}

enum _RowStatus { neutral, good, warning, bad }

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

  /// Момент останнього нарахування фармацевту. Кожна зміна → монетка
  /// обертається; якщо дашборд змонтовано одразу після оплати (нарахування
  /// «свіже», до [_freshEarnWindow]) — обертається при появі.
  final DateTime? lastEarnedAt;

  /// Стиль монетки АНЦ у картці «Нараховано» (див. [AncCoinStyle]).
  final AncCoinStyle coinStyle;

  /// Ефект монетки при нарахуванні (див. [AncCoinEffect]).
  final AncCoinEffect coinEffect;

  const ShiftDashboard({
    super.key,
    this.earnedAmount = 0.0,
    this.lastEarnedAt,
    this.coinStyle = AncCoinStyle.flat,
    this.coinEffect = AncCoinEffect.spin,
  });

  static const _freshEarnWindow = Duration(seconds: 5);

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
          // Блок «Зверніть увагу» прибрано 17.09 — сервісу підказок ще немає.
          _buildSectionLabel('Показники за зміну', Icons.bar_chart_rounded),
          const SizedBox(height: 14),

          // ── Earned counter (no goal — just current result) ──────────────
          _buildEarnedCard(),
          const SizedBox(height: 14),

          // ── Перемикач «Мої / Аптеки» + Товарообіг, ВТМ, Частка ЗФ ──────
          // Клік по рядку розгортає деталізацію на місці (kpi_block.dart).
          const KpiBlock(),
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
              // Плоска монетка стоїть сама на білому; золота — на блідій
              // жовтій підкладці, як було.
              Container(
                width: 54,
                height: 54,
                decoration: widget.coinStyle == AncCoinStyle.flat
                    ? null
                    : BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(13),
                      ),
                child: Center(
                  child: AncCoin(
                    size: widget.coinStyle == AncCoinStyle.flat ? 48 : 44,
                    style: widget.coinStyle,
                    effect: widget.coinEffect,
                    spinKey: widget.lastEarnedAt,
                    spinOnMount: _isFreshEarn,
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
                      color: Color(0xFF6B7280),
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

  /// Нарахування щойно відбулося (дашборд з'явився одразу після оплати).
  bool get _isFreshEarn {
    final at = widget.lastEarnedAt;
    return at != null &&
        DateTime.now().difference(at) < ShiftDashboard._freshEarnWindow;
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
            color: Color(0xFF6B7280),
            letterSpacing: 0.5,
          ),
        ),
      ],
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
