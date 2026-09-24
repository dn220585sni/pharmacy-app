import 'package:flutter/material.dart';

import '../../models/internet_order.dart';
import '../../models/money.dart';

/// Підтвердження об'єднання кількох ІЗ в один чек (ТЗ §9).
///
/// Показує ПОВНИЙ склад кожного замовлення (Микола, 24.09: фармацевт міг
/// не відкривати їх окремо, і до цього вікна складу об'єднаного чека ніде не
/// було видно): номер, час, статус, позиції з кількістю й сумою, «Знижка на
/// чек» окремим рядком, викреслені позиції — перекреслено. Унизу разом.
///
/// Повертає `true`, якщо касир підтвердив.
Future<bool?> showOrderMergeDialog(
  BuildContext context,
  List<InternetOrder> orders,
) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _OrderMergeDialog(orders: orders),
  );
}

class _OrderMergeDialog extends StatelessWidget {
  const _OrderMergeDialog({required this.orders});

  final List<InternetOrder> orders;

  static const _ink = Color(0xFF1C1C2E);
  static const _text = Color(0xFF374151);
  static const _muted = Color(0xFF6B7280);
  static const _line = Color(0xFFE5E7EB);
  static const _blue = Color(0xFF1E7DC8);

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _when(DateTime d) =>
      '${_two(d.day)}.${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';

  static String _qty(OrderItem i) {
    if (i.fraction != null) return i.fraction!;
    final q = i.quantity;
    return q == q.roundToDouble() ? q.toInt().toString() : q.toString();
  }

  @override
  Widget build(BuildContext context) {
    final total = orders.fold(0.0, (s, o) => s + o.total);
    final positions = orders.fold(
        0, (s, o) => s + o.items.where((i) => !i.isServiceLine).length);
    final who = orders
        .map((o) => [
              if (o.customerName != null) o.customerName!,
              if (o.customerPhone != null) o.customerPhone!,
            ].join(' · '))
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Об\'єднання ${orders.length} замовлень в один чек',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
              if (who.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(who,
                    style: const TextStyle(fontSize: 12.5, color: _muted)),
              ],
              const SizedBox(height: 8),
              const Text(
                'Клієнт має надати згоду на один чек за всі замовлення. '
                'Перевірте склад:',
                style: TextStyle(fontSize: 13, height: 1.4, color: _text),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var k = 0; k < orders.length; k++) ...[
                          if (k > 0) const SizedBox(height: 10),
                          _orderBlock(orders[k]),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 18, color: _line),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Разом · $positions поз.',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
                    ),
                  ),
                  Text('${total.asMoney} ₴',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Скасувати'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    autofocus: true,
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: const Text('Об\'єднати'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orderBlock(InternetOrder o) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '№${o.reserveNumber}',
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _ink)),
                    TextSpan(
                        text: '   ${_when(o.dateTime)} · ${o.statusLabel}'
                            '${o.typeLabel.isEmpty ? '' : ' · ${o.typeLabel}'}',
                        style: const TextStyle(fontSize: 12, color: _muted)),
                  ]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${o.total.asMoney} ₴',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink)),
            ],
          ),
          const SizedBox(height: 6),
          for (final i in o.items) _itemRow(i),
        ],
      ),
    );
  }

  Widget _itemRow(OrderItem i) {
    final service = i.isServiceLine;
    final style = TextStyle(
      fontSize: 12.5,
      height: 1.35,
      color: service ? _muted : _text,
      fontStyle: service ? FontStyle.italic : FontStyle.normal,
      decoration: i.strikeOut ? TextDecoration.lineThrough : null,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(i.name, style: style)),
          const SizedBox(width: 10),
          if (!service)
            Text('${_qty(i)} × ${i.price.asMoney}',
                style: style.copyWith(color: _muted)),
          if (!service) const SizedBox(width: 12),
          SizedBox(
            width: 78,
            child: Text('${i.total.asMoney} ₴',
                textAlign: TextAlign.right,
                style: style.copyWith(
                    fontWeight: service ? FontWeight.w400 : FontWeight.w600,
                    color: service ? _muted : _ink)),
          ),
        ],
      ),
    );
  }
}
