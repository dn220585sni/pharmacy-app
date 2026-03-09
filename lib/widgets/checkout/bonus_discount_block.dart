import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/customer_loyalty.dart';

/// Combined bonuses + personal discount + promo code block in the checkout screen.
class BonusDiscountBlock extends StatefulWidget {
  const BonusDiscountBlock({
    super.key,
    required this.loyalty,
    required this.useBonuses,
    required this.onUseBonusesChanged,
    required this.bonusController,
    required this.cartTotal,
    required this.discountAmount,
    required this.effectiveBonusAmount,
    required this.personalDiscount,
    required this.isLoadingDiscount,
    required this.onRequestDiscount,
    required this.onClearDiscount,
    required this.onBonusAmountChanged,
  });

  final CustomerLoyalty? loyalty;
  final bool useBonuses;
  final ValueChanged<bool> onUseBonusesChanged;
  final TextEditingController bonusController;
  final double cartTotal;
  final double discountAmount;
  final double effectiveBonusAmount;
  final double? personalDiscount;
  final bool isLoadingDiscount;
  final VoidCallback onRequestDiscount;
  final VoidCallback onClearDiscount;
  final VoidCallback onBonusAmountChanged;

  @override
  State<BonusDiscountBlock> createState() => _BonusDiscountBlockState();
}

class _BonusDiscountBlockState extends State<BonusDiscountBlock> {
  bool _usePromoCode = false;
  final _promoController = TextEditingController();
  final _promoFocusNode = FocusNode();

  @override
  void dispose() {
    _promoController.dispose();
    _promoFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasLoyalty = widget.loyalty != null;
    const disabledText = Color(0xFFB0B7C3);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE1F5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Bonus row ────────────────────────────────────────────────────
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: widget.useBonuses,
                  onChanged: hasLoyalty
                      ? (v) => widget.onUseBonusesChanged(v ?? false)
                      : null,
                  activeColor: const Color(0xFF1E7DC8),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(
                      color: hasLoyalty
                          ? const Color(0xFFD1D5DB)
                          : const Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Списати бонуси',
                    style: TextStyle(
                        color: hasLoyalty
                            ? const Color(0xFF1C1C2E)
                            : disabledText,
                        fontSize: 12),
                    children: [
                      if (hasLoyalty)
                        TextSpan(
                          text:
                              ' (доступно ${widget.loyalty!.bonusBalance.toStringAsFixed(2).replaceAll('.', ',')})',
                          style: const TextStyle(
                              color: Color(0xFF9CA3AF), fontSize: 11.5),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Bonus amount input (if checked)
          if (widget.useBonuses && hasLoyalty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 28), // align with text above
                SizedBox(
                  width: 80,
                  height: 30,
                  child: TextField(
                    controller: widget.bonusController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                    ],
                    onChanged: (_) => widget.onBonusAmountChanged(),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C2E),
                    ),
                    decoration: InputDecoration(
                      suffixText: '₴',
                      suffixStyle: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 7),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFF1E7DC8)),
                      ),
                    ),
                  ),
                ),
                if (widget.effectiveBonusAmount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '-${widget.effectiveBonusAmount.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],

          // ── Divider ──────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Color(0xFFE5E7EB), height: 1),
          ),

          // ── Personal discount row ────────────────────────────────────────
          GestureDetector(
            onTap: hasLoyalty
                ? () {
                    if (widget.personalDiscount != null) {
                      widget.onClearDiscount();
                    } else {
                      widget.onRequestDiscount();
                    }
                  }
                : null,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: widget.isLoadingDiscount
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF1E7DC8),
                          ),
                        )
                      : Checkbox(
                          value: widget.personalDiscount != null,
                          onChanged: hasLoyalty
                              ? (_) {
                                  if (widget.personalDiscount != null) {
                                    widget.onClearDiscount();
                                  } else {
                                    widget.onRequestDiscount();
                                  }
                                }
                              : null,
                          activeColor: const Color(0xFF1E7DC8),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                              color: hasLoyalty
                                  ? const Color(0xFFD1D5DB)
                                  : const Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'Застосувати персон. знижку',
                      style: TextStyle(
                          color: hasLoyalty
                              ? const Color(0xFF1C1C2E)
                              : disabledText,
                          fontSize: 12),
                      children: [
                        if (widget.personalDiscount != null)
                          TextSpan(
                            text:
                                '  -${widget.discountAmount.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Divider ──────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Color(0xFFE5E7EB), height: 1),
          ),

          // ── Promo code row (checkbox + inline text field) ────────────
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _usePromoCode,
                  onChanged: (v) {
                    setState(() {
                      _usePromoCode = v ?? false;
                      if (_usePromoCode) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _promoFocusNode.requestFocus();
                        });
                      } else {
                        _promoController.clear();
                        _promoFocusNode.unfocus();
                      }
                    });
                  },
                  activeColor: const Color(0xFF1E7DC8),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _promoController,
                    focusNode: _promoFocusNode,
                    enabled: _usePromoCode,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C2E),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Застосувати промокод',
                      hintStyle: TextStyle(
                        color: _usePromoCode
                            ? const Color(0xFFB0B7C3)
                            : const Color(0xFF1C1C2E),
                        fontSize: 12,
                        fontWeight: _usePromoCode
                            ? FontWeight.w400
                            : FontWeight.w400,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 7),
                      filled: true,
                      fillColor: _usePromoCode
                          ? const Color(0xFFF9FAFB)
                          : const Color(0xFFFAFAFA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFEEEEEE)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: Color(0xFF1E7DC8)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
