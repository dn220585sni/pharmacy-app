import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/cart_item.dart';
import '../models/drug.dart';
import 'cart_item_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CartOffer — public model for pharmacist offer recommendations.
// Populated by PosScreen from a service; mock data used until service is ready.
// ─────────────────────────────────────────────────────────────────────────────

class CartOffer {
  final Drug drug;
  final String reason;
  const CartOffer({required this.drug, required this.reason});
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone prefix formatter — always keeps "+380 ", only digits allowed after it.
// ─────────────────────────────────────────────────────────────────────────────

class _PhonePrefixFormatter extends TextInputFormatter {
  static const _prefix = '+380 ';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;

    if (!text.startsWith(_prefix)) {
      // User tried to delete prefix — rebuild from raw digits
      final allDigits = text.replaceAll(RegExp(r'\D'), '');
      // Strip leading "380" if it got included
      final afterCode = allDigits.startsWith('380')
          ? allDigits.substring(3)
          : allDigits;
      final result = _prefix + afterCode;
      return TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: result.length),
      );
    }

    // Prefix is intact — allow only digits after it
    final afterPrefix = text.substring(_prefix.length);
    final cleanAfter = afterPrefix.replaceAll(RegExp(r'\D'), '');
    final result = _prefix + cleanAfter;
    final cursor = newValue.selection.end
        .clamp(_prefix.length, result.length)
        .toInt();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CartPanel — inline cart shown in the right detail panel.
// Matches the visual style of DrugDetailPanel (white card, rounded 14, shadow).
// ─────────────────────────────────────────────────────────────────────────────

class CartPanel extends StatefulWidget {
  final List<CartItem> cart;
  final List<CartOffer> offers;
  final VoidCallback onClear;
  final void Function(int index) onIncrease;
  final void Function(int index) onDecrease;
  final void Function(int index) onRemove;
  final VoidCallback onPay;
  final VoidCallback onClose;
  final void Function(Drug drug) onAddOffer;

