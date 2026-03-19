import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/prescription.dart';
import '../models/drug.dart';
import '../data/mock_prescriptions.dart';

// ═════════════════════════════════════════════════════════════════════════════
// PRESCRIPTION PANEL — right-panel widget for e-Prescription flow.
// Two inline screens: 1) type + number input  →  2) prescription details.
// ═════════════════════════════════════════════════════════════════════════════

class PrescriptionPanel extends StatefulWidget {
  final VoidCallback onClose;
  final List<Drug> drugCatalog;
  final void Function(List<PrescriptionMatch> selectedMatches,
      Prescription prescription) onAddToCart;

  const PrescriptionPanel({
    super.key,
    required this.onClose,
    required this.drugCatalog,
    required this.onAddToCart,
  });

  @override
  State<PrescriptionPanel> createState() => PrescriptionPanelState();
}

class PrescriptionPanelState extends State<PrescriptionPanel> {
  // ── Step 1: input ─────────────────────────────────────────────────────────
  PrescriptionType _selectedType = PrescriptionType.electronic;
  final _numberController = TextEditingController();
  final _numberFocusNode = FocusNode();
  String? _errorMessage;

  // ── Step 2: results ───────────────────────────────────────────────────────
  Prescription? _prescription;
  List<PrescriptionMatch> _matches = [];

  // ── Paper prescription editable fields ──────────────────────────────────
  final _paperMedicationCtr = TextEditingController();
  final _paperQtyCtr = TextEditingController();
  final _paperPatientCtr = TextEditingController();
  final _paperDoctorCtr = TextEditingController();
  final _paperProgramCtr = TextEditingController();
  final _paperCompensationCtr = TextEditingController();
  DateTime _paperDate = DateTime.now();

  bool get _isPaperType =>
      _selectedType == PrescriptionType.paper ||
      _selectedType == PrescriptionType.paper1303;

  bool get _paperFieldsValid {
    if (!_isPaperType) return true;
    return _paperMedicationCtr.text.trim().isNotEmpty &&
        _paperQtyCtr.text.trim().isNotEmpty &&
        _paperPatientCtr.text.trim().isNotEmpty &&
        _paperDoctorCtr.text.trim().isNotEmpty &&
        _paperProgramCtr.text.trim().isNotEmpty &&
        _paperCompensationCtr.text.trim().isNotEmpty;
  }

  void _resetPaperFields() {
    _paperMedicationCtr.clear();
    _paperQtyCtr.clear();
    _paperPatientCtr.clear();
    _paperDoctorCtr.clear();
    _paperProgramCtr.clear();
    _paperCompensationCtr.clear();
    _paperDate = DateTime.now();
  }

  /// Rebuild matches using current paper fields (medication as INN search).
  void _updatePaperMatches() {
    if (_prescription == null) return;
    final medication = _paperMedicationCtr.text.trim();
    final qtyText = _paperQtyCtr.text.trim();
    final qty = int.tryParse(qtyText) ?? 1;
    final compText = _paperCompensationCtr.text.replaceAll(',', '.').trim();
    final compensationPct = double.tryParse(compText) ?? 0;

    if (medication.isEmpty) {
      setState(() => _matches = []);
      return;
    }

    // Search by name/INN substring
    final medLower = medication.toLowerCase();
    final candidates = widget.drugCatalog
        .where((d) =>
            d.stock > 0 &&
            ((d.inn != null && d.inn!.toLowerCase().contains(medLower)) ||
                d.name.toLowerCase().contains(medLower)))
        .toList();

    final matches = <PrescriptionMatch>[];
    final pseudoItem = PrescriptionItem(
      helsiName: medication,
      helsiQuantity: qty,
      inn: medication,
      reimbursementPrice: 0, // will be overridden per drug
    );

    for (final drug in candidates) {
      final reimb = drug.price * compensationPct / 100;
      final copay = (drug.price - reimb).clamp(0.0, double.infinity);
      matches.add(PrescriptionMatch(
        prescriptionItem: pseudoItem,
        drug: drug,
        maxQuantity: drug.stock.clamp(0, qty),
        reimbursementPrice: reimb,
        copayment: copay,
        pharmacistBonus: drug.pharmacistBonus ?? 0,
        isSelected: false,
        selectedQuantity: drug.stock.clamp(1, qty),
      ));
    }
    // Sort by lowest copayment
    matches.sort((a, b) => a.copayment.compareTo(b.copayment));
    if (matches.isNotEmpty) matches.first.isSelected = true;
    setState(() => _matches = matches);
  }

