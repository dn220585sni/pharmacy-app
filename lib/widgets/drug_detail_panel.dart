import 'package:flutter/material.dart';
import '../models/drug.dart';
import 'drug_list_item.dart'; // for kColBadge

// ─────────────────────────────────────────────────────────────────────────────
// Location chip widget
// ─────────────────────────────────────────────────────────────────────────────

class _LocationChip extends StatelessWidget {
  final StorageLocationType type;
  final String code;
  const _LocationChip({required this.type, required this.code});

  @override
  Widget build(BuildContext context) {
    final isShowcase = type == StorageLocationType.showcase;
    final label =
        isShowcase ? 'Розташування на вітрині' : 'Розташування на стелажу';
    final icon =
        isShowcase ? Icons.storefront_outlined : Icons.view_agenda_outlined;

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
              color: const Color(0xFF4F6EF7),
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

  const DrugDetailPanel({
    super.key,
    required this.drug,
    required this.analogues,
    required this.onSelectAnalogue,
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medication_outlined, size: 48, color: Color(0xFFD1D5DB)),
          SizedBox(height: 12),
          Text(
            'Оберіть препарат',
            style: TextStyle(color: Color(0xFFB0B7C3), fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Main content ────────────────────────────────────────────────────────────

  Widget _buildContent(Drug drug) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(drug),
          _buildDivider(),
          if (drug.usageInfo != null) ...[
            _buildUsageProperties(drug),
            _buildDivider(),
          ],
          _buildAnaloguesSection(),
          if (drug.storageConditions != null ||
              (drug.locationType != null && drug.locationCode != null)) ...[
            _buildDivider(),
            _buildStorageSection(drug),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

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
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Color(0xFF4F6EF7),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drug photo (network image or placeholder)
              _DrugPhoto(imageUrl: drug.imageUrl),
              const SizedBox(width: 12),

              // Name + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 4),
                    Text(
                      '${drug.category}  ·  ${drug.manufacturer}',
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '${drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                          style: const TextStyle(
                            color: Color(0xFF4F6EF7),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${drug.stock} ${drug.unit}',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Instruction link button
          GestureDetector(
            onTap: () {
              // TODO: open instruction URL when url_launcher is added
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined,
                      size: 14, color: Color(0xFF4F6EF7)),
                  SizedBox(width: 6),
                  Text(
                    'Переглянути інструкцію',
                    style: TextStyle(
                      color: Color(0xFF4F6EF7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.open_in_new_rounded,
                      size: 12, color: Color(0xFF9CA3AF)),
                ],
              ),
            ),
          ),
        ],
      ),
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
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Column(
            children: [
              for (int i = 0; i < cells.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: _UsagePropCell(data: cells[i])),
                      const SizedBox(width: 6),
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

  // ── Analogues section ───────────────────────────────────────────────────────

  Widget _buildAnaloguesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
            'Аналоги', count: analogues.isEmpty ? null : analogues.length),
        if (analogues.isEmpty)
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
                    color: Colors.grey.shade400,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          )
        else ...[
          // Column header
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
          ...analogues.asMap().entries.map((e) => _AnalogueDetailRow(
                drug: e.value,
                isEven: e.key.isEven,
                onTap: () => onSelectAnalogue(e.value),
              )),
        ],
      ],
    );
  }

  // ── Storage location section ────────────────────────────────────────────────

  Widget _buildStorageSection(Drug drug) {
    final hasLocation =
        drug.locationType != null && drug.locationCode != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Місце зберігання'),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Physical location row
              if (hasLocation)
                _LocationChip(
                  type: drug.locationType!,
                  code: drug.locationCode!,
                ),

              // Temperature conditions row
              if (drug.storageConditions != null) ...[
                if (hasLocation) const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.thermostat_outlined,
                        size: 14, color: Color(0xFF9CA3AF)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        drug.storageConditions!,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drug photo widget (network image with fallback placeholder)
// ─────────────────────────────────────────────────────────────────────────────

class _DrugPhoto extends StatelessWidget {
  final String? imageUrl;
  const _DrugPhoto({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? Image.network(
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
            )
          : _placeholder(),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
            width: 36,
            height: 36,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0F2F5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(data.icon, size: 18, color: const Color(0xFF6B7280)),
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Icon(badgeIcon, size: 8, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

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
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.value,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 10.5,
                    height: 1.3,
                  ),
                  maxLines: 2,
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
          const Color(0xFF4F6EF7),
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
