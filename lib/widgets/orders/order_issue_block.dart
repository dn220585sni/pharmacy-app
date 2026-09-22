import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/internet_order.dart';
import '../../models/money.dart';
import '../../models/order_extras.dart';
import '../../services/order_extras_service.dart';

/// Блок спеціального замовлення (ТЗ §10; у старому роздрібі — окреме вікно, у нас усередині картки замовлення):
/// онлайн-оплата LiqPay з кодом видачі, страхові (франшиза), атрибути збору.
///
/// Для передоплаченого замовлення касова кнопка лишається заблокованою, доки
/// код видачі з SMS покупця не пройде перевірку — про це повідомляє
/// [onVerifiedChanged].
class OrderIssueBlock extends StatefulWidget {
  final InternetOrder order;
  final OrderExtras extras;

  /// Оплату онлайн підтвердив GetOrderData (справжня ознака, не мок).
  final bool paidOnlineConfirmed;
  final bool verified;
  final ValueChanged<bool> onVerifiedChanged;

  /// Номер е-рецепта або соцкартки, введений касиром.
  final TextEditingController prescriptionController;

  const OrderIssueBlock({
    super.key,
    required this.order,
    required this.extras,
    required this.paidOnlineConfirmed,
    required this.verified,
    required this.onVerifiedChanged,
    required this.prescriptionController,
  });

  @override
  State<OrderIssueBlock> createState() => _OrderIssueBlockState();
}

class _OrderIssueBlockState extends State<OrderIssueBlock> {
  final _codeCtrl = TextEditingController();
  bool _checking = false;
  bool _smsSent = false;
  String? _error;

  bool get _prepaid => widget.extras.prepaid || widget.paidOnlineConfirmed;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await OrderExtrasService.verifyIssueCode(widget.order, code);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = ok ? null : 'Код не підходить. Перевірте SMS покупця';
    });
    widget.onVerifiedChanged(ok);
  }

  Future<void> _resend() async {
    await OrderExtrasService.resendIssueSms(widget.order);
    if (!mounted) return;
    setState(() => _smsSent = true);
  }

  static String _fmtDate(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final e = widget.extras;
    final order = widget.order;
    final isInsurance = order.type == OrderType.likTas;

    final attrs = <(String, String)>[
      if (e.collectedBy != null) ('ІЗ зібрав(ла)', e.collectedBy!),
      if (e.collectedAt != null) ('Дата збору', _fmtDate(e.collectedAt!)),
      if (e.promoCode != null) ('Промокод', e.promoCode!),
      if (isInsurance && e.franchisePercent != null)
        (
          'Франшиза',
          '${e.franchisePercent}% · клієнт сплачує '
              '${(order.total * e.franchisePercent! / 100).asMoney} ₴'
        ),
    ];

    if (!_prepaid && attrs.isEmpty && !isInsurance) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_prepaid) ..._prepaidSection(),
          if (_prepaid && (attrs.isNotEmpty || isInsurance))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: Color(0xFFE5E7EB)),
            ),
          for (final (label, value) in attrs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                  ),
                  Expanded(
                    child: Text(value,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1C1C2E))),
                  ),
                ],
              ),
            ),
          if (isInsurance) ...[
            const SizedBox(height: 6),
            TextField(
              controller: widget.prescriptionController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Номер електронного рецепту (або соц. картка)',
                labelStyle: const TextStyle(fontSize: 12),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
          if (OrderExtrasService.isMock && !widget.paidOnlineConfirmed) ...[
            const SizedBox(height: 6),
            const Text(
              'демо: ознаки цього блоку поки не приходять із сервера',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF6B7280)),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _prepaidSection() {
    return [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 16, color: Color(0xFFB45309)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Зверніть увагу. Дане замовлення не потребує оплати на місці',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: Color(0xFF92400E),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              enabled: !widget.verified,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 14, letterSpacing: 1),
              onSubmitted: (_) => _verify(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'Код видачі замовлення',
                helperText: widget.verified
                    ? 'Код підтверджено'
                    : OrderExtrasService.isMock
                        ? 'демо: останні 4 цифри номера замовлення'
                        : 'Код із SMS покупця',
                helperStyle: TextStyle(
                  fontSize: 11,
                  color: widget.verified
                      ? const Color(0xFF059669)
                      : const Color(0xFF6B7280),
                ),
                errorText: _error,
                isDense: true,
                suffixIcon: widget.verified
                    ? const Icon(Icons.check_circle_rounded,
                        size: 18, color: Color(0xFF059669))
                    : null,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!widget.verified)
            SizedBox(
              height: 40,
              child: ElevatedButton(
                onPressed: _checking ? null : _verify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E7DC8),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(_checking ? '…' : 'Перевірити',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      if (!widget.verified)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _resend,
            icon: const Icon(Icons.sms_outlined, size: 15),
            label: Text(_smsSent ? 'SMS надіслано повторно' : 'SMS повтор'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF1E7DC8),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
        ),
      const SizedBox(height: 6),
      const Text(
        'УВАГА! озвучте клієнту: Ця каса працює за електронними чеками. '
        'Знайти свій електронний чек ви можете в мобільному додатку або '
        'вайбер/телеграм ботах. На сайті ANC.UA є посилання для встановлення',
        style:
            TextStyle(fontSize: 11.5, height: 1.4, color: Color(0xFF374151)),
      ),
    ];
  }
}
