import 'package:flutter/material.dart';
import '../models/stop_price_action.dart';

/// Спільний попап «Деталі акції» — для кошика (`cart_item_widget`) та картки
/// товара (`drug_detail_panel`). Пояснює знижку, що діє на товар: опис, знижку,
/// період дії, відповідального.
///
/// [qty] — поточна кількість (для кошика); у картці товара = 1. Показуємо лише
/// акції, знижка яких діє при цій кількості; якщо таких нема (знижку дав сервер
/// у зв'язці з іншим препаратом) — показуємо всі акції товара.
void showStopPriceInfoDialog(
  BuildContext context, {
  required String drugName,
  required List<StopPriceAction> actions,
  int qty = 1,
}) {
  if (actions.isEmpty) return;
  final withDiscount = actions
      .where((a) => a.appliedRules(qty).any((r) => r.hasDiscount))
      .toList(growable: false);
  final relevant = withDiscount.isNotEmpty ? withDiscount : actions;

  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_offer_rounded,
                      size: 18, color: Color(0xFF16A34A)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Деталі акції',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C2E),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: Color(0xFF9CA3AF)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                drugName,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < relevant.length; i++) ...[
                        if (i > 0)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1),
                          ),
                        ..._actionInfoBlock(relevant[i], qty),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Віджети-блок одного запису акції: опис + знижка (що діє при [qty]) + період +
/// відповідальний.
List<Widget> _actionInfoBlock(StopPriceAction a, int qty) {
  final applied = a.appliedRules(qty).where((r) => r.hasDiscount);
  final discount =
      applied.isNotEmpty ? applied.last.appliedText : a.baseIncentiveText;
  return [
    Text(
      a.shortOpis,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1C1C2E),
        height: 1.35,
      ),
    ),
    if (discount != null) ...[
      const SizedBox(height: 8),
      _infoRow(Icons.local_offer_rounded, 'Знижка', discount),
    ],
    if (a.dateBegin != null && a.dateEnd != null) ...[
      const SizedBox(height: 8),
      _infoRow(Icons.event_rounded, 'Період', '${a.dateBegin} – ${a.dateEnd}'),
    ],
    if (a.author != null) ...[
      const SizedBox(height: 4),
      _infoRow(Icons.person_outline_rounded, 'Відповідальний', a.author!),
    ],
  ];
}

Widget _infoRow(IconData icon, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
        ),
      ],
    ),
  );
}
