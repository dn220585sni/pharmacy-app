import 'package:flutter/material.dart';
import '../models/drug.dart';
import '../services/farmasell_service.dart';
import '../services/product_browser_service.dart';
import 'drug_list_item.dart'; // for kColBadge
import 'instruction_dialog.dart';
import 'shift_dashboard.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Location chip widget
// ─────────────────────────────────────────────────────────────────────────────

class _LocationChip extends StatelessWidget {
  final StorageLocationType type;
  final String code;
  final int? qty;
  const _LocationChip({required this.type, required this.code, this.qty});

  @override
  Widget build(BuildContext context) {
    final isRobot = type == StorageLocationType.robot;

    if (isRobot) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy_rounded, size: 16, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            const Text(
              'Робот',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (qty != null) ...[
              const SizedBox(width: 6),
              Text(
                '$qty уп.',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final String label;
    final IconData icon;
    switch (type) {
      case StorageLocationType.showcase:
        label = 'Вітрина';
        icon = Icons.storefront_outlined;
      case StorageLocationType.polka:
        label = 'Полиця';
        icon = Icons.shelves;
      default:
        label = 'Стелаж';
        icon = Icons.view_agenda_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E7DC8),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              code,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (qty != null) ...[
            const SizedBox(width: 6),
            Text(
              '$qty уп.',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DrugDetailPanel
// ─────────────────────────────────────────────────────────────────────────────

class DrugDetailPanel extends StatefulWidget {
  final Drug? drug;
  final List<Drug> analogues;
  final List<ProductSearchResult> externalAnalogues;
  final void Function(Drug) onSelectAnalogue;
  final void Function(StorageLocationType type, String code, bool applyToCart)? onStorageLocationChanged;
  /// Passed through to ShiftDashboard when drug == null.
  final double earnedAmount;

  // ── Рука допомоги ──────────────────────────────────────────────────────
  final bool isCustomerAuthorized;
  final int helpingHandRemaining;
  final double? helpingHandPrice; // discounted price (null = not yet checked)
  final VoidCallback? onRequestHelpingHand;
  final VoidCallback? onFocusPhone;
  final void Function(String phone, double discountPrice, int? fractionalQty)? onHelpingHandAddToCart;

  const DrugDetailPanel({
    super.key,
    required this.drug,
    required this.analogues,
    this.externalAnalogues = const [],
    required this.onSelectAnalogue,
    this.onStorageLocationChanged,
    this.earnedAmount = 0.0,
    this.isCustomerAuthorized = false,
    this.helpingHandRemaining = 10,
    this.helpingHandPrice,
    this.onRequestHelpingHand,
    this.onFocusPhone,
    this.onHelpingHandAddToCart,
  });

  @override
  State<DrugDetailPanel> createState() => _DrugDetailPanelState();
}

class _DrugDetailPanelState extends State<DrugDetailPanel> {
  // ── Feature flag: set to false to hide the price from the header ────────
  static const bool _showPriceInHeader = true;

  bool _usageExpanded = true;
  bool _analoguesExpanded = true;

  /// Reset collapse state when drug changes.
  @override
  void didUpdateWidget(DrugDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drug?.id != widget.drug?.id) {
      _usageExpanded = true;
      _analoguesExpanded = true;
    }
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
      child: widget.drug == null
          ? _buildEmptyState()
          : _buildContent(widget.drug!, context),
    );
  }

  // ── Empty state ─────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return ShiftDashboard(earnedAmount: widget.earnedAmount);
  }

  // ── Main content ────────────────────────────────────────────────────────────

  Widget _buildContent(Drug drug, BuildContext context) {
    final hasStorage = drug.storageConditions != null ||
        drug.storageLocations != null ||
        (drug.locationType != null && drug.locationCode != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Fixed: header ───────────────────────────────────────────────────
        _buildHeader(drug, context),

        // ── Intake warning banner ─────────────────────────────────────────
        if (drug.intakeWarning != null && drug.intakeWarning!.isNotEmpty)
          _buildWarningBanner(drug.intakeWarning!),

        _buildDivider(),

        // ── Основні властивості (collapsible, collapsed by default) ─────────
        if (drug.usageInfo != null) ...[
          _buildUsageHeader(drug, context),
          if (_usageExpanded) _buildUsageProperties(drug),
          _buildDivider(),
        ],

        // ── Аналоги (collapsible, animated) ─────────────────────────────────
        _buildCollapsibleHeader(
          'Аналоги',
          expanded: _analoguesExpanded,
          onTap: () => setState(() =>
              _analoguesExpanded = !_analoguesExpanded),
        ),

        Expanded(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _analoguesExpanded
                ? _buildAnaloguesBody(drug)
                : const SizedBox.shrink(),
          ),
        ),

        if (!_analoguesExpanded) const Spacer(),

        // ── Fixed bottom: storage location ──────────────────────────────────
        if (hasStorage) ...[
          _buildDivider(),
          _StorageSection(
            drug: drug,
            onChanged: widget.onStorageLocationChanged,
          ),
        ],
      ],
    );
  }

  // ── ЄДК inline card (same style as orders panel) ───────────────────────────

  // ── Section divider ─────────────────────────────────────────────────────────

  Widget _buildDivider() => const Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFFF3F4F6),
      );

