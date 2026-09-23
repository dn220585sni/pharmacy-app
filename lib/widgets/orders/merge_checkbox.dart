import 'package:flutter/material.dart';

/// Чекбокс «Об'єднати» у списку ІЗ — дрібний і неконтрастний, щоб не
/// перетягувати увагу з номера замовлення (Микола 23.09).
class MergeCheckbox extends StatelessWidget {
  final bool value;
  final VoidCallback? onChanged;

  const MergeCheckbox({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Transform.scale(
        scale: 0.8,
        child: Checkbox(
          value: value,
          onChanged: onChanged == null ? null : (_) => onChanged!(),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          activeColor: const Color(0xFF7FA9D6),
          side: const BorderSide(color: Color(0xFFCBD2DC), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        ),
      ),
    );
  }
}
