import 'package:flutter/material.dart';

/// Причина, чому інтернет-замовлення НЕ кладуть у лікомат, хоча мали
/// (`ResPostmate` у SavesgVNakl, Катя 14.10). Без причини продаж / резерв
/// такого замовлення не зберігаємо. null — фармацевт скасував.
Future<String?> showLockerRefusalDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _LockerRefusalDialog(),
  );
}

/// Типові причини; «Інше» — вписати свою.
const kLockerRefusalReasons = [
  'Немає вільної комірки потрібного розміру',
  'Не вміщується в комірку (негабарит)',
  'Клієнт просить видати в аптеці',
  'Лікомат не працює',
];

class _LockerRefusalDialog extends StatefulWidget {
  const _LockerRefusalDialog();

  @override
  State<_LockerRefusalDialog> createState() => _LockerRefusalDialogState();
}

class _LockerRefusalDialogState extends State<_LockerRefusalDialog> {
  String? _choice;
  final _other = TextEditingController();
  static const _otherKey = '__other__';

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String? get _reason {
    if (_choice == _otherKey) {
      final s = _other.text.trim();
      return s.isEmpty ? null : s;
    }
    return _choice;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Чому не в лікомат?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Це замовлення має бути покладене в лікомат. Вкажіть, чому '
              'ви видаєте його інакше:',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _choice,
              onChanged: (v) => setState(() => _choice = v),
              child: Column(
                children: [
                  for (final r in kLockerRefusalReasons)
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: r,
                      title: Text(r, style: const TextStyle(fontSize: 13)),
                    ),
                  const RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _otherKey,
                    title: Text('Інше', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            if (_choice == _otherKey)
              TextField(
                controller: _other,
                autofocus: true,
                maxLength: 100,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Причина',
                  border: OutlineInputBorder(),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed:
              _reason == null ? null : () => Navigator.of(context).pop(_reason),
          child: const Text('Продовжити'),
        ),
      ],
    );
  }
}