  // ── Public API for POS screen Esc cascade ─────────────────────────────────
  bool get isDetailOpen => _prescription != null;

  void closeDetail() {
    setState(() {
      _prescription = null;
      _matches = [];
      _errorMessage = null;
    });
    _resetPaperFields();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _numberFocusNode.requestFocus();
    });
  }

  void focusSearch() {
    _numberFocusNode.requestFocus();
  }

  bool get _is1303Type =>
      _selectedType == PrescriptionType.program1303 ||
      _selectedType == PrescriptionType.paper1303;

  bool get _isInputValid {
    final len = _numberController.text.trim().length;
    if (_is1303Type) return len >= 6 && len <= 8;
    // User part: XXXX-XXXX-XXXX = 14 chars (12 alphanumeric + 2 dashes)
    return len >= 14;
  }

  List<PrescriptionMatch> get _selected =>
      _matches.where((m) => m.isSelected).toList();

  int get _totalQty => _selected.fold(0, (s, m) => s + m.selectedQuantity);

  double get _totalPrice =>
      _selected.fold(0.0, (s, m) => s + m.totalPrice);

  double get _totalCopayment =>
      _selected.fold(0.0, (s, m) => s + m.totalCopayment);

  @override
  void initState() {
    super.initState();
    _numberController.addListener(() {
      setState(() {
        if (_errorMessage != null) _errorMessage = null;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _numberFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _numberController.dispose();
    _numberFocusNode.dispose();
    _paperMedicationCtr.dispose();
    _paperQtyCtr.dispose();
    _paperPatientCtr.dispose();
    _paperDoctorCtr.dispose();
    _paperProgramCtr.dispose();
    _paperCompensationCtr.dispose();
    super.dispose();
  }

  void _lookupPrescription() {
    if (!_isInputValid) return;

    final userPart = _numberController.text.trim();
    // Standard types: prepend fixed "0000-" prefix
    final number = _is1303Type ? userPart : '0000-$userPart';

    if (_isPaperType) {
      // Paper prescription: create empty template for manual entry
      _resetPaperFields();
      if (_selectedType == PrescriptionType.paper1303) {
        _paperProgramCtr.text = 'Програма 1303';
      }
      setState(() {
        _prescription = Prescription(
          number: number,
          type: _selectedType,
          status: PrescriptionStatus.active,
          issueDate: DateTime.now(),
          medication: '',
          quantity: 0,
          patientName: '',
          programName: '',
          uuid: '',
          items: const [],
        );
        _matches = [];
        _errorMessage = null;
      });
      return;
    }

    // Electronic: lookup from mock data
    final rx = mockPrescriptions[number];
    if (rx == null) {
      setState(() => _errorMessage = 'Рецепт не знайдено');
      return;
    }

    final matches = findPrescriptionMatches(rx, widget.drugCatalog);
    setState(() {
      _prescription = rx;
      _matches = matches;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Focus wrapper handles Esc locally so the global HardwareKeyboard
    // handler in PosScreen can be completely transparent when this panel
    // is open (critical for macOS desktop text input).
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          if (_prescription != null) {
            closeDetail();
          } else {
            widget.onClose();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(14)),
          boxShadow: [
            BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 8,
                offset: Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut)),
              child: child,
            ),
          ),
          child: _prescription != null
              ? _buildResultsScreen(key: const ValueKey('results'))
              : _buildInputScreen(key: const ValueKey('input')),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 1: Input — type selection + number entry
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInputScreen({Key? key}) {
    return Column(
      key: key,
      children: [
        _buildHeader(),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              // ── Type label ────────────────────────────────────────────
              const Text('Тип рецепту',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
              const SizedBox(height: 10),

              // ── Radio grid (2×2) ──────────────────────────────────────
              Row(
                children: [
                  Expanded(
                      child: _radioOption(
                          'Електронний', PrescriptionType.electronic)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _radioOption(
                          'Програма 1303', PrescriptionType.program1303)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                      child:
                          _radioOption('Паперовий', PrescriptionType.paper)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _radioOption(
                          'Папер. рецепт 1303', PrescriptionType.paper1303)),
                ],
              ),
              const SizedBox(height: 16),

              // ── Number input ──────────────────────────────────────────
              Text(
                  _is1303Type
                      ? 'Введіть номер рецепту (6-8 цифр)'
                      : 'Введіть номер рецепту',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: TextField(
                  key: ValueKey('input_$_is1303Type'),
                  controller: _numberController,
                  focusNode: _numberFocusNode,
                  keyboardType: _is1303Type ? TextInputType.number : null,
                  style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2),
                  inputFormatters: _is1303Type
                      ? [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ]
                      : [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9A-Za-z\-]')),
                          LengthLimitingTextInputFormatter(14),
                          _PrescriptionNumberFormatter(),
                        ],
                  onSubmitted: (_) => _lookupPrescription(),
                  decoration: InputDecoration(
                    hintText: _is1303Type
                        ? '123456'
                        : 'XXXX-XXXX-XXXX',
                    hintStyle: TextStyle(
                        fontSize: 14,
                        fontFamily: 'monospace',
                        color: Colors.grey.shade400,
                        letterSpacing: 1.2),
                    prefixText: _is1303Type ? null : '0000-',
                    prefixStyle: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C2E),
                        letterSpacing: 1.2),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: Color(0xFF1E7DC8), width: 1.5),
                    ),
                    prefixIcon: const Icon(Icons.qr_code_scanner,
                        size: 18, color: Color(0xFF9CA3AF)),
                  ),
                ),
              ),

              // ── Warning card (below input, only for non-1303 types) ──
              if (!_is1303Type) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: Color(0xFFF59E0B)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'В рецепті мають бути тільки латинські символи та цифри.\n'
                          'Будь ласка, перевірте розкладку клавіатури.',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF92400E),
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Error message ─────────────────────────────────────────
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 15, color: Color(0xFFEF4444)),
                      const SizedBox(width: 8),
                      Text(_errorMessage!,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFDC2626))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── Mock numbers hint ─────────────────────────────────────
              Builder(builder: (_) {
                if (_isPaperType) {
                  // Paper types: show example format hint
                  final example = _is1303Type ? '123456' : 'ABCD-1234-EF56';
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F5F8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Тестові номери:',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9CA3AF))),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {
                            _numberController.text = example;
                            setState(() {});
                          },
                          child: Text(
                              _is1303Type ? example : '0000-$example',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF1E7DC8),
                                  decoration: TextDecoration.underline,
                                  decorationColor: Color(0xFF1E7DC8))),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Для паперових рецептів дані заповнюються вручну',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  );
                }
                // Electronic / Program 1303: filter mock prescriptions
                final hints = mockPrescriptions.entries
                    .where((e) {
                      final isDigitOnly =
                          RegExp(r'^\d+$').hasMatch(e.key);
                      return _is1303Type ? isDigitOnly : !isDigitOnly;
                    })
                    .map((e) => e.key)
                    .toList();
                if (hints.isEmpty) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5F8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Тестові номери:',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9CA3AF))),
                      const SizedBox(height: 4),
                      ...hints.map((n) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: GestureDetector(
                              onTap: () {
                                // For standard types, strip "0000-" prefix
                                final value = !_is1303Type &&
                                        n.startsWith('0000-')
                                    ? n.substring(5)
                                    : n;
                                _numberController.text = value;
                                setState(() {});
                              },
                              child: Text(n,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Color(0xFF1E7DC8),
                                      decoration:
                                          TextDecoration.underline,
                                      decorationColor:
                                          Color(0xFF1E7DC8))),
                            ),
                          )),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        _buildInputFooter(),
      ],
    );
  }

  Widget _radioOption(String label, PrescriptionType type) {
    final isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () {
        final was1303 = _is1303Type;
        setState(() => _selectedType = type);
        // Clear number when switching between 1303 ↔ standard (incompatible formats)
        if (_is1303Type != was1303) {
          _numberController.clear();
        }
        // Auto-focus the number input after type selection
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _numberFocusNode.requestFocus();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFEFF6FF)
              : const Color(0xFFF9FAFB),
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
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? const Color(0xFF1E7DC8)
                          : const Color(0xFF374151))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputFooter() {
    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: OutlinedButton(
                onPressed: widget.onClose,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Скасувати',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 38,
              child: ElevatedButton.icon(
                onPressed: _isInputValid ? _lookupPrescription : null,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Розпочати роботу',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w500)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isInputValid
                      ? const Color(0xFF1E7DC8)
                      : const Color(0xFFD1D5DB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 2: Results — prescription details + drug matches
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildResultsScreen({Key? key}) {
    final rx = _prescription!;
    return Column(
      key: key,
      children: [
        _buildHeader(),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            children: [
              _buildPrescriptionNumber(rx),
              const SizedBox(height: 8),
              _buildInfoBlock(rx),
              const SizedBox(height: 8),
              _buildMatchesTable(),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: _buildSummaryLine(),
        ),
        _buildResultsFooter(),
      ],
    );
  }

  // ── Shared header ─────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.health_and_safety,
                size: 16, color: Color(0xFF1E7DC8)),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('е-Рецепт',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C2E))),
          ),
          if (_prescription != null) ...[
            _buildHelsiButton(),
            const SizedBox(width: 6),
          ],
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(7),
              ),
              child:
                  const Icon(Icons.close, size: 14, color: Color(0xFF9CA3AF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelsiButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1E7DC8)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('Helsi cabinet',
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E7DC8))),
    );
  }

  // ── Prescription number display ───────────────────────────────────────────

  Widget _buildPrescriptionNumber(Prescription rx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.qr_code, size: 16, color: Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(rx.number,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: Color(0xFF1C1C2E),
                    letterSpacing: 1)),
          ),
          _buildStatusBadge(rx),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(Prescription rx) {
    Color bg;
    Color fg;
    String label;
    switch (rx.status) {
      case PrescriptionStatus.active:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        label = 'ACTIVE';
      case PrescriptionStatus.partiallyUsed:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        label = 'PARTIAL';
      case PrescriptionStatus.used:
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF6B7280);
        label = 'USED';
      case PrescriptionStatus.expired:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFEF4444);
        label = 'EXPIRED';
      case PrescriptionStatus.rejected:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        label = 'REJECTED';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.5)),
    );
  }

  // ── Info block ────────────────────────────────────────────────────────────

  Widget _buildInfoBlock(Prescription rx) {
    if (_isPaperType) return _buildPaperInfoBlock();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          _infoRow('Призначення', rx.medication),
          _infoRow('Кількість', rx.quantity.toString()),
          _infoRow(
              'Пацієнт',
              rx.patientAge != null
                  ? '${rx.patientName} (${rx.patientAge})'
                  : rx.patientName),
          _infoRow('Дата', _formatDate(rx.issueDate)),
          if (rx.doctorName != null) _infoRow('Лікар', rx.doctorName!),
          _infoProgramRow('Програма', rx.programName),
        ],
      ),
    );
  }

  // ── Paper prescription editable info block ──────────────────────────────

  Widget _buildPaperInfoBlock() {
    final valid = _paperFieldsValid;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: valid ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: valid ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  valid
                      ? Icons.check_circle_outline
                      : Icons.edit_note_rounded,
                  size: 14,
                  color: valid
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFD97706)),
              const SizedBox(width: 6),
              Text(
                  valid
                      ? 'Дані рецепту заповнено'
                      : 'Заповніть дані з паперового рецепту',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: valid
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFD97706))),
            ],
          ),
          const SizedBox(height: 8),
          _paperField('Призначення *', _paperMedicationCtr,
              hint: 'МНН або назва препарату',
              onChanged: (_) => _updatePaperMatches()),
          _paperField('Кількість *', _paperQtyCtr,
              hint: 'шт',
              keyboard: TextInputType.number,
              onChanged: (_) => _updatePaperMatches()),
          _paperField('Пацієнт *', _paperPatientCtr, hint: 'ПІБ пацієнта'),
          _paperDateField(),
          _paperField('Лікар *', _paperDoctorCtr, hint: 'ПІБ лікаря'),
          _paperField('Програма *', _paperProgramCtr,
              hint: 'Назва програми'),
          _paperField('% компенс. *', _paperCompensationCtr,
              hint: '0',
              keyboard: TextInputType.number,
              suffix: '%',
              onChanged: (_) => _updatePaperMatches()),
          if (!_paperFieldsValid) ...[
            const SizedBox(height: 6),
            const Text(
              'Заповніть всі обов\'язкові поля для продовження',
              style: TextStyle(fontSize: 9.5, color: Color(0xFFEF4444)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paperField(String label, TextEditingController ctr,
      {String? hint,
      TextInputType? keyboard,
      String? suffix,
      ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: RichText(
              text: TextSpan(
                text: label.replaceAll(' *', ''),
                style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500),
                children: [
                  if (label.contains('*'))
                    const TextSpan(
                        text: ' *',
                        style: TextStyle(color: Color(0xFFEF4444))),
                ],
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: ctr,
                keyboardType: keyboard,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1C1C2E)),
                onChanged: (v) {
                  setState(() {});
                  onChanged?.call(v);
                },
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle:
                      TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  suffixText: suffix,
                  suffixStyle: suffix != null
                      ? const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w500)
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  isDense: true,
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
                    borderSide: const BorderSide(
                        color: Color(0xFFD97706), width: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paperDateField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: RichText(
              text: const TextSpan(
                text: 'Дата',
                style: TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 28,
              child: GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _paperDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _paperDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    isDense: true,
                    suffixIcon: const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.calendar_today,
                          size: 12, color: Color(0xFF9CA3AF)),
                    ),
                    suffixIconConstraints:
                        const BoxConstraints(maxHeight: 20, maxWidth: 20),
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
                  ),
                  child: Text(_formatDate(_paperDate),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1C1C2E))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Static info rows (electronic) ───────────────────────────────────────

  Widget _infoRow(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 10.5,
                    color: const Color(0xFF1C1C2E),
                    fontWeight: FontWeight.w500,
                    fontFamily: mono ? 'monospace' : null)),
          ),
        ],
      ),
    );
  }

  Widget _infoProgramRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF1C1C2E),
                    fontWeight: FontWeight.w600,
                    height: 1.3)),
          ),
        ],
      ),
    );
  }

  // ── Summary line ──────────────────────────────────────────────────────────

  Widget _buildSummaryLine() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          _summaryItem('Кількість', '$_totalQty'),
          Container(
              width: 1, height: 20, color: const Color(0xFFBBF7D0)),
          _summaryItem('Сума', _totalPrice.toStringAsFixed(2)),
          Container(
              width: 1, height: 20, color: const Color(0xFFBBF7D0)),
          Expanded(
            child: Column(
              children: [
                const Text('До сплати',
                    style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w500)),
                Text(_totalCopayment.toStringAsFixed(2),
                    style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Matches table ─────────────────────────────────────────────────────────

  Widget _buildMatchesTable() {
    if (_matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        child: Column(
          children: const [
            Icon(Icons.search_off, size: 32, color: Color(0xFFD1D5DB)),
            SizedBox(height: 8),
            Text('Відповідних препаратів не знайдено',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Підбір препаратів',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151))),
        const SizedBox(height: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: const [
              SizedBox(width: 28),
              Expanded(
                  flex: 5,
                  child: Text('Найменування',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280)))),
              Expanded(
                  flex: 3,
                  child: Text('Виробник',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280)))),
              SizedBox(
                  width: 50,
                  child: Text('Кільк',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280)))),
              SizedBox(
                  width: 60,
                  child: Text('Ціна',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280)))),
              SizedBox(
                  width: 60,
                  child: Text('Відшк.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280)))),
              SizedBox(
                  width: 60,
                  child: Text('Доплата',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280)))),
            ],
          ),
        ),
        const SizedBox(height: 2),
        ..._matches.map((m) => _buildMatchRow(m)),
      ],
    );
  }

  Widget _buildMatchRow(PrescriptionMatch match) {
    return GestureDetector(
      onTap: () => setState(() => match.isSelected = !match.isSelected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: match.isSelected
              ? const Color(0xFFF0FDF4)
              : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: match.isSelected
                ? const Color(0xFFBBF7D0)
                : const Color(0xFFF3F4F6),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: match.isSelected,
                onChanged: (v) =>
                    setState(() => match.isSelected = v ?? false),
                activeColor: const Color(0xFF16A34A),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(match.drug.name,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: match.isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: const Color(0xFF1C1C2E)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(match.prescriptionItem.helsiName,
                      style: const TextStyle(
                          fontSize: 9.5, color: Color(0xFF9CA3AF)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(match.drug.manufacturer,
                  style: const TextStyle(
                      fontSize: 10.5, color: Color(0xFF6B7280)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: 50,
              child: Center(child: _buildQtyControl(match)),
            ),
            SizedBox(
              width: 60,
              child: Text(match.drug.price.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1C1C2E))),
            ),
            SizedBox(
              width: 60,
              child: Text(
                  match.reimbursementPrice > 0
                      ? match.reimbursementPrice.toStringAsFixed(2)
                      : '—',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E7DC8))),
            ),
            SizedBox(
              width: 60,
              child: Text(match.copayment.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: match.copayment == 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFEA580C))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQtyControl(PrescriptionMatch match) {
    if (!match.isSelected) {
      return Text('${match.selectedQuantity}',
          style:
              const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            if (match.selectedQuantity > 1) {
              setState(() => match.selectedQuantity--);
            }
          },
          child: const Icon(Icons.remove_circle_outline,
              size: 14, color: Color(0xFF9CA3AF)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('${match.selectedQuantity}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C2E))),
        ),
        GestureDetector(
          onTap: () {
            if (match.selectedQuantity < match.maxQuantity) {
              setState(() => match.selectedQuantity++);
            }
          },
          child: const Icon(Icons.add_circle_outline,
              size: 14, color: Color(0xFF1E7DC8)),
        ),
      ],
    );
  }

  // ── Results footer ────────────────────────────────────────────────────────

  Widget _buildResultsFooter() {
    final hasSelection = _selected.isNotEmpty;
    final canAdd = hasSelection && _paperFieldsValid;
    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add_circle_outline, size: 14),
                label: const Text('До дефектури',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w500)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 38,
              child: ElevatedButton.icon(
                onPressed: canAdd
                    ? () => widget.onAddToCart(_selected, _prescription!)
                    : null,
                icon: const Icon(Icons.add_shopping_cart, size: 16),
                label: const Text('Додати до чеку',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w500)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canAdd
                      ? const Color(0xFF1E7DC8)
                      : const Color(0xFFD1D5DB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

// ── Prescription number auto-formatter ──────────────────────────────────────

class _PrescriptionNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll('-', '').toUpperCase();
    if (raw.isEmpty) return newValue.copyWith(text: '');

    // User types 12 chars max → formatted: XXXX-XXXX-XXXX (14 chars)
    final buf = StringBuffer();
    for (var i = 0; i < raw.length && i < 12; i++) {
      if (i > 0 && i % 4 == 0) buf.write('-');
      buf.write(raw[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
