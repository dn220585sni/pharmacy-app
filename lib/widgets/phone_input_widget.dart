import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhoneInputWidget extends StatefulWidget {
  final void Function(String phone)? onConfirm;

  const PhoneInputWidget({super.key, this.onConfirm});

  @override
  State<PhoneInputWidget> createState() => _PhoneInputWidgetState();
}

class _PhoneInputWidgetState extends State<PhoneInputWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final phone = _controller.text.trim();
    if (phone.isNotEmpty) {
      widget.onConfirm?.call('+380$phone');
    }
  }

  void _clear() {
    _controller.clear();
  }

  void _backspace() {
    final text = _controller.text;
    if (text.isNotEmpty) {
      _controller.text = text.substring(0, text.length - 1);
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No outer background — sits directly on the gray scaffold bg.
    // Height breakdown (matches the search-bar strip on the left):
    //   Padding top (12) + input row (48) + padding bottom (8) = 68 px  ← same as search field
    //   SizedBox label row (36 px)                                       ← same as category chips
    //   Total: 104 px on both sides.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Input row ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              // +380 prefix
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(8)),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '+380',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              // Phone number input — fixed width, just enough for 9 digits
              Container(
                width: 116,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFF9FAFB),
                  border: Border(
                    top: BorderSide(color: Color(0xFFE5E7EB)),
                    bottom: BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  style: const TextStyle(
                    color: Color(0xFF1C1C2E),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'XXXXXXXXX',
                    hintStyle: TextStyle(
                      color: Color(0xFFD1D5DB),
                      fontSize: 13,
                    ),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                  ),
                  onSubmitted: (_) => _confirm(),
                ),
              ),

              // OK button
              GestureDetector(
                onTap: _confirm,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5A623),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              // X button
              GestureDetector(
                onTap: _clear,
                child: Container(
                  height: 48,
                  width: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F5F8),
                    border: Border(
                      top: BorderSide(color: Color(0xFFE5E7EB)),
                      bottom: BorderSide(color: Color(0xFFE5E7EB)),
                      left: BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'X',
                    style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              // Backspace button
              GestureDetector(
                onTap: _backspace,
                child: Container(
                  height: 48,
                  width: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F5F8),
                    borderRadius:
                        BorderRadius.horizontal(right: Radius.circular(8)),
                    border: Border(
                      top: BorderSide(color: Color(0xFFE5E7EB)),
                      bottom: BorderSide(color: Color(0xFFE5E7EB)),
                      left: BorderSide(color: Color(0xFFE5E7EB)),
                      right: BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.backspace_outlined,
                    color: Color(0xFF9CA3AF),
                    size: 15,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Label row — same 36 px height as the category-chips row ──────
        SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Номер клієнта для накопичення бонусів',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