  const CartPanel({
    super.key,
    required this.cart,
    required this.offers,
    required this.onClear,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onPay,
    required this.onClose,
    required this.onAddOffer,
  });

  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<CartPanel> {
  bool _showPaymentSuccess = false;

  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();

  double get _cartTotal => widget.cart.fold(0.0, (s, i) => s + i.total);
  int get _cartItemCount => widget.cart.fold(0, (s, i) => s + i.quantity);

  @override
  void initState() {
    super.initState();
    _phoneController.text = '+380 ';
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  void _processPayment() {
    if (widget.cart.isEmpty) return;
    widget.onPay();
    setState(() => _showPaymentSuccess = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showPaymentSuccess = false);
        widget.onClose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          Expanded(child: _buildItemsList()),
          _buildOffersSection(),
          _buildPhoneSection(),
          _buildSummary(),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded,
              color: Color(0xFF4F6EF7), size: 17),
          const SizedBox(width: 8),
          const Text(
            'Поточний чек',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          // F2 shortcut hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Text(
              'F2',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Spacer(),
          if (widget.cart.isNotEmpty) ...[
            GestureDetector(
              onTap: widget.onClear,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFFEF5350).withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFEF5350), size: 13),
                    SizedBox(width: 4),
                    Text('Очистити',
                        style: TextStyle(
                            color: Color(0xFFEF5350), fontSize: 11.5)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 7),
          ],
          // Close button
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F8),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Color(0xFF9CA3AF), size: 15),
            ),
          ),
        ],
      ),
    );
  }

  // ── Items list ──────────────────────────────────────────────────────────────

  Widget _buildItemsList() {
    if (widget.cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined,
                color: Colors.grey.shade200, size: 52),
            const SizedBox(height: 12),
            const Text(
              'Кошик порожній',
              style: TextStyle(color: Color(0xFFB0B7C3), fontSize: 14.5),
            ),
            const SizedBox(height: 5),
            const Text(
              'Введіть кількість у полі «Відпущ»',
              style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 12.5),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: widget.cart.length,
      itemBuilder: (context, index) => CartItemWidget(
        item: widget.cart[index],
        onIncrease: () => setState(() => widget.onIncrease(index)),
        onDecrease: () => setState(() => widget.onDecrease(index)),
        onRemove: () => setState(() => widget.onRemove(index)),
      ),
    );
  }

  // ── "Турбота про клієнта" offers section ────────────────────────────────────

  Widget _buildOffersSection() {
    // TODO: replace widget.offers with response from recommendations service
    if (widget.offers.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    color: Color(0xFFF59E0B), size: 14),
                const SizedBox(width: 6),
                const Text(
                  'Турбота про клієнта',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.offers.length}',
                    style: const TextStyle(
                      color: Color(0xFFD97706),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Offer cards
          for (final offer in widget.offers) _buildOfferCard(offer),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildOfferCard(CartOffer offer) {
    final drug = offer.drug;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drug.name,
                    style: const TextStyle(
                      color: Color(0xFF1C1C2E),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    offer.reason,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
              style: const TextStyle(
                color: Color(0xFF4F6EF7),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => widget.onAddOffer(drug),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F6EF7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Додати',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Phone number / loyalty section ──────────────────────────────────────────

  Widget _buildPhoneSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FF),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          // ЛАЙК loyalty badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF4F6EF7),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text(
              'ЛАЙК',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 9),
          // Phone input — prefix "+380 " is always kept
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                keyboardType: TextInputType.phone,
                inputFormatters: [_PhonePrefixFormatter()],
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF1C1C2E),
                ),
                decoration: InputDecoration(
                  hintText: '+380 __ ___ __ __',
                  hintStyle: const TextStyle(
                      color: Color(0xFFB0B7C3), fontSize: 13),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 10, right: 6),
                    child: Icon(Icons.phone_outlined,
                        size: 15, color: Color(0xFF9CA3AF)),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFFDDE1F5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFF4F6EF7)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary + pay ───────────────────────────────────────────────────────────

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _summaryRow('Кількість позицій:', '$_cartItemCount шт.'),
          const SizedBox(height: 5),
          _summaryRow('Знижка:', '0,00 ₴'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: Color(0xFFE5E7EB), height: 1),
          ),
          Row(
            children: [
              const Text(
                'До сплати:',
                style: TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${_cartTotal.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                style: const TextStyle(
                  color: Color(0xFF4F6EF7),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Pay / success button
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: _showPaymentSuccess
                ? _paySuccessWidget()
                : _payButtonWidget(),
          ),

          const SizedBox(height: 8),

          // Secondary actions row
          Row(
            children: [
              Expanded(
                  child: _SmallButton(
                      icon: Icons.print_outlined,
                      label: 'Друк',
                      onTap: () {})),
              const SizedBox(width: 7),
              Expanded(
                  child: _SmallButton(
                      icon: Icons.discount_outlined,
                      label: 'Знижка',
                      onTap: () {})),
              const SizedBox(width: 7),
              Expanded(
                  child: _SmallButton(
                      icon: Icons.pause_outlined,
                      label: 'Пауза',
                      onTap: () {})),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) => Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 12.5)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFF6B7280), fontSize: 12.5)),
        ],
      );

  Widget _paySuccessWidget() => Container(
        key: const ValueKey('success'),
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 19),
            SizedBox(width: 7),
            Text(
              'Оплата проведена!',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _payButtonWidget() => GestureDetector(
        key: const ValueKey('pay'),
        onTap: _processPayment,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 46,
          decoration: BoxDecoration(
            color: widget.cart.isNotEmpty
                ? const Color(0xFF4F6EF7)
                : const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.payment_rounded,
                color: widget.cart.isNotEmpty
                    ? Colors.white
                    : const Color(0xFFB0B7C3),
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                'Провести оплату',
                style: TextStyle(
                  color: widget.cart.isNotEmpty
                      ? Colors.white
                      : const Color(0xFFB0B7C3),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SmallButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: const Color(0xFF4F6EF7).withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF4F6EF7), size: 16),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF4F6EF7), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
