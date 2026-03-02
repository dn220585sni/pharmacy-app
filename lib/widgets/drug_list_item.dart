import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/drug.dart';

// Fixed column widths — must match the header in pos_screen.dart
const double kColBadge = 44.0;
const double kColStock = 52.0;
const double kColDispensed = 58.0;
const double kColPrice = 78.0;
const double kColExpiry = 54.0;
const double kColManufacturer = 82.0;

class DrugListItem extends StatefulWidget {
  final Drug drug;
  final bool isSelected;
  final bool shouldFocusQty;
  final bool isEvenRow;
  final int cartQuantity;
  final String? pendingInput; // digit to inject when qty field gets focused
  final VoidCallback onTap;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<int> onNavigate; // +1 = down, -1 = up

  const DrugListItem({
    super.key,
    required this.drug,
    required this.isSelected,
    required this.shouldFocusQty,
    required this.isEvenRow,
    required this.cartQuantity,
    this.pendingInput,
    required this.onTap,
    required this.onQuantityChanged,
    required this.onNavigate,
  });

  @override
  State<DrugListItem> createState() => _DrugListItemState();
}

class _DrugListItemState extends State<DrugListItem> {
  late TextEditingController _qtyController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(
      text: widget.cartQuantity > 0 ? '${widget.cartQuantity}' : '',
    );
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onNavigate(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          widget.onNavigate(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  void didUpdateWidget(DrugListItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Focus qty field when row becomes active via keyboard/click (not filter)
    final justBecameSelected = !oldWidget.isSelected && widget.isSelected;
    final focusTriggerChanged = !oldWidget.shouldFocusQty && widget.shouldFocusQty;

    if (widget.isSelected && widget.shouldFocusQty &&
        (justBecameSelected || focusTriggerChanged)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
          final pending = widget.pendingInput;
          if (pending != null && pending.isNotEmpty) {
            // Inject the digit that was typed while search had focus
            _qtyController.value = TextEditingValue(
              text: pending,
              selection: TextSelection.collapsed(offset: pending.length),
            );
            final qty = int.tryParse(pending) ?? 0;
            final clamped = qty.clamp(0, widget.drug.stock);
            if (clamped > 0) widget.onQuantityChanged(clamped);
          } else {
            _qtyController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _qtyController.text.length,
            );
          }
        }
      });
    }

    // Sync controller when cart quantity changes externally
    if (oldWidget.cartQuantity != widget.cartQuantity) {
      final newText =
          widget.cartQuantity > 0 ? '${widget.cartQuantity}' : '';
      if (_qtyController.text != newText) {
        _qtyController.value = _qtyController.value.copyWith(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildBadge() {
    final drug = widget.drug;

    // 1. In transit
    if (drug.isInTransit) {
      return _BadgeContainer(
        color: const Color(0xFFEEEFF2),
        child: const Icon(
          Icons.local_shipping_outlined,
          size: 17,
          color: Color(0xFF94A3B8),
        ),
      );
    }

    // 2. Expired / expiring soon
    if (drug.isExpired || drug.isExpiringSoon) {
      return _BadgeContainer(
        color: const Color(0xFFF5EDED),
        child: const Icon(
          Icons.hourglass_bottom_rounded,
          size: 16,
          color: Color(0xFFAA8080),
        ),
      );
    }

    // 3. Own brand — blue tint, secondary gray text
    if (drug.isOwnBrand) {
      return _BadgeContainer(
        color: const Color(0xFFECEEF6),
        child: drug.pharmacistBonus != null
            ? Text(
                '${drug.pharmacistBonus}',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              )
            : const Text(
                'ВТМ',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
      );
    }

    // 4. Pharmacist bonus — warm tint, secondary gray text
    if (drug.pharmacistBonus != null) {
      return _BadgeContainer(
        color: const Color(0xFFF5F0E8),
        child: Text(
          '${drug.pharmacistBonus}',
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return const SizedBox(width: kColBadge, height: 32);
  }

  @override
  Widget build(BuildContext context) {
    final drug = widget.drug;
    final bool isDimmed =
        (drug.stock == 0 && !drug.isInTransit) || drug.isExpired;

    final Color textPrimary =
        isDimmed ? const Color(0xFFB0B7C3) : const Color(0xFF1C1C2E);
    final Color textSecondary =
        isDimmed ? const Color(0xFFCBD5E1) : const Color(0xFF6B7280);

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: widget.isSelected
            ? const Color(0xFFEEF2FF)
            : widget.isEvenRow
                ? Colors.white
                : const Color(0xFFF8F9FB),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Badge
                  SizedBox(width: kColBadge, child: _buildBadge()),
                  const SizedBox(width: 10),

                  // Name (flexible)
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            drug.name,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 13.5,
                              fontWeight: widget.isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (drug.requiresPrescription && !isDimmed)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'Рецепт',
                              style: TextStyle(
                                color: Color(0xFFEF5350),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Stock
                  SizedBox(
                    width: kColStock,
                    child: Text(
                      '${drug.stock}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textSecondary, fontSize: 13),
                    ),
                  ),

                  // Dispensed (qty input)
                  SizedBox(
                    width: kColDispensed,
                    child: drug.stock > 0
                        ? Center(
                            child: SizedBox(
                              width: 44,
                              height: 28,
                              child: TextField(
                                controller: _qtyController,
                                focusNode: _focusNode,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1C1C2E),
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 5),
                                  filled: true,
                                  fillColor: widget.cartQuantity > 0
                                      ? const Color(0xFFEEF2FF)
                                      : const Color(0xFFF9FAFB),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE5E7EB), width: 1),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                      color: widget.cartQuantity > 0
                                          ? const Color(0xFF4F6EF7)
                                          : const Color(0xFFE5E7EB),
                                      width: 1,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                        color: Color(0xFF4F6EF7), width: 1.5),
                                  ),
                                ),
                                onChanged: (value) {
                                  final qty = int.tryParse(value) ?? 0;
                                  final clamped = qty.clamp(0, drug.stock);
                                  widget.onQuantityChanged(clamped);
                                },
                                onTap: () {
                                  if (!widget.isSelected) widget.onTap();
                                },
                              ),
                            ),
                          )
                        : const SizedBox(),
                  ),

                  // Price
                  SizedBox(
                    width: kColPrice,
                    child: Text(
                      drug.price.toStringAsFixed(2).replaceAll('.', ','),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color:
                            isDimmed ? textSecondary : const Color(0xFF1C1C2E),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Expiry
                  SizedBox(
                    width: kColExpiry,
                    child: Text(
                      drug.expiryDate ?? '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: drug.isExpired
                            ? const Color(0xFFEF5350)
                            : drug.isExpiringSoon
                                ? const Color(0xFFF59E0B)
                                : textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),

                  // Manufacturer
                  SizedBox(
                    width: kColManufacturer,
                    child: Text(
                      drug.manufacturer,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: textSecondary, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFEEEFF2)),
          ],
        ),
      ),
    );
  }
}

class _BadgeContainer extends StatelessWidget {
  final Color color;
  final Widget child;

  const _BadgeContainer({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(child: child),
    );
  }
}
