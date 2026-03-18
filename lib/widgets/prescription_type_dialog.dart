import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/prescription.dart';

// ═════════════════════════════════════════════════════════════════════════════
// PRESCRIPTION TYPE DIALOG — Step 1 of e-Prescription flow.
// Select type (electronic / paper / 1303) + enter prescription number.
// ═════════════════════════════════════════════════════════════════════════════

/// Result of the prescription type dialog.
class PrescriptionDialogResult {
  final PrescriptionType type;
  final String number;
  const PrescriptionDialogResult({required this.type, required this.number});
}

/// Show the prescription type selection dialog.
Future<PrescriptionDialogResult?> showPrescriptionTypeDialog(
  BuildContext context,
) {
  return showDialog<PrescriptionDialogResult>(
    context: context,
    builder: (ctx) => const PrescriptionTypeDialog(),
  );
}

class PrescriptionTypeDialog extends StatefulWidget {
  const PrescriptionTypeDialog({super.key});

  @override
  State<PrescriptionTypeDialog> createState() => _PrescriptionTypeDialogState();
}

class _PrescriptionTypeDialogState extends State<PrescriptionTypeDialog> {
  PrescriptionType _selectedType = PrescriptionType.electronic;
  final _numberController = TextEditingController();
  final _numberFocusNode = FocusNode();

  bool get _isValid => _numberController.text.trim().length >= 19;

  @override
  void initState() {
    super.initState();
    _numberController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _numberFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _numberController.dispose();
    _numberFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_isValid) return;
    Navigator.of(context).pop(PrescriptionDialogResult(
      type: _selectedType,
      number: _numberController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTypeLabel(),
                    const SizedBox(height: 10),
                    _buildRadioGrid(),
                    const SizedBox(height: 14),
                    _buildWarning(),
                    const SizedBox(height: 14),
                    _buildNumberInput(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.description_outlined,
                size: 18, color: Color(0xFFD97706)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Відпуск препаратів за рецептом',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C2E))),
                SizedBox(height: 2),
                Text('Введіть дані рецепту',
                    style:
                        TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.close, size: 14, color: Color(0xFF9CA3AF)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Radio grid ──────────────────────────────────────────────────────────────

  Widget _buildTypeLabel() {
    return const Text('Тип рецепту',
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151)));
  }

  Widget _buildRadioGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _radioOption(
                    'Електронний', PrescriptionType.electronic)),
            const SizedBox(width: 8),
            Expanded(
                child:
                    _radioOption('Програма 1303', PrescriptionType.program1303)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
                child: _radioOption('Паперовий', PrescriptionType.paper)),
            const SizedBox(width: 8),
            Expanded(
                child: _radioOption(
                    'Папер. рецепт 1303', PrescriptionType.paper1303)),
          ],
        ),
      ],
    );
  }

  Widget _radioOption(String label, PrescriptionType type) {
    final isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1E7DC8)
                : const Color(0xFFE5E7EB),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1E7DC8)
                      : const Color(0xFFD1D5DB),
                  width: isSelected ? 4.5 : 1.5,
                ),
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? const Color(0xFF1E7DC8)
                          : const Color(0xFF374151))),
            ),
          ],
        ),
      ),
    );
  }

  // ── Warning card ────────────────────────────────────────────────────────────

  Widget _buildWarning() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF59E0B)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'В рецепті мають бути тільки латинські символи та цифри.\n'
              'Будь ласка, перевірте розкладку клавіатури.',
              style: TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Number input ────────────────────────────────────────────────────────────

  Widget _buildNumberInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Введіть номер рецепту',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151))),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: TextField(
            controller: _numberController,
            focusNode: _numberFocusNode,
            style: const TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\-]')),
              LengthLimitingTextInputFormatter(19),
              _PrescriptionNumberFormatter(),
            ],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '0000-XXXX-XXXX-XXXX',
              hintStyle: TextStyle(
                  fontSize: 14,
                  fontFamily: 'monospace',
                  color: Colors.grey.shade400,
                  letterSpacing: 1.2),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF1E7DC8), width: 1.5),
              ),
              prefixIcon: const Icon(Icons.qr_code_scanner,
                  size: 18, color: Color(0xFF9CA3AF)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  foregroundColor: const Color(0xFF6B7280),
                ),
                child: const Text('Відміна',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 40,
              child: ElevatedButton(
                onPressed: _isValid ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isValid
                      ? const Color(0xFF1E7DC8)
                      : const Color(0xFFD1D5DB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Розпочати роботу',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Prescription number auto-formatter (inserts dashes) ─────────────────────

class _PrescriptionNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Strip existing dashes, then re-insert at positions 4, 9, 14
    final raw = newValue.text.replaceAll('-', '').toUpperCase();
    if (raw.isEmpty) return newValue.copyWith(text: '');

    final buf = StringBuffer();
    for (var i = 0; i < raw.length && i < 16; i++) {
      if (i == 4 || i == 8 || i == 12) buf.write('-');
      buf.write(raw[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
