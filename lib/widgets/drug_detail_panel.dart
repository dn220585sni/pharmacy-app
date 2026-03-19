import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/drug.dart';
import 'drug_list_item.dart'; // for kColBadge
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

class DrugDetailPanel extends StatelessWidget {
  final Drug? drug;
  final List<Drug> analogues;
  final void Function(Drug) onSelectAnalogue;
  final void Function(StorageLocationType type, String code, bool applyToCart)? onStorageLocationChanged;
  /// Passed through to ShiftDashboard when drug == null.
  final double earnedAmount;

  const DrugDetailPanel({
    super.key,
    required this.drug,
    required this.analogues,
    required this.onSelectAnalogue,
    this.onStorageLocationChanged,
    this.earnedAmount = 0.0,
  });

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
      child: drug == null ? _buildEmptyState() : _buildContent(drug!),
    );
  }

  // ── Empty state ─────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return ShiftDashboard(earnedAmount: earnedAmount);
  }

  // ── Main content ────────────────────────────────────────────────────────────

  Widget _buildContent(Drug drug) {
    final hasStorage = drug.storageConditions != null ||
        drug.storageLocations != null ||
        (drug.locationType != null && drug.locationCode != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Fixed: header ───────────────────────────────────────────────────
        _buildHeader(drug),
        _buildDivider(),

        // ── Показання (indications from Product Browser) ──────────────────
        if (drug.indications != null && drug.indications!.isNotEmpty) ...[
          _buildIndications(drug),
          _buildDivider(),
        ],

        // ── Fixed: usage properties ─────────────────────────────────────────
        if (drug.usageInfo != null) ...[
          _buildUsageProperties(drug),
          _buildDivider(),
        ],

        // ── Fixed: analogues section label + column headers ─────────────────
        _buildSectionHeader(
            'Аналоги', count: analogues.isEmpty ? null : analogues.length),

        if (analogues.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: Color(0xFFD1D5DB)),
                const SizedBox(width: 6),
                Text(
                  'Аналоги відсутні',
                  style: TextStyle(
                      color: Colors.grey.shade400, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const Spacer(),
        ] else ...[
          // Fixed column headers
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

          // ── Scrollable: only the analogue rows ──────────────────────────
          Expanded(
            child: ListView(
              children: analogues.asMap().entries.map((e) => _AnalogueDetailRow(
                    drug: e.value,
                    isEven: e.key.isEven,
                    onTap: () => onSelectAnalogue(e.value),
                  )).toList(),
            ),
          ),
        ],

        // ── Fixed bottom: storage location ──────────────────────────────────
        if (hasStorage) ...[
          _buildDivider(),
          _StorageSection(
            drug: drug,
            onChanged: onStorageLocationChanged,
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

  Widget _buildHeader(Drug drug) {
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          drug.name,
                          style: const TextStyle(
                            color: Color(0xFF1C1C2E),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (drug.instructionsUrl != null)
                        GestureDetector(
                          onTap: () => _openInstruction(drug.instructionsUrl!),
                          child: Tooltip(
                            message: 'Переглянути інструкцію',
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFD6DEFF),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.description_rounded,
                                size: 18,
                                color: Color(0xFF1E7DC8),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _buildMetaLine(drug),
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  _buildBatchInfo(drug),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Meta line: category · manufacturer · country ──────────────────────────

  String _buildMetaLine(Drug drug) {
    final parts = <String>[];
    if (drug.category.isNotEmpty) parts.add(drug.category);
    if (drug.manufacturer.isNotEmpty) parts.add(drug.manufacturer);
    if (drug.countryOfOrigin != null) parts.add(drug.countryOfOrigin!);
    if (drug.applicationMethod != null) parts.add(drug.applicationMethod!);
    return parts.join('  ·  ');
  }

  // ── Open instruction URL ──────────────────────────────────────────────────

  void _openInstruction(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // ── Indications section ───────────────────────────────────────────────────

  Widget _buildIndications(Drug drug) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.medical_information_outlined,
                  size: 14, color: Color(0xFF1E7DC8)),
              SizedBox(width: 6),
              Text(
                'Показання',
                style: TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            drug.indications!,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              height: 1.4,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Batch / serial info (under drug name in header) ────────────────────────

  Widget _buildBatchInfo(Drug drug) {
    final rows = <_InfoRow>[
      if (drug.series != null)
        _InfoRow('Серія', drug.series!),
      if (drug.serialNumber != null)
        _InfoRow('Сер. номер', drug.serialNumber!),
      if (drug.barcode != null)
        _InfoRow('Штрих-код', drug.barcode!),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows.map((r) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Text(
              '${r.label}: ',
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 11.5,
              ),
            ),
            Text(
              r.value,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Основні властивості'),
        Padding(
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
        ),
      ],
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
      ],
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
        color: const Color(0xFFF4F5F8),
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
// Analogue row (inline in detail panel)
// ─────────────────────────────────────────────────────────────────────────────

class _AnalogueDetailRow extends StatelessWidget {
  final Drug drug;
  final bool isEven;
  final VoidCallback onTap;

  const _AnalogueDetailRow({
    required this.drug,
    required this.isEven,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDimmed = (drug.stock == 0 && !drug.isInTransit) || drug.isExpired;
    final textColor =
        isDimmed ? const Color(0xFFB0B7C3) : const Color(0xFF1C1C2E);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: isEven ? Colors.white : const Color(0xFFF8F9FB),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            SizedBox(width: kColBadge, child: _buildBadge()),
            Expanded(
              child: Text(
                drug.name,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                '${drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge() {
    if (drug.isInTransit) {
      return _badgeBox(
        const Color(0xFFF4F5F8),
        const Icon(Icons.local_shipping_outlined,
            size: 14, color: Color(0xFF9CA3AF)),
      );
    }
    if (drug.isExpired || drug.isExpiringSoon) {
      final color =
          drug.isExpired ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
      return _badgeBox(
        color.withValues(alpha: 0.1),
        Icon(Icons.hourglass_bottom_rounded, size: 14, color: color),
      );
    }
    if (drug.pharmacistBonus != null) {
      return _badgeBox(
        const Color(0xFFFFF8E7),
        Text(
          '${drug.pharmacistBonus}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFB8860B),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return const SizedBox(width: kColBadge);
  }

  Widget _badgeBox(Color bg, Widget child) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
