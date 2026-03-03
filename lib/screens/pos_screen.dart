import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/mock_drugs.dart';
import '../models/cart_item.dart';
import '../models/drug.dart';
import '../widgets/action_sidebar.dart';
import '../widgets/cart_dialog.dart';
import '../widgets/drug_detail_panel.dart';
import '../widgets/drug_list_item.dart';

// Approximate item row height for scroll-to-selection
const double _kItemHeight = 49.0;

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  final ScrollController _listScrollController = ScrollController();

  List<Drug> _searchResults = mockDrugs;
  final List<CartItem> _cart = [];
  Drug? _selectedDrug;
  String _selectedSymptom = 'Всі';

  /// Whether the next selection change should auto-focus the qty field.
  /// True when navigating with keyboard or clicking a row.
  /// False when selection changes due to filter (search field must keep focus).
  bool _focusQtyOnSelect = false;

  /// A digit character waiting to be injected into the qty field on the
  /// next frame after focus transfers from the search field.
  String? _pendingQtyInput;

  // ── Symptom filters ───────────────────────────────────────────────────────

  static const List<String> _quickSymptoms = [
    'Всі', 'Біль', 'Нежить', 'Застуда', 'Кашель', 'Отруєння', 'Стрес', 'Безсоння',
  ];

  /// Groups of symptoms shown in the "Більше…" dropdown.
  /// Each sub-list is visually separated by a divider.
  static const List<List<String>> _moreSymptomsGroups = [
    ['Головний біль', 'Біль у горлі', 'Зубний біль', 'Біль у спині'],
    ['Кашель сухий', 'Кашель вологий'],
    ['Важкість у шлунку', 'Печія', 'Діарея', 'Нудота'],
    ['Алергія', 'Проблеми зі шкірою'],
    ['Підвищений тиск', 'Понижений тиск'],
    ['Загальна слабкість'],
  ];

  // Flat list for membership checks
  static const List<String> _moreSymptoms = [
    'Головний біль', 'Біль у горлі', 'Зубний біль', 'Біль у спині',
    'Кашель сухий', 'Кашель вологий',
    'Важкість у шлунку', 'Печія', 'Діарея', 'Нудота',
    'Алергія', 'Проблеми зі шкірою',
    'Підвищений тиск', 'Понижений тиск',
    'Загальна слабкість',
  ];

  /// Maps each symptom to the drug categories it should surface.
  /// Empty list → show all (used for 'Всі').
  static const Map<String, List<String>> _symptomCategories = {
    'Всі':               [],
    'Біль':              ['Знеболюючі'],
    'Нежить':            ['Антигістамінні', 'Пульмонологія'],
    'Застуда':           ['Знеболюючі', 'Антибіотики', 'Пульмонологія'],
    'Кашель':            ['Пульмонологія'],
    'Отруєння':          ['Гастроентерологія'],
    'Стрес':             ['Вітаміни'],
    'Головний біль':     ['Знеболюючі'],
    'Біль у горлі':      ['Знеболюючі', 'Антибіотики'],
    'Зубний біль':       ['Знеболюючі'],
    'Біль у спині':      ['Знеболюючі'],
    'Кашель сухий':      ['Пульмонологія'],
    'Кашель вологий':    ['Пульмонологія'],
    'Важкість у шлунку': ['Гастроентерологія'],
    'Печія':             ['Гастроентерологія'],
    'Діарея':            ['Гастроентерологія'],
    'Нудота':            ['Гастроентерологія'],
    'Алергія':           ['Антигістамінні'],
    'Проблеми зі шкірою': [],
    'Підвищений тиск':   ['Кардіологія'],
    'Понижений тиск':    ['Кардіологія'],
    'Безсоння':          [],
    'Загальна слабкість': ['Вітаміни'],
  };

  @override
  void initState() {
    super.initState();

    // Intercept ↑↓ in the search field before TextField consumes them
    _searchFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveSelection(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveSelection(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    _searchController.addListener(_filterDrugs);

    // Auto-select first row on startup
    if (_searchResults.isNotEmpty) {
      _selectedDrug = _searchResults.first;
    }

    // Global key handler: redirect printable chars to search field
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  /// Global key handler: redirect printable characters to the search field
  /// unless the search field or a digit-input (qty) field already has focus.
  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // Don't intercept system shortcuts (Cmd/Ctrl/Alt)
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }

    // ── Esc: clear search field OR open clear-cart confirmation ─────────────
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_cart.isNotEmpty) {
        _openClearCartConfirmDialog();
      } else if (_searchController.text.isNotEmpty) {
        _searchController.clear();
        setState(() => _selectedDrug = null);
      } else if (_selectedDrug != null) {
        setState(() => _selectedDrug = null);
      }
      return true;
    }

    final character = event.character;
    if (character == null || character.isEmpty) return false;

    // Skip control characters (Enter, Tab, newline, etc.)
    final code = character.codeUnitAt(0);
    if (code < 32 || code == 127) return false;

    final isDigit = code >= 48 && code <= 57;

    // Digit pressed while search is focused + a drug with stock is selected
    // → route the digit to the qty field instead of appending to the query.
    if (isDigit &&
        _searchFocusNode.hasFocus &&
        _selectedDrug != null &&
        _selectedDrug!.stock > 0) {
      setState(() {
        _focusQtyOnSelect = true;
        _pendingQtyInput = character;
      });
      // Clear pending input after the next frame (it will have been consumed).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _pendingQtyInput = null);
      });
      return true;
    }

    // Search field already has focus — let it handle naturally
    if (_searchFocusNode.hasFocus) return false;

    // If a qty TextField has focus and the key is a digit — don't intercept,
    // let the digit go to the qty field as intended.
    if (isDigit && FocusManager.instance.primaryFocus != null &&
        FocusManager.instance.primaryFocus != _searchFocusNode) {
      return false;
    }

    // Redirect to search field, starting a fresh query.
    // Insert the character in a post-frame callback so it lands AFTER the
    // native text-input connection for the search field is established —
    // otherwise macOS discards the first character during the focus handoff.
    _searchFocusNode.requestFocus();
    final redirectChar = character;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchController.value = TextEditingValue(
        text: redirectChar,
        selection: TextSelection.collapsed(offset: redirectChar.length),
      );
    });
    return true;
  }

  // ─── Drug list logic ───────────────────────────────────────────────────────

  void _filterDrugs() {
    final query = _searchController.text.toLowerCase();
    final targetCats = _symptomCategories[_selectedSymptom] ?? [];
    setState(() {
      _searchResults = mockDrugs.where((drug) {
        final matchesQuery = query.isEmpty ||
            drug.name.toLowerCase().contains(query) ||
            drug.manufacturer.toLowerCase().contains(query);
        final matchesSymptom = _selectedSymptom == 'Всі' ||
            targetCats.contains(drug.category);
        return matchesQuery && matchesSymptom;
      }).toList();

      // Keep current selection if it's still in results;
      // otherwise fall back to the first result.
      _focusQtyOnSelect = false; // Don't steal focus from search field
      if (_searchResults.isNotEmpty) {
        final stillVisible = _selectedDrug != null &&
            _searchResults.any((d) => d.id == _selectedDrug!.id);
        if (!stillVisible) {
          _selectedDrug = _searchResults.first;
        }
      } else {
        _selectedDrug = null;
      }
    });
  }

  /// Move keyboard selection by [delta] rows (+1 down, -1 up).
  void _moveSelection(int delta) {
    if (_searchResults.isEmpty) return;

    final currentIdx = _selectedDrug == null
        ? -1
        : _searchResults.indexWhere((d) => d.id == _selectedDrug!.id);
    final newIdx = (currentIdx + delta).clamp(0, _searchResults.length - 1);

    if (newIdx == currentIdx && _selectedDrug != null) return;

    setState(() {
      _selectedDrug = _searchResults[newIdx];
      _focusQtyOnSelect = true;
    });

    _scrollToIndex(newIdx);
  }

  void _scrollToIndex(int index) {
    if (!_listScrollController.hasClients) return;
    final pos = _listScrollController.position;
    final itemTop = index * _kItemHeight;
    final itemBottom = itemTop + _kItemHeight;

    if (itemTop < pos.pixels) {
      _listScrollController.animateTo(
        itemTop,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    } else if (itemBottom > pos.pixels + pos.viewportDimension) {
      _listScrollController.animateTo(
        itemBottom - pos.viewportDimension,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  // ─── Cart logic ────────────────────────────────────────────────────────────

  int _getCartQuantity(String drugId) {
    final idx = _cart.indexWhere((item) => item.drug.id == drugId);
    return idx >= 0 ? _cart[idx].quantity : 0;
  }

  void _setQuantity(Drug drug, int qty) {
    setState(() {
      final idx = _cart.indexWhere((item) => item.drug.id == drug.id);
      if (qty <= 0) {
        if (idx >= 0) _cart.removeAt(idx);
      } else {
        final clamped = qty.clamp(1, drug.stock);
        if (idx >= 0) {
          _cart[idx].quantity = clamped;
        } else {
          _cart.add(CartItem(drug: drug, quantity: clamped));
        }
      }
    });
  }

  void _removeFromCart(int index) => setState(() => _cart.removeAt(index));

  void _increaseQty(int index) {
    setState(() {
      if (_cart[index].quantity < _cart[index].drug.stock) {
        _cart[index].quantity++;
      }
    });
  }

  void _decreaseQty(int index) {
    setState(() {
      if (_cart[index].quantity > 1) {
        _cart[index].quantity--;
      } else {
        _cart.removeAt(index);
      }
    });
  }

  double get _cartTotal => _cart.fold(0, (s, i) => s + i.total);
  int get _cartItemCount => _cart.fold(0, (s, i) => s + i.quantity);

  void _clearCart() => setState(() => _cart.clear());

  void _processPayment() {
    if (_cart.isEmpty) return;
    setState(() => _cart.clear());
  }

  // ─── Analogues ─────────────────────────────────────────────────────────────

  List<Drug> get _analogues {
    final group = _selectedDrug?.analogueGroup;
    if (group == null) return [];
    return (mockDrugs
          .where((d) => d.analogueGroup == group && d.id != _selectedDrug!.id)
          .toList()
        ..sort((a, b) =>
            (b.pharmacistBonus ?? 0).compareTo(a.pharmacistBonus ?? 0)));
  }

  void _selectAnalogue(Drug drug) {
    _searchController.text = '';
    _filterDrugs();
    setState(() {
      _selectedDrug = drug;
      _focusQtyOnSelect = true;
    });
    final idx = _searchResults.indexWhere((d) => d.id == drug.id);
    if (idx >= 0) _scrollToIndex(idx);
  }

  // ─── Cart dialog ────────────────────────────────────────────────────────────

  /// Shown when the user presses Esc while the cart has items.
  /// Asks "Ви дійсно хочете очистити кошик?" with Так / Ні buttons.
  void _openClearCartConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 360,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.shopping_cart_outlined,
                      size: 26, color: Color(0xFFEF4444)),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Очистити кошик?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C2E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ви дійсно хочете очистити кошик?\n'
                  '$_cartItemCount поз. на суму '
                  '${_cartTotal.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          side: const BorderSide(
                              color: Color(0xFFE5E7EB)),
                        ),
                        child: const Text(
                          'Ні',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _clearCart();
                          Navigator.of(ctx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Так',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCartDialog() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => CartDialog(
          cart: List.unmodifiable(_cart),
          onClear: () {
            _clearCart();
            setDialogState(() {});
          },
          onIncrease: (i) {
            _increaseQty(i);
            setDialogState(() {});
          },
          onDecrease: (i) {
            _decreaseQty(i);
            setDialogState(() {});
          },
          onRemove: (i) {
            _removeFromCart(i);
            setDialogState(() {});
          },
          onPay: () {
            _processPayment();
            setDialogState(() {});
          },
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Column(
        children: [
          _buildTopBar(),

          // ── Two-column layout ─────────────────────────────────────────────
          // Left:  search bar (chips + cart) + table card
          // Right: full-height drug detail card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left column
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSearchBar(),
                        const SizedBox(height: 8),
                        Expanded(child: _buildTableCard()),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Right column — drug detail card, top-aligned with search field
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: DrugDetailPanel(
                        drug: _selectedDrug,
                        analogues: _analogues,
                        onSelectAnalogue: _selectAnalogue,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Quick-action sidebar
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: ActionSidebar(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border:
            Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF4F6EF7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.local_pharmacy_rounded,
                color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          const Text(
            'ФармаПОС',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 24),
          const Icon(Icons.access_time_rounded,
              color: Color(0xFF9CA3AF), size: 15),
          const SizedBox(width: 5),
          Text(
            _getCurrentDateTime(),
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF4F6EF7).withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_outline_rounded,
                    color: Color(0xFF4F6EF7), size: 15),
                SizedBox(width: 5),
                Text('Касир: Микола',
                    style:
                        TextStyle(color: Color(0xFF4F6EF7), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getCurrentDateTime() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}  '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  // ── Search bar (open strip, no card) ───────────────────────────────────────

  Widget _buildSearchBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search input — arrows intercepted via _searchFocusNode
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            style: const TextStyle(
                color: Color(0xFF1C1C2E), fontSize: 14.5),
            decoration: InputDecoration(
              hintText: 'Пошук за назвою або виробником...',
              hintStyle:
                  const TextStyle(color: Color(0xFFB0B7C3), fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: Color(0xFF9CA3AF), size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () => _searchController.clear(),
                      child: const Icon(Icons.close_rounded,
                          color: Color(0xFFB0B7C3), size: 18),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
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
                    const BorderSide(color: Color(0xFF4F6EF7), width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            ),
          ),
        ),

        // Symptom chips + «Більше…» scroll together; cart is fixed at the right
        SizedBox(
          height: 36,
          child: Row(
            children: [
              // All filter chips + «Більше…» in one scrollable strip
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ..._quickSymptoms.map((symptom) {
                        final isActive = _selectedSymptom == symptom;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedSymptom = symptom;
                            _filterDrugs();
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF4F6EF7)
                                  : const Color(0xFFF4F5F8),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isActive
                                    ? const Color(0xFF4F6EF7)
                                    : const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Text(
                              symptom,
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : const Color(0xFF6B7280),
                                fontSize: 12.5,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      }),
                      // «Більше…» sits inline — visually part of the filter row
                      _buildMoreSymptomButton(),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Cart button — always visible at the far right, never scrolls
              _buildCartChip(),
            ],
          ),
        ),
      ],
    );
  }

  // ── «Більше…» symptom dropdown ─────────────────────────────────────────────

  Widget _buildMoreSymptomButton() {
    final isActive = _moreSymptoms.contains(_selectedSymptom);
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      tooltip: '',
      offset: const Offset(0, 40),
      elevation: 6,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) => setState(() {
        _selectedSymptom = value;
        _filterDrugs();
      }),
      itemBuilder: (context) {
        final List<PopupMenuEntry<String>> items = [];
        bool first = true;
        for (final group in _moreSymptomsGroups) {
          if (!first) items.add(const PopupMenuDivider(height: 8));
          for (final symptom in group) {
            final sel = _selectedSymptom == symptom;
            items.add(PopupMenuItem<String>(
              value: symptom,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                symptom,
                style: TextStyle(
                  color: sel
                      ? const Color(0xFF4F6EF7)
                      : const Color(0xFF1C1C2E),
                  fontSize: 13,
                  fontWeight:
                      sel ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ));
          }
          first = false;
        }
        return items;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF4F6EF7)
              : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFF4F6EF7)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isActive ? _selectedSymptom : 'Більше...',
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF6B7280),
                fontSize: 12.5,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: isActive ? Colors.white : const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  // ── Cart chip button (right end of filter row) ─────────────────────────────

  Widget _buildCartChip() {
    final hasItems = _cart.isNotEmpty;
    return GestureDetector(
      onTap: _openCartDialog,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: hasItems
              ? const Color(0xFF4F6EF7)
              : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasItems
                ? const Color(0xFF4F6EF7)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              color: hasItems ? Colors.white : const Color(0xFF9CA3AF),
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(
              hasItems
                  ? '$_cartItemCount поз.  |  ${_cartTotal.toStringAsFixed(2).replaceAll('.', ',')} ₴'
                  : 'Кошик',
              style: TextStyle(
                color: hasItems ? Colors.white : const Color(0xFF6B7280),
                fontSize: 13,
                fontWeight:
                    hasItems ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Table card (rounded rectangle) ─────────────────────────────────────────

  Widget _buildTableCard() {
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
      child: Column(
        children: [
          _buildTableHeader(),
          Expanded(child: _buildDrugList()),
        ],
      ),
    );
  }

  Widget _buildDrugList() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                color: Colors.grey.shade300, size: 48),
            const SizedBox(height: 10),
            const Text(
              'Нічого не знайдено',
              style: TextStyle(color: Color(0xFFB0B7C3), fontSize: 15),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _listScrollController,
      padding: EdgeInsets.zero,
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final drug = _searchResults[index];
        final isSelected = _selectedDrug?.id == drug.id;
        return DrugListItem(
          key: ValueKey(drug.id),
          drug: drug,
          isSelected: isSelected,
          shouldFocusQty: isSelected && _focusQtyOnSelect,
          isEvenRow: index.isEven,
          cartQuantity: _getCartQuantity(drug.id),
          pendingInput: isSelected ? _pendingQtyInput : null,
          onTap: () => setState(() {
            _selectedDrug = drug;
            _focusQtyOnSelect = true;
          }),
          onQuantityChanged: (qty) => _setQuantity(drug, qty),
          onNavigate: _moveSelection,
        );
      },
    );
  }

  Widget _buildTableHeader() {
    const style = TextStyle(
      color: Color(0xFF9CA3AF),
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
    );

    return Container(
      color: const Color(0xFFF9FAFB),
      child: Column(
        children: [
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const SizedBox(width: kColBadge + 10),
                const Expanded(child: Text('Назва', style: style)),
                SizedBox(
                  width: kColStock,
                  child: const Text('Наявн',
                      textAlign: TextAlign.center, style: style),
                ),
                SizedBox(
                  width: kColDispensed,
                  child: const Text('Відпущ',
                      textAlign: TextAlign.center, style: style),
                ),
                SizedBox(
                  width: kColPrice,
                  child: const Text('Ціна',
                      textAlign: TextAlign.right, style: style),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: kColExpiry,
                  child: const Text('Термін',
                      textAlign: TextAlign.center, style: style),
                ),
                SizedBox(
                  width: kColManufacturer,
                  child: const Text('Виробник',
                      textAlign: TextAlign.right, style: style),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        ],
      ),
    );
  }

}
