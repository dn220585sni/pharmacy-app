import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SOCIAL PROJECTS PANEL — right-panel selector for social programs.
// ═════════════════════════════════════════════════════════════════════════════

class SocialProjectsPanel extends StatefulWidget {
  final VoidCallback onClose;
  final String? selectedProject;
  final ValueChanged<String?> onProjectSelected;

  const SocialProjectsPanel({
    super.key,
    required this.onClose,
    required this.selectedProject,
    required this.onProjectSelected,
  });

  @override
  State<SocialProjectsPanel> createState() => SocialProjectsPanelState();
}

class SocialProjectsPanelState extends State<SocialProjectsPanel> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  static const _projects = [
    'Пакунок малюка',
    'єПідтримка',
    'Нацкешбек',
    'Дарниця +',
    'Знижка УБД',
    'Медикард',
    'EPRUF',
    'АЗОВ супровід',
    'Серце Азовсталі',
    'Серце Азовсталі Ліки',
    'Асістанс',
    'Карітас',
    'Сонафарм',
  ];

  List<String> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _projects;
    return _projects.where((p) => p.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void focusSearch() {
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
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
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            _buildSearchField(),
            const SizedBox(height: 4),
            Expanded(child: _buildProjectsList()),
            if (widget.selectedProject != null) ...[
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              _buildSelectedFooter(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.volunteer_activism_rounded,
                size: 16, color: Color(0xFF1E7DC8)),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Соціальні проекти',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C2E))),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.close,
                  size: 14, color: Color(0xFF9CA3AF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Пошук програми...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            prefixIcon: const Icon(Icons.search, size: 18,
                color: Color(0xFF9CA3AF)),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
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
              borderSide: const BorderSide(
                  color: Color(0xFF1E7DC8), width: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProjectsList() {
    final filtered = _filtered;

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.search_off, size: 32, color: Color(0xFFD1D5DB)),
            SizedBox(height: 8),
            Text('Програму не знайдено',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final project = filtered[index];
        final isSelected = widget.selectedProject == project;

        return GestureDetector(
          onTap: () {
            widget.onProjectSelected(isSelected ? null : project);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFEFF6FF)
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFFF3F4F6),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _projectIcon(project),
                  size: 18,
                  color: isSelected
                      ? const Color(0xFF1E7DC8)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    project,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? const Color(0xFF1E7DC8)
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle,
                      size: 18, color: Color(0xFF1E7DC8)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectedFooter() {
    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        children: [
          const Icon(Icons.check_circle,
              size: 16, color: Color(0xFF16A34A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.selectedProject!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C2E),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => widget.onProjectSelected(null),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Скасувати',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFDC2626))),
            ),
          ),
        ],
      ),
    );
  }

  IconData _projectIcon(String project) {
    switch (project) {
      case 'Пакунок малюка':
        return Icons.child_care;
      case 'єПідтримка':
        return Icons.support_rounded;
      case 'Нацкешбек':
        return Icons.currency_exchange;
      case 'Дарниця +':
        return Icons.add_circle_outline;
      case 'Знижка УБД':
        return Icons.military_tech;
      case 'Медикард':
        return Icons.credit_card;
      case 'EPRUF':
        return Icons.verified_outlined;
      case 'АЗОВ супровід':
        return Icons.shield_outlined;
      case 'Серце Азовсталі':
      case 'Серце Азовсталі Ліки':
        return Icons.favorite_border;
      case 'Асістанс':
        return Icons.handshake_outlined;
      case 'Карітас':
        return Icons.diversity_1;
      case 'Сонафарм':
        return Icons.local_pharmacy_outlined;
      default:
        return Icons.volunteer_activism;
    }
  }
}