  // ── Section header ──────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, {int? count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F3FB),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Color(0xFF1E7DC8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Header: photo + name + meta + instruction link ──────────────────────────

  Widget _buildHeader(Drug drug, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drug photo
            _DrugPhoto(imageUrl: drug.imageUrl),
            const SizedBox(width: 12),

            // Name + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    drug.name,
                    style: const TextStyle(
                      color: Color(0xFF1C1C2E),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildMetaColumn(drug),
                ],
              ),
            ),

            // ── Price (toggle: _showPriceInHeader) ───────────────────────────
            if (_showPriceInHeader && drug.price > 0) ...[
              const SizedBox(width: 8),
              Center(
                child: Text(
                  '${drug.price.toStringAsFixed(2)} ₴',
                  style: const TextStyle(
                    color: Color(0xFF1E7DC8),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Meta column: category / manufacturer / country (vertical) ──────────────

  Widget _buildMetaColumn(Drug drug) {
    final items = <(IconData, String)>[
      if (drug.category.isNotEmpty)
        (Icons.local_pharmacy_outlined, drug.category),
      if (drug.manufacturer.isNotEmpty)
        (Icons.business_outlined, drug.manufacturer),
      if (drug.countryOfOrigin != null)
        (Icons.flag_outlined, drug.countryOfOrigin!),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.$1, size: 12, color: const Color(0xFFB0B5BF)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                item.$2,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11.5,
                  height: 1.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  // ── Intake warning banner ──────────────────────────────────────────────

  Widget _buildWarningBanner(String warning) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFFDBA74)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warning,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }


  // ── Collapsible section header ────────────────────────────────────────────

  Widget _buildAnaloguesBody(Drug drug) {
    if (widget.externalAnalogues.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 14, color: Color(0xFFD1D5DB)),
            const SizedBox(width: 6),
            Text(
              drug.inn != null
                  ? 'Пошук аналогів...'
                  : 'Аналоги відсутні',
              style: TextStyle(
                  color: Colors.grey.shade400, fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Column headers
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: const Row(
            children: [
              SizedBox(width: kColBadge),
              Expanded(
                child: Text('Назва',
                    style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ),
              SizedBox(
                width: 72,
                child: Text('Ціна',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
        // Analogue rows
        Flexible(
          child: ListView(
            children: widget.externalAnalogues.asMap().entries.map((e) =>
                _ExternalAnalogueRow(
                  product: e.value,
                  isEven: e.key.isEven,
                )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsibleHeader(
    String title, {
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  // ── Основні властивості header with instruction icon ──────────────────────

  Widget _buildUsageHeader(Drug drug, BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _usageExpanded = !_usageExpanded),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Основні властивості',
                style: const TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Instruction icon
            GestureDetector(
              onTap: drug.instructionsUrl != null
                  ? () => _openInstruction(context, drug.instructionsUrl!)
                  : null,
              child: Tooltip(
                message: 'Інструкція',
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: drug.instructionsUrl != null
                        ? const Color(0xFFEEF2FF)
                        : const Color(0xFFF4F5F8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: drug.instructionsUrl != null
                          ? const Color(0xFFD6DEFF)
                          : const Color(0xFFE5E7EB),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    Icons.description_rounded,
                    size: 14,
                    color: drug.instructionsUrl != null
                        ? const Color(0xFF1E7DC8)
                        : const Color(0xFFD1D5DB),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _usageExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  // ── Open instruction URL ──────────────────────────────────────────────────

  void _openInstruction(BuildContext context, String url) {
    showInstructionDialog(context, url);
  }

  // ── Batch / serial info (under drug name in header) ────────────────────────

  // _buildBatchInfo moved to _StorageSectionState

  // ── Usage properties grid ───────────────────────────────────────────────────

  Widget _buildUsageProperties(Drug drug) {
    final u = drug.usageInfo!;

    // Dispensing cell
    final dispensingStatus =
        drug.requiresPrescription ? UsageStatus.caution : UsageStatus.ok;
    final dispensingText =
        drug.requiresPrescription ? 'за рецептом' : 'без рецепта';

    // Children cell text
    String childrenText;
    if (u.children == null || u.children == UsageStatus.unknown) {
      childrenText = 'не досліджено';
    } else if (u.children == UsageStatus.contraindicated) {
      childrenText = 'протипоказано';
    } else if (u.childrenFromAge != null) {
      childrenText = 'з ${u.childrenFromAge} років';
    } else {
      childrenText = 'можна';
    }

    final cells = [
      _PropData(Icons.person_outline_rounded, 'Дорослим',
          _statusText(u.adults), u.adults),
      _PropData(Icons.masks_outlined, 'Алергікам',
          _statusText(u.allergics), u.allergics),
      _PropData(Icons.child_care_outlined, 'Дітям', childrenText,
          u.children ?? UsageStatus.unknown),
      _PropData(Icons.pregnant_woman_outlined, 'Вагітним',
          u.pregnantNote ?? _statusText(u.pregnant), u.pregnant),
      _PropData(Icons.baby_changing_station_outlined, 'Годуючим',
          _statusText(u.nursing), u.nursing),
      _PropData(Icons.directions_car_outlined, 'Водіям',
          _statusText(u.drivers), u.drivers),
      _PropData(Icons.water_drop_outlined, 'Діабетикам',
          _statusText(u.diabetics), u.diabetics),
      _PropData(Icons.receipt_long_outlined, 'Умова відпуску',
          dispensingText, dispensingStatus),
    ];

    return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Column(
            children: [
              for (int i = 0; i < cells.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(child: _UsagePropCell(data: cells[i])),
                      const SizedBox(width: 5),
                      Expanded(child: _UsagePropCell(data: cells[i + 1])),
                    ],
                  ),
                ),
            ],
          ),
    );
  }

  String _statusText(UsageStatus s) {
    switch (s) {
      case UsageStatus.ok:
        return 'можна';
      case UsageStatus.caution:
        return 'з обережністю';
      case UsageStatus.contraindicated:
        return 'протипоказано';
      case UsageStatus.unknown:
        return 'не досліджено';
    }
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Editable storage location section
// ─────────────────────────────────────────────────────────────────────────────

class _StorageSection extends StatefulWidget {
  final Drug drug;
  final void Function(StorageLocationType type, String code, bool applyToCart)? onChanged;

  const _StorageSection({required this.drug, this.onChanged});

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  bool _isEditing = false;
  late StorageLocationType _editType;
  late TextEditingController _codeCtrl;
  bool _applyToCart = false;
  final FocusNode _codeFocus = FocusNode();

  // ── Editable location types (robot excluded) ──────────────────────────────
  static const _editableTypes = [
    StorageLocationType.shelf,
    StorageLocationType.showcase,
    StorageLocationType.polka,
  ];

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _StorageSection old) {
    super.didUpdateWidget(old);
    if (old.drug.id != widget.drug.id) {
      _isEditing = false;
    }
  }

  // ── Extract locations from drug ───────────────────────────────────────────
  StorageLocation? get _robotLocation {
    final locs = widget.drug.storageLocations;
    if (locs != null) {
      final r = locs.where((l) => l.type == StorageLocationType.robot);
      if (r.isNotEmpty) return r.first;
    }
    return null;
  }

  /// The single non-robot location to display / edit.
  (StorageLocationType, String, int?) get _editableLocation {
    final locs = widget.drug.storageLocations;
    if (locs != null) {
      final nonRobot = locs.where((l) => l.type != StorageLocationType.robot);
      if (nonRobot.isNotEmpty) {
        final loc = nonRobot.first;
        return (loc.type, loc.code, loc.qty);
      }
    }
    // Fallback to legacy
    if (widget.drug.locationType != null && widget.drug.locationCode != null &&
        widget.drug.locationType != StorageLocationType.robot) {
      return (widget.drug.locationType!, widget.drug.locationCode!, widget.drug.stock);
    }
    return (StorageLocationType.shelf, '', null);
  }

  void _startEditing() {
    final (type, code, _) = _editableLocation;
    setState(() {
      _isEditing = true;
      _editType = type;
      _codeCtrl.text = code;
      _applyToCart = false;
    });
    Future.microtask(() => _codeFocus.requestFocus());
  }

  void _cancel() => setState(() => _isEditing = false);

  void _save() {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    widget.onChanged?.call(_editType, code, _applyToCart);
    setState(() => _isEditing = false);
  }

  // ── Label / icon helpers ──────────────────────────────────────────────────
  static String _typeLabel(StorageLocationType t) {
    switch (t) {
      case StorageLocationType.shelf:    return 'Стелаж';
      case StorageLocationType.showcase: return 'Вітрина';
      case StorageLocationType.polka:    return 'Полиця';
      case StorageLocationType.robot:    return 'Робот';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Text(
            'Місце зберігання',
            style: const TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: location chips + edit
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Robot chip (always read-only)
                    if (_robotLocation != null) ...[
                      _LocationChip(
                        type: StorageLocationType.robot,
                        code: _robotLocation!.code,
                        qty: _robotLocation!.qty,
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Editable non-robot location
                    _isEditing ? _buildEditRow() : _buildReadOnlyRow(),
                  ],
                ),
              ),

              // Right: batch info (Серія, Сер. номер, Штрих-код)
              if (!_isEditing) _buildBatchInfo(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Batch info (right side of storage section) ──────────────────────────
  Widget _buildBatchInfo() {
    final drug = widget.drug;
    final rows = <(String, String)>[
      if (drug.series != null) ('Серія', drug.series!),
      if (drug.barcode != null) ('Штрих-код', drug.barcode!),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: rows.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${r.$1}: ',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                ),
              ),
              Text(
                r.$2,
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  // ── Read-only: chip + pencil ──────────────────────────────────────────────
  Widget _buildReadOnlyRow() {
    final (type, code, qty) = _editableLocation;
    if (code.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        _LocationChip(type: type, code: code, qty: qty),
        const SizedBox(width: 6),
        _EditButton(onTap: _startEditing),
      ],
    );
  }

  // ── Edit mode: dropdown + text field + save/cancel + checkbox ─────────────
  Widget _buildEditRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Controls row
        Row(
          children: [
            // Type dropdown
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F8),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFD1D5DB)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<StorageLocationType>(
                  value: _editType,
                  isDense: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF6B7280)),
                  style: const TextStyle(color: Color(0xFF374151), fontSize: 12, fontWeight: FontWeight.w600),
                  items: _editableTypes.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(_typeLabel(t)),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _editType = v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Code text field
            SizedBox(
              width: 80,
              height: 32,
              child: Center(
                child: TextField(
                  controller: _codeCtrl,
                  focusNode: _codeFocus,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF4F6EF7), width: 1.5),
                  ),
                ),
                  onSubmitted: (_) => _save(),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Save button
            _MiniIconButton(
              icon: Icons.check_rounded,
              color: const Color(0xFF22C55E),
              tooltip: 'Зберегти (Enter)',
              onTap: _save,
            ),
            const SizedBox(width: 4),

            // Cancel button
            _MiniIconButton(
              icon: Icons.close_rounded,
              color: const Color(0xFF9CA3AF),
              tooltip: 'Скасувати (Esc)',
              onTap: _cancel,
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Checkbox: apply to all cart items
        GestureDetector(
          onTap: () => setState(() => _applyToCart = !_applyToCart),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: _applyToCart,
                  onChanged: (v) => setState(() => _applyToCart = v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  activeColor: const Color(0xFF4F6EF7),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Встановити для всіх товарів у кошику',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Pencil (edit) button ──────────────────────────────────────────────────────

class _EditButton extends StatelessWidget {
  final VoidCallback onTap;
  const _EditButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: 'Редагувати місце зберігання',
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF9CA3AF)),
          ),
        ),
      ),
    );
  }
}

// ── Mini icon button (save / cancel) ─────────────────────────────────────────

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _MiniIconButton({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drug photo widget (network image with fallback placeholder)
// ─────────────────────────────────────────────────────────────────────────────

class _DrugPhoto extends StatelessWidget {
  final String? imageUrl;
  const _DrugPhoto({this.imageUrl});

  // imageUrl prefixed with "asset:" → local asset; otherwise treated as network URL.
  bool get _isAsset => imageUrl?.startsWith('asset:') ?? false;
  String get _assetPath => imageUrl!.substring('asset:'.length);

  @override
  Widget build(BuildContext context) {
    return Container(
      // Width fixed; height stretches to match the sibling text column via
      // IntrinsicHeight in the parent Row.
      width: 90,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null
          ? _placeholder()
          : _isAsset
              ? Image.asset(
                  _assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => _placeholder(),
                )
              : Image.network(
                  imageUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                        ),
                  errorBuilder: (context, error, stack) => _placeholder(),
                ),
    );
  }

  Widget _placeholder() => const Icon(
        Icons.medication_outlined,
        size: 30,
        color: Color(0xFFD1D5DB),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}

class _PropData {
  final IconData icon;
  final String label;
  final String value;
  final UsageStatus status;
  const _PropData(this.icon, this.label, this.value, this.status);
}

// ─────────────────────────────────────────────────────────────────────────────
// Usage property cell — white card, icon circle + status badge overlay
// ─────────────────────────────────────────────────────────────────────────────

class _UsagePropCell extends StatelessWidget {
  final _PropData data;
  const _UsagePropCell({required this.data});

  @override
  Widget build(BuildContext context) {
    final (textColor, badgeIcon, badgeColor) = _statusStyle(data.status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon circle with status badge overlay
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0F2F5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(data.icon, size: 14, color: const Color(0xFF6B7280)),
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Icon(badgeIcon, size: 7, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),

          // Label + status text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.label,
                  style: const TextStyle(
                    color: Color(0xFF1C1C2E),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                Text(
                  data.value,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 10.5,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Returns (statusTextColor, badgeIcon, badgeCircleColor)
  (Color, IconData, Color) _statusStyle(UsageStatus s) {
    switch (s) {
      case UsageStatus.ok:
        return (
          const Color(0xFF1E7DC8),
          Icons.check_rounded,
          const Color(0xFF22C55E),
        );
      case UsageStatus.caution:
        return (
          const Color(0xFFD97706),
          Icons.priority_high_rounded,
          const Color(0xFFF59E0B),
        );
      case UsageStatus.contraindicated:
        return (
          const Color(0xFFDC2626),
          Icons.close_rounded,
          const Color(0xFFEF4444),
        );
      case UsageStatus.unknown:
        return (
          const Color(0xFF9CA3AF),
          Icons.remove_rounded,
          const Color(0xFFD1D5DB),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════
// Analogue row (from API search)
// ═══════════════════════════════════════════════════════════════════════════

class _ExternalAnalogueRow extends StatelessWidget {
  final ProductSearchResult product;
  final bool isEven;

  const _ExternalAnalogueRow({
    required this.product,
    required this.isEven,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isEven ? const Color(0xFFFAFBFC) : const Color(0xFFF5F6F8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          // Bonus badge (same style as table A)
          SizedBox(
            width: kColBadge,
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F0E8),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text(
                  '\$',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ),
          // Product name + producer
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (product.producer != null)
                  Text(
                    product.producer!,
                    style: const TextStyle(
                      color: Color(0xFFB0B7C3),
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Price
          SizedBox(
            width: 72,
            child: Text(
              '${product.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Heart icon button for "Рука допомоги"
// ─────────────────────────────────────────────────────────────────────────────

class _HelpingHandButton extends StatelessWidget {
  final Drug drug;
  final bool isAuthorized;
  final int remaining;
  final double? discountPrice;
  final VoidCallback? onRequest;
  final void Function(String phone, double discountPrice, int? fractionalQty)? onAddToCart;

  const _HelpingHandButton({
    required this.drug,
    required this.isAuthorized,
    required this.remaining,
    this.discountPrice,
    this.onRequest,
    this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final active = isAuthorized;
    final color = active ? const Color(0xFFD4637A) : const Color(0xFFD1D5DB);

    return GestureDetector(
      onTap: remaining > 0 ? () => _onTap(context) : null,
      child: Tooltip(
        message: 'Рука допомоги',
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFDF2F4) : const Color(0xFFF4F5F8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? const Color(0xFFF5D0D8) : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          child: Icon(Icons.favorite_rounded, size: 16, color: color),
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    if (!isAuthorized) {
      // Not authorized → open full dialog with phone input
      showDialog(
        context: context,
        builder: (ctx) => HelpingHandDialog(
          drug: drug,
          remaining: remaining,
          onConfirm: (phone, price, fractionalQty) {
            onAddToCart?.call(phone, price, fractionalQty);
          },
        ),
      );
    } else if (discountPrice == null) {
      // Authorized but discount not yet revealed → reveal it
      onRequest?.call();
    } else {
      // Discount already revealed → show popover with price
      _showPricePopover(context);
    }
  }

  void _showPricePopover(BuildContext context) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset offset = box.localToGlobal(Offset.zero);
    final Size size = box.size;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: offset.dy + size.height + 6,
            left: (offset.dx + size.width / 2 - 130)
                .clamp(8.0, MediaQuery.of(ctx).size.width - 268),
            child: Material(
              elevation: 8,
              shadowColor: const Color(0x1A000000),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 260,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEEEFF2)),
                ),
                child: Row(
                  children: [
                    Text(
                      '${drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Color(0xFFD1D5DB),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 13, color: Color(0xFFD4637A)),
                    const SizedBox(width: 8),
                    Text(
                      '${discountPrice!.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                      style: const TextStyle(
                        color: Color(0xFFD4637A),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '-${(drug.price - discountPrice!).toStringAsFixed(2).replaceAll('.', ',')} ₴',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen centered dialog for "Рука допомоги" (when not authorized)
// ─────────────────────────────────────────────────────────────────────────────

class HelpingHandDialog extends StatefulWidget {
  final Drug drug;
  final int remaining;
  /// phone, discountPrice, fractionalQty (null = whole package)
  final void Function(String phone, double discountPrice, int? fractionalQty) onConfirm;

  const HelpingHandDialog({
    super.key,
    required this.drug,
    required this.remaining,
    required this.onConfirm,
  });

  @override
  State<HelpingHandDialog> createState() => _HelpingHandDialogState();
}

class _HelpingHandDialogState extends State<HelpingHandDialog> {
  final _phoneCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  double? _discountPrice;
  bool _isLoading = false;

  /// true = whole package, false = blister (fractional).
  bool _wholePackage = true;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.addListener(_onPhoneChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _phoneFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _phoneCtrl.removeListener(_onPhoneChanged);
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  void _onPhoneChanged() {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 9 && _discountPrice == null && !_isLoading) {
      _checkDiscount(digits);
    }
  }

  Future<void> _checkDiscount(String digits) async {
    setState(() => _isLoading = true);

    final drug = widget.drug;
    final comingPrice = double.tryParse(drug.comingPrice ?? '');

    // Try real FarmaSell API if data available
    if (comingPrice != null && drug.comingCode != null) {
      final sku = drug.skuCode ?? drug.id.replaceFirst('srv_', '');
      final result = await FarmaSellService.getHelpingHandDiscount(
        clientPhone: '+380$digits',
        sku: sku,
        comingPrice: comingPrice,
        comingCode: drug.comingCode!,
      );
      if (!mounted) return;

      if (result.success && result.discountPrice != null) {
        setState(() {
          _discountPrice = result.discountPrice;
          _isLoading = false;
        });
        return;
      }
    } else {
      // Small delay for mock to feel natural
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
    }

    // Fallback: mock discount
    final price = drug.price;
    final pct = price > 100 ? 0.20 : price > 50 ? 0.18 : 0.15;
    setState(() {
      _discountPrice = (price * (1 - pct)).roundToDouble();
      _isLoading = false;
    });
  }

  void _confirm() {
    if (_discountPrice == null) return;
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    Navigator.pop(context);
    final fractionalQty = (!_wholePackage && widget.drug.canSplitByBlister)
        ? 1
        : null;
    widget.onConfirm(digits, _discountPrice!, fractionalQty);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F3FB),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite_rounded,
                      size: 18, color: Color(0xFF1E7DC8)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Рука допомоги',
                        style: TextStyle(
                          color: Color(0xFF1C1C2E),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.drug.name,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F3FB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Залишилось: ${widget.remaining}',
                    style: const TextStyle(
                      color: Color(0xFF1E7DC8),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Phone input
            const Text(
              'Номер телефону клієнта',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _phoneCtrl,
              focusNode: _phoneFocus,
              keyboardType: TextInputType.phone,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C2E),
                letterSpacing: 0.5,
              ),
              decoration: InputDecoration(
                hintText: '050 123 45 67',
                hintStyle: const TextStyle(
                  color: Color(0xFFD1D5DB),
                  fontWeight: FontWeight.w400,
                ),
                prefixText: '+380 ',
                prefixStyle: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF1E7DC8),
                          ),
                        ),
                      )
                    : _discountPrice != null
                        ? const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF22C55E))
                        : null,
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: Color(0xFF1E7DC8), width: 1.5),
                ),
              ),
              onSubmitted: (_) {
                if (_discountPrice != null) _confirm();
              },
            ),

            // Price section (appears after discount is calculated)
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _discountPrice != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE5E7EB),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Old price
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Звичайна ціна',
                                  style: TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${widget.drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                                  style: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: Color(0xFFD1D5DB),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            const Icon(Icons.arrow_forward_rounded,
                                size: 16, color: Color(0xFF1E7DC8)),
                            const SizedBox(width: 14),
                            // New price
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Зі знижкою',
                                  style: TextStyle(
                                    color: Color(0xFF1E7DC8),
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_discountPrice!.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                                  style: const TextStyle(
                                    color: Color(0xFF1C1C2E),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // Savings
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '-${(widget.drug.price - _discountPrice!).toStringAsFixed(2).replaceAll('.', ',')} ₴',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 20),

            // Buttons row
            if (widget.drug.canSplitByBlister && _discountPrice != null) ...[
              // Splittable drug — two add-to-cart buttons: Блістер + Упаковку
              Row(
                children: [
                  // Блістер
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _wholePackage = false);
                        _confirm();
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.grid_view_rounded, size: 16, color: Color(0xFF6B7280)),
                              SizedBox(width: 8),
                              Text(
                                'Блістер',
                                style: TextStyle(
                                  color: Color(0xFF374151),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Упаковку
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _wholePackage = true);
                        _confirm();
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A7FC4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_cart_rounded, size: 16, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Упаковку',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Non-splittable or discount not yet revealed — Cancel + Додати в чек
              Row(
                children: [
                  // Cancel
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Відмінити',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Esc',
                              style: TextStyle(
                                color: Color(0xFFD1D5DB),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Add to cart (whole package)
                  Expanded(
                    child: GestureDetector(
                      onTap: _discountPrice != null ? _confirm : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: _discountPrice != null
                              ? const Color(0xFF4A7FC4)
                              : const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart_rounded,
                              size: 16,
                              color: _discountPrice != null
                                  ? Colors.white
                                  : const Color(0xFF9CA3AF),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Упаковку',
                              style: TextStyle(
                                color: _discountPrice != null
                                    ? Colors.white
                                    : const Color(0xFF9CA3AF),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

