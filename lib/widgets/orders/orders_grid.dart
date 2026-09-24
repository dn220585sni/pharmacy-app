import 'package:flutter/material.dart';

import '../../models/internet_order.dart';
import '../../models/money.dart';
import '../../models/order_extras.dart';
import 'order_indicators.dart';
import 'merge_checkbox.dart';

/// Прев'ю складу замовлення: назви через кому, з кожної — перші 15 символів
/// (ТЗ §3, колонка «Перелік товарів у замовленні»).
String orderItemsPreview(InternetOrder order, {int chars = 15}) => order.items
    .where((i) => !i.isServiceLine)
    .map((i) {
      final n = i.name.trim();
      return n.length > chars ? n.substring(0, chars).trimRight() : n;
    })
    .join(', ');

String orderDateTimeLabel(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Таблиця замовлень для повноекранного режиму панелі (ТЗ §3).
class OrdersGrid extends StatelessWidget {
  final List<InternetOrder> orders;
  final Map<String, OrderExtras> extras;
  final Set<String> checkedIds;
  final bool Function(InternetOrder) canCheck;
  final void Function(InternetOrder) onToggleCheck;
  final void Function(InternetOrder) onOpen;
  final void Function(InternetOrder) onOpenMessages;
  final int highlightedIndex;

  const OrdersGrid({
    super.key,
    required this.orders,
    required this.extras,
    required this.checkedIds,
    required this.canCheck,
    required this.onToggleCheck,
    required this.onOpen,
    required this.onOpenMessages,
    this.highlightedIndex = -1,
  });

  static const _head = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Color(0xFF6B7280),
    letterSpacing: 0.3,
  );
  static const _cell = TextStyle(fontSize: 12.5, color: Color(0xFF1C1C2E));

  // Ширини колонок; «Перелік товарів» забирає решту.
  static const _wCheck = 44.0;
  static const _wDate = 128.0;
  static const _wReserve = 104.0;
  static const _wSum = 92.0;
  static const _wStatus = 230.0;
  static const _wCell = 72.0;
  static const _wType = 128.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFFF9FAFB),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const Row(
            children: [
              SizedBox(
                  width: _wCheck,
                  child: Tooltip(
                    message: 'Позначте 2+ замовлення одного клієнта, '
                        'щоб відпустити їх одним чеком',
                    child: Text('Об\'єдн.', style: _head),
                  )),
              SizedBox(width: _wDate, child: Text('Дата та час', style: _head)),
              SizedBox(width: _wReserve, child: Text('Резерв', style: _head)),
              SizedBox(
                  width: _wSum,
                  child: Text('Сума',
                      style: _head, textAlign: TextAlign.right)),
              SizedBox(width: 16),
              SizedBox(
                  width: _wStatus,
                  child: Text('Статус замовлення', style: _head)),
              SizedBox(width: _wCell, child: Text('Комірка', style: _head)),
              SizedBox(width: _wType, child: Text('Тип', style: _head)),
              Expanded(child: Text('Перелік товарів', style: _head)),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        Expanded(
          child: ListView.separated(
            itemCount: orders.length,
            separatorBuilder: (_, _) => const Divider(
                height: 1, thickness: 1, color: Color(0xFFF4F5F8)),
            itemBuilder: (context, i) => _row(orders[i], i == highlightedIndex),
          ),
        ),
      ],
    );
  }

  Widget _row(InternetOrder o, bool highlighted) {
    final e = extras[o.id] ?? OrderExtras.empty;
    final checkable = canCheck(o);
    return InkWell(
      onTap: () => onOpen(o),
      hoverColor: const Color(0xFFF8FAFF),
      child: Container(
        color: highlighted ? const Color(0xFFEEF2FF) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: _wCheck,
              child: Align(
                alignment: Alignment.centerLeft,
                child: MergeCheckbox(
                  value: checkedIds.contains(o.id),
                  onChanged: checkable ? () => onToggleCheck(o) : null,
                ),
              ),
            ),
            SizedBox(
                width: _wDate,
                child: Text(orderDateTimeLabel(o.dateTime), style: _cell)),
            SizedBox(
              width: _wReserve,
              child: Text(o.reserveNumber,
                  style: _cell.copyWith(fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              width: _wSum,
              child: Text('${o.total.asMoney} ₴',
                  style: _cell, textAlign: TextAlign.right),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: _wStatus,
              child: Wrap(
                spacing: 5,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(o.statusLabel, style: _cell),
                  if (e.autoConfirm) const AutoConfirmMark(),
                  // Плашка «Час спливає/вийшов» у рядку прибрана (24.09).
                  if (e.hasMessages)
                    MessageEnvelope(
                        unread: e.hasUnread, onTap: () => onOpenMessages(o)),
                ],
              ),
            ),
            SizedBox(
              width: _wCell,
              child: Text(o.lockerCell?.toString() ?? '—', style: _cell),
            ),
            SizedBox(
              width: _wType,
              child: Text(o.typeLabel,
                  style: _cell, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              child: Text(
                orderItemsPreview(o),
                style: _cell.copyWith(color: const Color(0xFF6B7280)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
