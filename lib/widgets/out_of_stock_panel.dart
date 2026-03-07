import 'package:flutter/material.dart';
import '../models/drug.dart';
import '../models/edk_offer.dart';
import '../models/nearby_pharmacy.dart';

/// Right-panel card shown when a pharmacist selects an out-of-stock drug.
///
/// Two internal states:
///  1. EDK offer active → shows replacement drug + blister/package buttons
///  2. EDK dismissed   → shows nearby pharmacy list + "Замовити" block
class OutOfStockPanel extends StatefulWidget {
  final Drug drug;
  final EdkOffer? edkOffer;
  final VoidCallback onAddPackage;
  final VoidCallback? onAddBlister;
  final VoidCallback onDismissEdk;

  /// Nearby pharmacies that have this drug in stock.
  final List<NearbyPharmacy> nearbyPharmacies;

  /// Whether the loyalty phone number has been entered.
  final bool hasPhone;

  /// Callback to focus the phone input field in the auth card.
  final VoidCallback onFocusPhone;

  /// Called when user confirms reservation at a pharmacy.
  final void Function(NearbyPharmacy pharmacy)? onReserve;

  /// Called when user confirms ordering the drug to this pharmacy.
  final VoidCallback? onOrderForClient;

  const OutOfStockPanel({
    super.key,
    required this.drug,
    this.edkOffer,
    required this.onAddPackage,
    this.onAddBlister,
    required this.onDismissEdk,
    this.nearbyPharmacies = const [],
    this.hasPhone = false,
    required this.onFocusPhone,
    this.onReserve,
    this.onOrderForClient,
  });

  @override
  State<OutOfStockPanel> createState() => OutOfStockPanelState();
}

class OutOfStockPanelState extends State<OutOfStockPanel> {
  bool _edkDismissed = false;
  int? _selectedPharmacyIndex;

  /// 0 = "В аптеці поруч", 1 = "Замовити сюди"
  int _altTab = 0;

  bool get isEdkActive => widget.edkOffer != null && !_edkDismissed;

  /// Statuses that can't be reserved or ordered — no alternative options.
  bool get _hasAlternativeOptions {
    final s =
        widget.drug.availabilityStatus ?? DrugAvailabilityStatus.notOrdered;
    return s != DrugAvailabilityStatus.marketShortage &&
        s != DrugAvailabilityStatus.quarantined;
  }

  void dismissEdk() {
    setState(() => _edkDismissed = true);
    widget.onDismissEdk();
  }

  void _selectPharmacy(int index) {
    setState(() => _selectedPharmacyIndex = index);
    // If no phone → focus the phone field immediately.
    if (!widget.hasPhone) {
      widget.onFocusPhone();
    }
  }

  @override
  void didUpdateWidget(OutOfStockPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drug.id != widget.drug.id) {
      _edkDismissed = false;
      _selectedPharmacyIndex = null;
      _altTab = 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Fixed header: photo + name + instruction icon ──────────────
          _buildHeader(widget.drug),
          // ── Status badge ──────────────────────────────────────────────
          _buildStatusBadge(widget.drug),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),

