import 'package:flutter/material.dart';
import '../models/cart_item.dart';
import 'cart_item_widget.dart';

class CartDialog extends StatefulWidget {
  final List<CartItem> cart;
  final VoidCallback onClear;
  final void Function(int index) onIncrease;
  final void Function(int index) onDecrease;
  final void Function(int index) onRemove;
  final VoidCallback onPay;

  const CartDialog({
    super.key,
    required this.cart,
    required this.onClear,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onPay,
  });

  @override
  State<CartDialog> createState() => _CartDialogState();
}

class _CartDialogState extends State<CartDialog> {
  bool _showPaymentSuccess = false;

  double get _cartTotal =>
      widget.cart.fold(0, (s, i) => s + i.total);
  int get _cartItemCount =>
      widget.cart.fold(0, (s, i) => s + i.quantity);

  void _processPayment() {
    if (widget.cart.isEmpty) return;
    widget.onPay();
    setState(() => _showPaymentSuccess = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showPaymentSuccess = false);
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Container(
        width: 460,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
            Flexible(child: _buildItemsList()),
            _buildSummary(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded,
              color: Color(0xFF4F6EF7), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Поточний чек',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (widget.cart.isNotEmpty)
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
                            color: Color(0xFFEF5350), fontSize: 12)),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Color(0xFF9CA3AF), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    if (widget.cart.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined,
                color: Colors.grey.shade200, size: 52),
            const SizedBox(height: 12),
            const Text(
              'Кошик порожній',
              style:
                  TextStyle(color: Color(0xFFB0B7C3), fontSize: 14.5),
            ),
            const SizedBox(height: 5),
            const Text(
              'Введіть кількість у полі «Відпущ»',
              style:
                  TextStyle(color: Color(0xFFD1D5DB), fontSize: 12.5),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
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

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        border:
            Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Кількість позицій:',
                  style:
                      TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
              const Spacer(),
              Text('$_cartItemCount шт.',
                  style: const TextStyle(
                      color: Color(0xFF6B7280), fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Знижка:',
                  style:
                      TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
              const Spacer(),
              const Text('0,00 ₴',
                  style: TextStyle(
                      color: Color(0xFF6B7280), fontSize: 13)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Color(0xFFE5E7EB), height: 1),
          ),
          Row(
            children: [
              const Text(
                'До сплати:',
                style: TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${_cartTotal.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                style: const TextStyle(
                  color: Color(0xFF4F6EF7),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _showPaymentSuccess
                ? Container(
                    key: const ValueKey('success'),
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF10B981)
                              .withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Color(0xFF10B981), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Оплата проведена!',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : GestureDetector(
                    key: const ValueKey('pay'),
                    onTap: _processPayment,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        color: widget.cart.isNotEmpty
                            ? const Color(0xFF4F6EF7)
                            : const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.payment_rounded,
                            color: widget.cart.isNotEmpty
                                ? Colors.white
                                : const Color(0xFFB0B7C3),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Провести оплату',
                            style: TextStyle(
                              color: widget.cart.isNotEmpty
                                  ? Colors.white
                                  : const Color(0xFFB0B7C3),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                    icon: Icons.print_outlined,
                    label: 'Друк',
                    onTap: () {}),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SecondaryButton(
                    icon: Icons.discount_outlined,
                    label: 'Знижка',
                    onTap: () {}),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SecondaryButton(
                    icon: Icons.pause_outlined,
                    label: 'Пауза',
                    onTap: () {}),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SecondaryButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: const Color(0xFF4F6EF7).withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF4F6EF7), size: 17),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF4F6EF7), fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}
