import 'package:flutter/material.dart';

import '../../models/internet_order.dart';
import '../../models/money.dart';
import '../../models/order_extras.dart';
import '../../services/auth_service.dart';
import '../../services/order_extras_service.dart';

/// Переписка аптека ↔ кол-центр по замовленню (ТЗ §5, §7).
///
/// Вхідні читаються для будь-якої суми. Писати аптека може лише по
/// замовленнях на суму понад [OrderExtrasService.outgoingMinTotal] —
/// обмеження передачі персональних даних Tabletki.ua.
///
/// Повертає оновлені ознаки замовлення (нові повідомлення, прочитано).
Future<OrderExtras> showOrderMessagesDialog(
    BuildContext context, InternetOrder order) async {
  final result = await showDialog<OrderExtras>(
    context: context,
    builder: (_) => _OrderMessagesDialog(order: order),
  );
  return result ?? OrderExtrasService.of(order.id);
}

class _OrderMessagesDialog extends StatefulWidget {
  final InternetOrder order;
  const _OrderMessagesDialog({required this.order});

  @override
  State<_OrderMessagesDialog> createState() => _OrderMessagesDialogState();
}

class _OrderMessagesDialogState extends State<_OrderMessagesDialog> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late OrderExtras _extras;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _extras = OrderExtrasService.markRead(widget.order.id);
    _ctrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToEnd();
      if (OrderExtrasService.canSend(widget.order)) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _jumpToEnd() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final next = await OrderExtrasService.sendMessage(
        widget.order, text, AuthService.currentUser ?? '');
    if (!mounted) return;
    setState(() {
      _extras = next;
      _sending = false;
      _ctrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  static String _fmt(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final canSend = OrderExtrasService.canSend(order);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 580),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mail_outline_rounded,
                    size: 18, color: Color(0xFF1E7DC8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Повідомлення · №${order.reserveNumber}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C2E),
                    ),
                  ),
                ),
                if (OrderExtrasService.isMock)
                  const Tooltip(
                    message: 'Сервісу переписки з кол-центром ще немає: '
                        'повідомлення демонстраційні й нікуди не надсилаються',
                    child: Text('демо',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280))),
                  ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => Navigator.pop(context, _extras),
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        size: 18, color: Color(0xFF6B7280)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: _extras.messages.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'Переписки по цьому замовленню ще не було',
                          style:
                              TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      shrinkWrap: true,
                      itemCount: _extras.messages.length,
                      itemBuilder: (_, i) => _bubble(_extras.messages[i]),
                    ),
            ),
            const SizedBox(height: 12),
            if (canSend)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Повідомлення кол-центру',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: Color(0xFF6B7280)),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF4F5F8),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 38,
                    child: ElevatedButton(
                      onPressed:
                          _ctrl.text.trim().isEmpty || _sending ? null : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E7DC8),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFF3F4F6),
                        disabledForegroundColor: const Color(0xFF9CA3AF),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Надіслати',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Text(
                  'Написати кол-центру можна лише по замовленнях на суму понад '
                  '${OrderExtrasService.outgoingMinTotal.asMoney} ₴ '
                  '(обмеження передачі персональних даних). '
                  'Сума цього замовлення — ${order.total.asMoney} ₴.',
                  style: const TextStyle(
                      fontSize: 12, height: 1.35, color: Color(0xFF6B7280)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(OrderMessage m) {
    final mine = m.fromPharmacy;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFE8F3FB) : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${m.author} · ${_fmt(m.time)}',
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 3),
            Text(m.text,
                style: const TextStyle(
                    fontSize: 13, height: 1.35, color: Color(0xFF1C1C2E))),
          ],
        ),
      ),
    );
  }
}