          // ── Animated body ─────────────────────────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ...previousChildren,
                    ?currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                      parent: animation, curve: Curves.easeOut)),
                  child: child,
                ),
              ),
              child: isEdkActive
                  ? KeyedSubtree(
                      key: const ValueKey('oos-edk'),
                      child: _buildEdkSection(),
                    )
                  : _hasAlternativeOptions
                      ? KeyedSubtree(
                          key: const ValueKey('oos-alt'),
                          child: _buildAlternativeOptions(),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('oos-empty'),
                          child: _buildNoOptionsMessage(),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(Drug drug) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrugPhoto(imageUrl: drug.imageUrl),
            const SizedBox(width: 12),
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
                      GestureDetector(
                        onTap: () {
                          // TODO: open instruction URL
                        },
                        child: Tooltip(
                          message: 'Переглянути інструкцію',
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F4FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.menu_book_rounded,
                              size: 14,
                              color: Color(0xFF1E7DC8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${drug.category}  ·  ${drug.manufacturer}',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATUS BADGE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatusBadge(Drug drug) {
    final status =
        drug.availabilityStatus ?? DrugAvailabilityStatus.notOrdered;

    final (label, icon, color) = _statusInfo(status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static (String, IconData, Color) _statusInfo(DrugAvailabilityStatus s) {
    return switch (s) {
      DrugAvailabilityStatus.marketShortage => (
        'Відсутній на ринку',
        Icons.remove_shopping_cart_outlined,
        const Color(0xFFEF4444),
      ),
      DrugAvailabilityStatus.quarantined => (
        'В карантині',
        Icons.gpp_bad_outlined,
        const Color(0xFFDC2626),
      ),
      DrugAvailabilityStatus.inTransit => (
        'В дорозі',
        Icons.local_shipping_outlined,
        const Color(0xFF1E7DC8),
      ),
      DrugAvailabilityStatus.awaitingReceiving => (
        'В аптеці, очікує приходування',
        Icons.inventory_2_outlined,
        const Color(0xFFF59E0B),
      ),
      DrugAvailabilityStatus.notOrdered => (
        'Не замовлений',
        Icons.remove_circle_outline,
        const Color(0xFF6B7280),
      ),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EDK SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEdkSection() {
    final offer = widget.edkOffer!;
    final drug = offer.drug;
    final bonus = drug.pharmacistBonus;

    return Column(
      children: [
        // ── Scrollable body ──────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              children: [
                // Section label
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Є Дещо Краще',
                        style: TextStyle(
                          color: Color(0xFF1E7DC8),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.edkOffer?.promoLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.edkOffer!.promoLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // Drug photo
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: drug.imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.network(
                            drug.imageUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stack) => _placeholderIcon(),
                          ),
                        )
                      : _placeholderIcon(),
                ),
                const SizedBox(height: 12),

                // Name
                Text(
                  drug.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF1C1C2E),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),

                // Manufacturer + category
                Text(
                  '${drug.manufacturer} · ${drug.category}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),

                // Price + bonus
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                      style: const TextStyle(
                        color: Color(0xFF1C1C2E),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (bonus != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFEF3C7),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$bonus',
                            style: const TextStyle(
                              color: Color(0xFFB45309),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // Script block (speech module)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          const Color(0xFF1E7DC8).withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 15,
                        color: Color(0xFF1E7DC8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          offer.script,
                          style: const TextStyle(
                            color: Color(0xFF1E5A8A),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Bottom buttons ───────────────────────────────────────────────
        _buildEdkButtons(),
      ],
    );
  }

  Widget _buildEdkButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        children: [
          // Primary row: Блістер (optional) + Упаковку
          Row(
            children: [
              if (widget.onAddBlister != null) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onAddBlister,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F5F8),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.grid_view_rounded,
                              size: 15, color: Color(0xFF6B7280)),
                          SizedBox(width: 6),
                          Text(
                            'Блістер',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: GestureDetector(
                  onTap: widget.onAddPackage,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E7DC8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_shopping_cart_rounded,
                            color: Colors.white, size: 15),
                        const SizedBox(width: 6),
                        const Text(
                          'Упаковку',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0x33FFFFFF),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'Enter',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
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
          const SizedBox(height: 8),

          // Dismiss
          GestureDetector(
            onTap: dismissEdk,
            child: Container(
              width: double.infinity,
              height: 36,
              alignment: Alignment.center,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ні, дякую',
                    style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x0F000000),
                      borderRadius: BorderRadius.all(Radius.circular(3)),
                    ),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      child: Text(
                        'Esc',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ALTERNATIVE OPTIONS (after EDK dismissed)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAlternativeOptions() {
    return Column(
      children: [
        // ── Segmented toggle ──────────────────────────────────────────
        _buildAltToggle(),

        // ── Tab body ──────────────────────────────────────────────────
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _altTab == 0
                ? KeyedSubtree(
                    key: const ValueKey('tab-reserve'),
                    child: _buildNearbyTab(),
                  )
                : KeyedSubtree(
                    key: const ValueKey('tab-order'),
                    child: _buildOrderTab(),
                  ),
          ),
        ),

        // ── Bottom: auth warning + action button ──────────────────────
        if (_altTab == 0 && _selectedPharmacyIndex != null)
          _buildActionFooter(
            label: 'Забронювати',
            icon: Icons.bookmark_add_outlined,
            onAction: () {
              final ph =
                  widget.nearbyPharmacies[_selectedPharmacyIndex!];
              widget.onReserve?.call(ph);
            },
          ),
        if (_altTab == 1)
          _buildActionFooter(
            label: 'Замовити',
            icon: Icons.local_shipping_outlined,
            onAction: () => widget.onOrderForClient?.call(),
          ),
      ],
    );
  }

  // ── Segmented toggle ───────────────────────────────────────────────────────

  Widget _buildAltToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            _buildToggleTab(
              index: 0,
              icon: Icons.store_outlined,
              label: 'В аптеці поруч',
              isLeft: true,
            ),
            _buildToggleTab(
              index: 1,
              icon: Icons.local_shipping_outlined,
              label: 'Замовити під клієнта',
              isLeft: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleTab({
    required int index,
    required IconData icon,
    required String label,
    required bool isLeft,
  }) {
    final isActive = _altTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _altTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: double.infinity,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1E7DC8) : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isLeft ? const Radius.circular(7) : Radius.zero,
              right: !isLeft ? const Radius.circular(7) : Radius.zero,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? Colors.white : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive ? Colors.white : const Color(0xFF6B7280),
                    fontSize: 11.5,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 0: Nearby pharmacies ─────────────────────────────────────────────

  Widget _buildNearbyTab() {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: _buildPharmacyList(),
      ),
    );
  }

  // ── Tab 1: Order to this pharmacy ──────────────────────────────────────────

  Widget _buildOrderTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 22,
              color: Color(0xFF1E7DC8),
            ),
          ),
          const SizedBox(height: 12),

          // Title with cashback badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Індивідуальне замовлення',
                style: TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '+кешбек 5%',
                  style: TextStyle(
                    color: Color(0xFFB45309),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            'Препарат «${widget.drug.name}» буде замовлено '
            'та доставлено до цієї аптеки. Клієнту при купівлі '
            'буде нараховано підвищений кешбек 5% на бонусний рахунок.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // Delivery time
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 14, color: Color(0xFF9CA3AF)),
                SizedBox(width: 8),
                Text(
                  'Орієнтовний термін: 1–2 робочих дні',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Pharmacy list ──────────────────────────────────────────────────────────

  Widget _buildPharmacyList() {
    final pharmacies = widget.nearbyPharmacies;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pharmacy rows
          if (pharmacies.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Немає аптек з наявністю поруч',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12.5,
                ),
              ),
            )
          else
            ...List.generate(pharmacies.length, (i) {
              final ph = pharmacies[i];
              final isSelected = _selectedPharmacyIndex == i;
              return _buildPharmacyRow(ph, i, isSelected,
                  isFirst: i == 0,
                  isLast: i == pharmacies.length - 1);
            }),
        ],
      ),
    );
  }

  Widget _buildPharmacyRow(
    NearbyPharmacy ph,
    int index,
    bool isSelected, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    return GestureDetector(
      onTap: () => _selectPharmacy(index),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEEF2FF) : Colors.transparent,
          borderRadius: BorderRadius.vertical(
            top: isFirst ? const Radius.circular(9) : Radius.zero,
            bottom: isLast ? const Radius.circular(9) : Radius.zero,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Radio-like indicator
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF1E7DC8)
                            : const Color(0xFFD1D5DB),
                        width: isSelected ? 5 : 1.5,
                      ),
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Address + hours
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ph.displayAddress,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF1C1C2E)
                                : const Color(0xFF4B5563),
                            fontSize: 12.5,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 11,
                              color: Color(0xFF9CA3AF),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ph.workingHours,
                              style: const TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Price + stock + distance
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${ph.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                        style: const TextStyle(
                          color: Color(0xFF1C1C2E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${ph.stockQty} шт',
                        style: const TextStyle(
                          color: Color(0xFF1E7DC8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (ph.distance != null)
                        Text(
                          ph.distance!,
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 10.5,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!isLast)
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFF0F0F3),
                indent: 42,
              ),
          ],
        ),
      ),
    );
  }

  // ── Unified action footer (reserve / order) ─────────────────────────────────

  Widget _buildActionFooter({
    required String label,
    required IconData icon,
    required VoidCallback onAction,
  }) {
    final authorized = widget.hasPhone;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        children: [
          // Auth warning — blue info card style
          if (!authorized) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFF1E7DC8)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Введіть номер телефону клієнта',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF1E7DC8),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Action button
          GestureDetector(
            onTap: authorized ? onAction : widget.onFocusPhone,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 44,
              decoration: BoxDecoration(
                color: authorized
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      size: 17,
                      color: authorized
                          ? Colors.white
                          : const Color(0xFF9CA3AF)),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: authorized
                          ? Colors.white
                          : const Color(0xFF9CA3AF),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NO OPTIONS (marketShortage / quarantined after EDK dismissed)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNoOptionsMessage() {
    final status =
        widget.drug.availabilityStatus ?? DrugAvailabilityStatus.notOrdered;
    final isQuarantine = status == DrugAvailabilityStatus.quarantined;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isQuarantine
                  ? Icons.gpp_bad_outlined
                  : Icons.remove_shopping_cart_outlined,
              size: 24,
              color: const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isQuarantine
                ? 'Препарат наразі в карантині'
                : 'Препарат відсутній на ринку',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isQuarantine
                ? 'Замовлення та бронювання недоступні до завершення перевірки якості.'
                : 'Замовлення та бронювання недоступні — виробник тимчасово не постачає цей препарат.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _placeholderIcon() {
    return const Center(
      child: Icon(
        Icons.medication_rounded,
        size: 36,
        color: Color(0xFFD1D5DB),
      ),
    );
  }
}

// ── Drug photo (mirrors DrugDetailPanel._DrugPhoto) ──────────────────────────

class _DrugPhoto extends StatelessWidget {
  final String? imageUrl;
  const _DrugPhoto({this.imageUrl});

  bool get _isAsset => imageUrl?.startsWith('asset:') ?? false;
  String get _assetPath => imageUrl!.substring('asset:'.length);

  @override
  Widget build(BuildContext context) {
    return Container(
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
