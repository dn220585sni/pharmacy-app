import 'package:flutter/material.dart';
import '../models/cash_expense.dart';
import '../data/mock_expenses.dart';
import 'hover_icon_button.dart';
import 'callback_request_dialog.dart';
import 'return_flow_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExpensesPanel — Cash register expenses panel shown in the right detail column.
// Two-screen flow: Expense List → Expense Details.
// ─────────────────────────────────────────────────────────────────────────────

class ExpensesPanel extends StatefulWidget {
  final VoidCallback onClose;

  const ExpensesPanel({
    super.key,
    required this.onClose,
  });

  @override
  State<ExpensesPanel> createState() => ExpensesPanelState();
}

class ExpensesPanelState extends State<ExpensesPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  CashExpense? _selectedExpense;
  late List<CashExpense> _allExpenses;
  late List<CashExpense> _filteredExpenses;
  int _highlightedIndex = -1;
  String _selectedFilter = 'Всі';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _selectedRegister;

  bool get _hasQuery => _searchController.text.trim().isNotEmpty;

  List<String> get _availableRegisters {
    final regs = _allExpenses.map((e) => e.register).toSet().toList();
    regs.sort();
    return regs;
  }

  static const _primaryFilters = [
    'Всі',
    'Резерви',
    'Страхові',
    'Реімбурсація',
  ];

  static const _moreFilters = [
    'Повернення',
    'Glovo',
    'Нова пошта',
    'Рецепт 1303',
  ];

  // ── Public methods for PosScreen keyboard cascade ──────────────────────────

  /// Whether the detail screen is open.
  bool get isDetailOpen => _selectedExpense != null;

  /// Close detail → back to list.
  void closeDetail() {
    setState(() => _selectedExpense = null);
  }

  /// Focus the search field (called after panel opens).
  void focusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _allExpenses = List<CashExpense>.from(mockExpenses);
    _filteredExpenses = _allExpenses;
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      var list = List<CashExpense>.from(_allExpenses);

      // Type filter
      if (_selectedFilter != 'Всі') {
        list = list.where((e) {
          switch (_selectedFilter) {
            case 'Резерви':
              return e.type == ExpenseType.reserve;
            case 'Повернення':
              return e.type == ExpenseType.returnOp;
            case 'Страхові':
              return e.type == ExpenseType.insurance;
            case 'Реімбурсація':
              return e.type == ExpenseType.reimbursement;
            case 'Glovo':
              return e.type == ExpenseType.glovo;
            case 'Нова пошта':
              return e.type == ExpenseType.novaPoshta;
            case 'Рецепт 1303':
              return e.type == ExpenseType.prescription1303;
            default:
              return true;
          }
        }).toList();
      }

      // Date range filter
      if (_dateFrom != null) {
        final from = DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
        list = list.where((e) => !e.dateTime.isBefore(from)).toList();
      }
      if (_dateTo != null) {
        final to = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day)
            .add(const Duration(days: 1));
        list = list.where((e) => e.dateTime.isBefore(to)).toList();
      }

      // Register filter
      if (_selectedRegister != null) {
        list = list.where((e) => e.register == _selectedRegister).toList();
      }

      // Text search
      if (query.isNotEmpty) {
        list = list.where((e) {
          return e.receiptNumber.toLowerCase().contains(query) ||
              e.pharmacist.toLowerCase().contains(query) ||
              (e.customerPhone?.toLowerCase().contains(query) ?? false) ||
              (e.reserveNumber?.toLowerCase().contains(query) ?? false) ||
              e.items.any((item) =>
                  item.name.toLowerCase().contains(query));
        }).toList();
        _highlightedIndex = list.isNotEmpty ? 0 : -1;
      } else {
        _highlightedIndex = -1;
      }

      _filteredExpenses = list;
    });
  }

  void _selectFilter(String filter) {
    setState(() => _selectedFilter = filter);
    _applyFilters();
  }

  void _selectExpense(CashExpense expense) {
    setState(() => _selectedExpense = expense);
  }

  void _openHighlighted() {
    if (_highlightedIndex >= 0 &&
        _highlightedIndex < _filteredExpenses.length) {
      _selectExpense(_filteredExpenses[_highlightedIndex]);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
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
        child: _selectedExpense != null
            ? _buildDetailScreen(_selectedExpense!)
            : _buildListScreen(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 1 — EXPENSE LIST
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildListScreen() {
    return Column(
      key: const ValueKey('expenses_list'),
      children: [
        _buildListHeader(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        _buildSearchField(),
        _buildDateAndRegisterRow(),
        _buildFilterChips(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        Expanded(child: _buildExpensesList()),
        _buildListFooter(),
      ],
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined,
              color: Color(0xFF1E7DC8), size: 17),
          const SizedBox(width: 8),
          const Text(
            'Витрати по касі',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Text(
              'Ctrl+E',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Spacer(),
          HoverIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Закрити',
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SizedBox(
        height: 34,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C2E)),
          onSubmitted: (_) => _openHighlighted(),
          decoration: InputDecoration(
            hintText: 'Телефон, препарат, №чеку, №замовлення',
            hintStyle:
                const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 18, color: Color(0xFF9CA3AF)),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 0),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            filled: true,
            fillColor: const Color(0xFFF4F5F8),
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
              borderSide: const BorderSide(color: Color(0xFF1E7DC8)),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 16, color: Color(0xFF9CA3AF)),
                    onPressed: () {
                      _searchController.clear();
                      _searchFocusNode.requestFocus();
                    },
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  // ── Date range & register filter row ──────────────────────────────────────

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('uk'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1E7DC8),
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
    _applyFilters();
  }

  Widget _buildDateChip(String label, DateTime? value, {required bool isFrom}) {
    final hasValue = value != null;
    final text = hasValue
        ? '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}'
        : label;
    return GestureDetector(
      onTap: () => _pickDate(isFrom: isFrom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: hasValue ? const Color(0xFFE8F3FB) : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasValue ? const Color(0xFF1E7DC8) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 12,
                color: hasValue
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFF9CA3AF)),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                color: hasValue
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFF9CA3AF),
              ),
            ),
            if (hasValue) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (isFrom) {
                      _dateFrom = null;
                    } else {
                      _dateTo = null;
                    }
                  });
                  _applyFilters();
                },
                child: const Icon(Icons.close_rounded,
                    size: 12, color: Color(0xFF1E7DC8)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateAndRegisterRow() {
    final registers = _availableRegisters;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Row(
        children: [
          _buildDateChip('від', _dateFrom, isFrom: true),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('—',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
          ),
          _buildDateChip('до', _dateTo, isFrom: false),
          const SizedBox(width: 8),
          if (registers.length > 1)
            Expanded(
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: _selectedRegister != null
                      ? const Color(0xFFE8F3FB)
                      : const Color(0xFFF4F5F8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedRegister != null
                        ? const Color(0xFF1E7DC8)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedRegister,
                    isExpanded: true,
                    isDense: true,
                    icon: const Icon(Icons.expand_more_rounded,
                        size: 16, color: Color(0xFF9CA3AF)),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
                    hint: const Text('Всі каси',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF9CA3AF))),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Всі каси',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF9CA3AF))),
                      ),
                      ...registers.map((r) => DropdownMenuItem<String?>(
                            value: r,
                            child: Text(
                              r.length > 18 ? '${r.substring(0, 18)}…' : r,
                              style: const TextStyle(fontSize: 11),
                            ),
                          )),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedRegister = value);
                      _applyFilters();
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => _selectFilter(label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF1E7DC8)
                : const Color(0xFFF4F5F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF1E7DC8)
                  : const Color(0xFFE5E7EB),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF6B7280),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final isMoreSelected = _moreFilters.contains(_selectedFilter);

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        children: [
          // Primary filter chips
          ..._primaryFilters.map(_buildFilterChip),
          // "Ще..." dropdown chip
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: PopupMenuButton<String>(
              onSelected: (value) => _selectFilter(value),
              offset: const Offset(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              color: Colors.white,
              elevation: 4,
              itemBuilder: (_) => _moreFilters.map((label) {
                final selected = _selectedFilter == label;
                return PopupMenuItem<String>(
                  value: label,
                  height: 36,
                  child: Row(
                    children: [
                      if (selected)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.check_rounded,
                              size: 14, color: Color(0xFF1E7DC8)),
                        ),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected
                              ? const Color(0xFF1E7DC8)
                              : const Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isMoreSelected
                      ? const Color(0xFF1E7DC8)
                      : const Color(0xFFF4F5F8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isMoreSelected
                        ? const Color(0xFF1E7DC8)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isMoreSelected ? _selectedFilter : 'Ще',
                      style: TextStyle(
                        color: isMoreSelected
                            ? Colors.white
                            : const Color(0xFF6B7280),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 14,
                      color: isMoreSelected
                          ? Colors.white
                          : const Color(0xFF9CA3AF),
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

  Widget _buildExpensesList() {
    if (_filteredExpenses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 40, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                _hasQuery || _selectedFilter != 'Всі'
                    ? 'Нічого не знайдено'
                    : 'Немає операцій',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: _filteredExpenses.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, thickness: 1, color: Color(0xFFF4F5F8)),
      itemBuilder: (context, index) {
        final expense = _filteredExpenses[index];
        return _ExpenseListTile(
          expense: expense,
          highlighted: _hasQuery && index == _highlightedIndex,
          onTap: () => _selectExpense(expense),
        );
      },
    );
  }

  Widget _buildListFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          const Icon(Icons.list_alt_rounded,
              size: 14, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 6),
          Text(
            'Операцій: ${_filteredExpenses.length}',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 2 — EXPENSE DETAIL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetailScreen(CashExpense expense) {
    return Column(
      key: ValueKey('expense_detail_${expense.id}'),
      children: [
        _buildDetailHeader(expense),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        // Items list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              for (final item in expense.items)
                if (item.sku.isNotEmpty)
                  _ExpenseItemRow(item: item),
            ],
          ),
        ),
        _buildDetailFooter(expense),
      ],
    );
  }

  Widget _buildDetailHeader(CashExpense expense) {
    final date = expense.dateTime;
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: back + receipt # + status badge
          Row(
            children: [
              HoverIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Назад',
                onTap: () => setState(() => _selectedExpense = null),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.receipt_outlined,
                  size: 15, color: Color(0xFF1E7DC8)),
              const SizedBox(width: 6),
              Text(
                '№${expense.receiptNumber}',
                style: const TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              _ExpenseStatusBadge(expense: expense),
              const Spacer(),
              HoverIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Закрити',
                onTap: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: date, time, pharmacist, type
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _InfoChip(
                  icon: Icons.calendar_today_rounded,
                  label: '$dateStr  $timeStr',
                ),
                _InfoChip(
                  icon: Icons.person_outline_rounded,
                  label: expense.pharmacist,
                ),
                _InfoChip(
                  icon: Icons.storefront_outlined,
                  label: expense.register,
                ),
                if (expense.reserveNumber != null)
                  _InfoChip(
                    icon: Icons.bookmark_outline_rounded,
                    label: 'Р ${expense.reserveNumber}',
                  ),
                if (expense.returnInvoice != null)
                  _InfoChip(
                    icon: Icons.assignment_return_outlined,
                    label: expense.returnInvoice!,
                    color: const Color(0xFFEF4444),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCallbackRequestDialog(
      BuildContext context, CashExpense expense) {
    showDialog(
      context: context,
      builder: (_) => CallbackRequestDialog(expense: expense),
    );
  }

  void _startReturnFlow(BuildContext context, CashExpense expense) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReturnFlowDialog(expense: expense),
    );
  }

  Widget _buildDetailFooter(CashExpense expense) {
    final formattedAmount =
        expense.amount.toStringAsFixed(2).replaceAll('.', ',');
    final minutesSinceSale =
        DateTime.now().difference(expense.dateTime).inMinutes;
    final canReturn =
        expense.status != ExpenseStatus.returned && minutesSinceSale <= 30;
    final returnExpired =
        expense.status != ExpenseStatus.returned && minutesSinceSale > 30;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Total row
          Row(
            children: [
              const Text(
                'Сума:',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$formattedAmount ₴',
                style: const TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Return-expired notice
          if (returnExpired)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 14, color: Color(0xFFB45309)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Повернення товару можливе лише протягом 30 хвилин з моменту покупки',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Primary action: Повернення
          if (expense.status != ExpenseStatus.returned) ...[
            SizedBox(
              width: double.infinity,
              child: _ActionButton(
                label: 'Повернення',
                icon: Icons.assignment_return_outlined,
                isPrimary: true,
                onTap: canReturn
                    ? () => _startReturnFlow(context, expense)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Secondary actions row: Зателефонувати | Друк ▾ | ⋮ Ще
          Row(
            children: [
              // Замовити дзвінок
              Expanded(
                child: _ActionButton(
                  label: 'Замовити дзвінок',
                  icon: Icons.phone_callback_outlined,
                  isPrimary: false,
                  onTap: () => _showCallbackRequestDialog(context, expense),
                ),
              ),
              const SizedBox(width: 6),
              // Друк ▾
              _PopupActionButton(
                icon: Icons.print_outlined,
                label: 'Друк',
                items: const [
                  _PopupActionItem(
                    icon: Icons.receipt_outlined,
                    label: 'Надрукувати чек',
                  ),
                  _PopupActionItem(
                    icon: Icons.description_outlined,
                    label: 'Надрукувати т. накладну',
                  ),
                  _PopupActionItem(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'Відкрити чек PDF (ПРРО)',
                  ),
                  _PopupActionItem(
                    icon: Icons.email_outlined,
                    label: 'Надіслати чек на email',
                  ),
                  _PopupActionItem(
                    icon: Icons.credit_card_outlined,
                    label: 'Термінальний чек',
                  ),
                  _PopupActionItem(
                    icon: Icons.local_pharmacy_outlined,
                    label: 'Чек з лікомату',
                  ),
                ],
                onSelected: (_) {
                  // TODO: handle print action
                },
              ),
              const SizedBox(width: 6),
              // ⋮ Ще
              _PopupActionButton(
                icon: Icons.more_horiz_rounded,
                label: null,
                items: [
                  // ── Каса ──
                  const _PopupActionItem(
                    icon: null,
                    label: 'КАСА',
                    isSectionHeader: true,
                  ),
                  const _PopupActionItem(
                    icon: Icons.point_of_sale_outlined,
                    label: 'Пробити по касі (поточна зміна)',
                  ),
                  const _PopupActionItem(
                    icon: Icons.history_rounded,
                    label: 'Пробити по касі (стара зміна)',
                  ),
                  const _PopupActionItem(
                    icon: Icons.remove_circle_outline,
                    label: 'Зняти позначку пробивання',
                  ),
                  const _PopupActionItem(
                    icon: Icons.queue_outlined,
                    label: 'Т. накладну в чергу',
                  ),
                  // ── Мітки ──
                  const _PopupActionItem(
                    icon: null,
                    label: 'МІТКИ',
                    isSectionHeader: true,
                  ),
                  const _PopupActionItem(
                    icon: Icons.medical_services_outlined,
                    label: 'Рецепт Про-Фарми',
                  ),
                  const _PopupActionItem(
                    icon: Icons.local_hospital_outlined,
                    label: 'Поліклініка / Лікар',
                  ),
                  const _PopupActionItem(
                    icon: Icons.verified_outlined,
                    label: 'Зареєстрований у Хелсі',
                  ),
                  const _PopupActionItem(
                    icon: Icons.currency_exchange_rounded,
                    label: 'Реімбурсація',
                  ),
                  // ── Термінал ──
                  const _PopupActionItem(
                    icon: null,
                    label: 'ТЕРМІНАЛ',
                    isSectionHeader: true,
                  ),
                  const _PopupActionItem(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Заміна терміналу',
                  ),
                  // ── Інше ──
                  const _PopupActionItem(
                    icon: null,
                    label: 'ІНШЕ',
                    isSectionHeader: true,
                  ),
                  _PopupActionItem(
                    icon: Icons.bookmark_add_outlined,
                    label: 'Провести бронювання',
                    enabled: expense.isReserve,
                  ),
                ],
                onSelected: (_) {
                  // TODO: handle action
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

/// Color for the expense type badge.
Color _typeColor(ExpenseType type) {
  switch (type) {
    case ExpenseType.receipt:
      return const Color(0xFF6B7280); // gray
    case ExpenseType.reserve:
      return const Color(0xFF3B82F6); // blue
    case ExpenseType.returnOp:
      return const Color(0xFFEF4444); // red
    case ExpenseType.insurance:
      return const Color(0xFF8B5CF6); // purple
    case ExpenseType.reimbursement:
      return const Color(0xFF059669); // green
    case ExpenseType.glovo:
      return const Color(0xFFD97706); // amber
    case ExpenseType.novaPoshta:
      return const Color(0xFFDC2626); // red-nova
    case ExpenseType.prescription1303:
      return const Color(0xFF0891B2); // cyan
  }
}

/// Expense list tile — shown in the list screen.
class _ExpenseListTile extends StatefulWidget {
  final CashExpense expense;
  final bool highlighted;
  final VoidCallback onTap;

  const _ExpenseListTile({
    required this.expense,
    this.highlighted = false,
    required this.onTap,
  });

  @override
  State<_ExpenseListTile> createState() => _ExpenseListTileState();
}

class _ExpenseListTileState extends State<_ExpenseListTile> {
  bool _hovered = false;

  String get _itemsSummary {
    final realItems =
        widget.expense.items.where((i) => i.sku.isNotEmpty).toList();
    if (realItems.isEmpty) return '';
    if (realItems.length == 1) return realItems.first.name;
    return realItems
        .map((i) => i.name.length > 10 ? '${i.name.substring(0, 10)}…' : i.name)
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    final date = e.dateTime;
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final amountStr = e.amount.toStringAsFixed(2).replaceAll('.', ',');

    Color statusColor;
    switch (e.status) {
      case ExpenseStatus.completed:
        statusColor = const Color(0xFF6B7280);
        break;
      case ExpenseStatus.reserved:
        statusColor = const Color(0xFF3B82F6);
        break;
      case ExpenseStatus.returned:
        statusColor = const Color(0xFFEF4444);
        break;
      case ExpenseStatus.cancelled:
        statusColor = const Color(0xFF9CA3AF);
        break;
    }

    final typeColor = _typeColor(e.type);

    final bg = widget.highlighted
        ? const Color(0xFFEFF6FF)
        : _hovered
            ? const Color(0xFFF9FAFB)
            : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: status dot + receipt # + type badge + amount + chevron
              Row(
                children: [
                  // Status dot
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: e.isReserve ? statusColor : null,
                      border: e.isReserve
                          ? null
                          : Border.all(color: statusColor, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Receipt number
                  Text(
                    '№${e.receiptNumber}',
                    style: const TextStyle(
                      color: Color(0xFF1C1C2E),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // Type badge (hide for regular receipts)
                  if (e.type != ExpenseType.receipt) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        e.typeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: typeColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Amount
                  Text(
                    '$amountStr ₴',
                    style: const TextStyle(
                      color: Color(0xFF1C1C2E),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: _hovered
                        ? const Color(0xFF1E7DC8)
                        : const Color(0xFFD1D5DB),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              // Row 2: date/time + drug names summary
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  '$dateStr $timeStr · $_itemsSummary',
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expense item row — shown in the detail screen.
class _ExpenseItemRow extends StatelessWidget {
  final ExpenseItem item;
  const _ExpenseItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final totalStr = item.total.toStringAsFixed(2).replaceAll('.', ',');
    final priceStr = item.price.toStringAsFixed(2).replaceAll('.', ',');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
            bottom: BorderSide(color: Color(0xFFF4F5F8), width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.medication_outlined,
              size: 16,
              color: Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(width: 10),
          // Center: name + details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    color: Color(0xFF1C1C2E),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item.manufacturer != null) item.manufacturer!,
                    '${item.quantity} шт.',
                    '$priceStr ₴/шт.',
                  ].join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Right: total
          Text(
            '$totalStr ₴',
            style: const TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status badge for expense detail header.
class _ExpenseStatusBadge extends StatelessWidget {
  final CashExpense expense;
  const _ExpenseStatusBadge({required this.expense});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (expense.status) {
      case ExpenseStatus.completed:
        color = const Color(0xFF6B7280);
        break;
      case ExpenseStatus.reserved:
        color = const Color(0xFF3B82F6);
        break;
      case ExpenseStatus.returned:
        color = const Color(0xFFEF4444);
        break;
      case ExpenseStatus.cancelled:
        color = const Color(0xFF9CA3AF);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            expense.statusLabel,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small info chip for detail header metadata.
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Action button for detail footer.
class _ActionButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool isPrimary;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    this.icon,
    required this.isPrimary,
    this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final bgColor = !enabled
        ? const Color(0xFFF4F5F8)
        : widget.isPrimary
            ? (_hovered
                ? const Color(0xFF1A6CB3)
                : const Color(0xFF1E7DC8))
            : (_hovered
                ? const Color(0xFFE5E7EB)
                : const Color(0xFFF4F5F8));
    final fgColor = !enabled
        ? const Color(0xFFD1D5DB)
        : widget.isPrimary
            ? Colors.white
            : const Color(0xFF374151);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: widget.isPrimary
                ? null
                : Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 14, color: fgColor),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: fgColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data class for popup menu items.
class _PopupActionItem {
  final IconData? icon;
  final String label;
  final bool isSectionHeader;
  final bool enabled;

  const _PopupActionItem({
    this.icon,
    required this.label,
    this.isSectionHeader = false,
    this.enabled = true,
  });
}

/// Compact popup button with icon (+ optional label) that opens a grouped menu.
class _PopupActionButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final List<_PopupActionItem> items;
  final ValueChanged<int> onSelected;

  const _PopupActionButton({
    required this.icon,
    this.label,
    required this.items,
    required this.onSelected,
  });

  @override
  State<_PopupActionButton> createState() => _PopupActionButtonState();
}

class _PopupActionButtonState extends State<_PopupActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PopupMenuButton<int>(
        onSelected: widget.onSelected,
        offset: const Offset(0, -8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        color: Colors.white,
        elevation: 6,
        constraints: const BoxConstraints(maxWidth: 260),
        itemBuilder: (_) {
          final entries = <PopupMenuEntry<int>>[];
          for (var i = 0; i < widget.items.length; i++) {
            final item = widget.items[i];
            if (item.isSectionHeader) {
              // Divider before section (except the first)
              if (entries.isNotEmpty) {
                entries.add(const PopupMenuDivider(height: 8));
              }
              entries.add(PopupMenuItem<int>(
                enabled: false,
                height: 28,
                child: Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 0.8,
                  ),
                ),
              ));
            } else {
              entries.add(PopupMenuItem<int>(
                value: i,
                enabled: item.enabled,
                height: 34,
                child: Row(
                  children: [
                    if (item.icon != null) ...[
                      Icon(item.icon, size: 15,
                          color: item.enabled
                              ? const Color(0xFF6B7280)
                              : const Color(0xFFD1D5DB)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: item.enabled
                              ? const Color(0xFF374151)
                              : const Color(0xFFD1D5DB),
                        ),
                      ),
                    ),
                  ],
                ),
              ));
            }
          }
          return entries;
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.label != null ? 10 : 8,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFFE5E7EB)
                : const Color(0xFFF4F5F8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14,
                  color: const Color(0xFF374151)),
              if (widget.label != null) ...[
                const SizedBox(width: 5),
                Text(
                  widget.label!,
                  style: const TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.expand_more_rounded,
                    size: 12, color: Color(0xFF9CA3AF)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

