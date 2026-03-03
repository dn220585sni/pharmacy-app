import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/mock_drugs.dart';
import '../models/cart_item.dart';
import '../models/drug.dart';
import '../widgets/action_sidebar.dart';
import '../widgets/cart_panel.dart';
import '../widgets/drug_detail_panel.dart';
import '../widgets/drug_list_item.dart';

// Approximate item row height for scroll-to-selection
const double _kItemHeight = 49.0;

// Phone prefix formatter — always keeps "+380 ", only digits allowed after it.
class _PhonePrefixFormatter extends TextInputFormatter {
  static const prefix = '+380 ';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;
    if (!text.startsWith(prefix)) {
      final allDigits = text.replaceAll(RegExp(r'\D'), '');
      final afterCode =
          allDigits.startsWith('380') ? allDigits.substring(3) : allDigits;
      final result = prefix + afterCode;
      return TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: result.length),
      );
    }
    final afterPrefix = text.substring(prefix.length);
    final cleanAfter = afterPrefix.replaceAll(RegExp(r'\D'), '');
    final result = prefix + cleanAfter;
    final cursor =
        newValue.selection.end.clamp(prefix.length, result.length).toInt();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  final ScrollController _listScrollController = ScrollController();
  final _searchBarKey = GlobalKey();

  List<Drug> _searchResults = mockDrugs;
  final List<CartItem> _cart = [];
  Drug? _selectedDrug;
  double _totalEarned = 0.0;
  String _selectedSymptom = 'Всі';

  /// Whether the next selection change should auto-focus the qty field.
  /// True when navigating with keyboard or clicking a row.
  /// False when selection changes due to filter (search field must keep focus).
  bool _focusQtyOnSelect = false;

  /// A digit character waiting to be injected into the qty field on the
  /// next frame after focus transfers from the search field.
  String? _pendingQtyInput;

  /// Whether the cart panel is shown in the right column.
  bool _cartOpen = false;

  /// Key for accessing CartPanelState (enterCheckout via F5).
  final _cartPanelKey = GlobalKey<CartPanelState>();

  void _toggleCart() => setState(() => _cartOpen = !_cartOpen);

  /// Auth card is visible when a drug row is selected OR cart is open.
  /// Hidden only on the dashboard view (no drug selected, cart closed).
  bool get _showAuthCard => _cartOpen || _selectedDrug != null;

  // ── Customer loyalty (phone auth) ─────────────────────────────────────────
  final _loyaltyPhoneController = TextEditingController();
  final _loyaltyPhoneFocusNode = FocusNode();
  CustomerLoyalty? _customerLoyalty;
  bool _isLoadingLoyalty = false;
  String? _previousCustomerPhone;

  static const _loyaltyPhonePrefix = '+380 ';

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

    // Loyalty phone setup
    _loyaltyPhoneController.text = _loyaltyPhonePrefix;
    _loyaltyPhoneController.addListener(_onLoyaltyPhoneChanged);

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
    _loyaltyPhoneController.removeListener(_onLoyaltyPhoneChanged);
    _loyaltyPhoneController.dispose();
    _loyaltyPhoneFocusNode.dispose();
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

    // ── F2: toggle cart panel ────────────────────────────────────────────────
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      _toggleCart();
      return true;
    }

    // ── F5: enter checkout mode (cart must be open with items) ──────────────
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      if (_cart.isNotEmpty) {
        if (!_cartOpen) {
          setState(() => _cartOpen = true);
          // Wait for CartPanel to build, then enter checkout
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _cartPanelKey.currentState?.enterCheckout();
          });
        } else {
          _cartPanelKey.currentState?.enterCheckout();
        }
      }
      return true;
    }

    // ── Esc: exit checkout → close cart → clear cart confirm → clear search → deselect
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_cartOpen && _cartPanelKey.currentState?.isInCheckout == true) {
        _cartPanelKey.currentState?.exitCheckout();
      } else if (_cartOpen) {
        setState(() => _cartOpen = false);
      } else if (_cart.isNotEmpty) {
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

  // ── Loyalty phone listener ────────────────────────────────────────────────

  void _onLoyaltyPhoneChanged() {
    // Only rebuild UI so buttons react to digit count changes.
    // Actual fetch happens on Ок press or Enter.
    final digits = _loyaltyPhoneController.text
        .substring(_loyaltyPhonePrefix.length)
        .replaceAll(RegExp(r'\D'), '');

    if (digits.length < 9 && _customerLoyalty != null) {
      setState(() {
        _customerLoyalty = null;
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _fetchLoyalty(String digits) async {
    setState(() => _isLoadingLoyalty = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final lastDigit = int.tryParse(digits[digits.length - 1]) ?? 0;
    final balance = (lastDigit + 1) * 25.0;
    setState(() {
      _customerLoyalty = CustomerLoyalty(
        phone: '+380$digits',
        bonusBalance: balance,
      );
      _isLoadingLoyalty = false;
    });
  }

  void _resetLoyalty() {
    if (_customerLoyalty != null) {
      _previousCustomerPhone = _loyaltyPhoneController.text;
    }
    _loyaltyPhoneController.removeListener(_onLoyaltyPhoneChanged);
    _loyaltyPhoneController.text = _loyaltyPhonePrefix;
    _loyaltyPhoneController.addListener(_onLoyaltyPhoneChanged);
    _customerLoyalty = null;
    _isLoadingLoyalty = false;
  }

  void _recallPreviousCustomer() {
    if (_previousCustomerPhone == null) return;
    _loyaltyPhoneController.removeListener(_onLoyaltyPhoneChanged);
    _loyaltyPhoneController.text = _previousCustomerPhone!;
    _loyaltyPhoneController.addListener(_onLoyaltyPhoneChanged);
    // Extract digits after +380 and fetch
    final digits = _previousCustomerPhone!
        .substring(_loyaltyPhonePrefix.length)
        .replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 9) {
      _fetchLoyalty(digits);
    }
  }

  void _confirmPhone() {
    final digits = _loyaltyPhoneController.text
        .substring(_loyaltyPhonePrefix.length)
        .replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 9 && !_isLoadingLoyalty) {
      _fetchLoyalty(digits);
    }
  }

  // TODO: offers will come from recommendations service based on cart contents
  List<CartOffer> get _recommendedOffers => [
    CartOffer(
      drug: mockDrugs.firstWhere((d) => d.id == '019'),
      reason: 'Підтримка імунітету при застуді',
    ),
    CartOffer(
      drug: mockDrugs.firstWhere((d) => d.id == '017'),
      reason: 'Супутній препарат при кашлі',
    ),
  ];

  void _addOfferToCart(Drug drug) {
    setState(() {
      final idx = _cart.indexWhere((item) => item.drug.id == drug.id);
      if (idx >= 0) {
        if (_cart[idx].quantity < drug.stock) _cart[idx].quantity++;
      } else {
        _cart.add(CartItem(drug: drug, quantity: 1));
      }
    });
  }

  void _processPayment() {
    if (_cart.isEmpty) return;
    // Accumulate earnings BEFORE clearing the cart
    final saleAmount = _cartTotal;
    // Bypass the listener so _filterDrugs doesn't auto-select a drug,
    // then reset everything including _selectedDrug → ShiftDashboard appears.
    _searchController.removeListener(_filterDrugs);
    _searchController.clear();
    _searchController.addListener(_filterDrugs);
    setState(() {
      _totalEarned += saleAmount;
      _cart.clear();
      _selectedDrug = null;   // show ShiftDashboard after payment
      _searchResults = mockDrugs;
      _resetLoyalty();
    });
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
      _cartOpen = false;
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


  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Column(
        children: [
          _buildTopBar(),

          // ── Main content area ──────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Left + Right content columns ──────────────────────────
                  // SearchBar uses GlobalKey to survive layout switches.
                  Expanded(
                    child: _showAuthCard
                        // ── Auth card visible: split layout ────────────
                        ? Column(
                            children: [
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: _buildSearchBar(),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 3,
                                      child: _buildCustomerAuthCard(),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: _buildTableCard(),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 3,
                                      child: _cartOpen
                                          ? CartPanel(
                                              key: _cartPanelKey,
                                              cart: List.unmodifiable(_cart),
                                              offers: _recommendedOffers,
                                              onClear: _clearCart,
                                              onIncrease: _increaseQty,
                                              onDecrease: _decreaseQty,
                                              onRemove: _removeFromCart,
                                              onPay: _processPayment,
                                              onClose: _toggleCart,
                                              onAddOffer: _addOfferToCart,
                                              loyalty: _customerLoyalty,
                                            )
                                          : DrugDetailPanel(
                                              key: const ValueKey('detail'),
                                              drug: _selectedDrug,
                                              analogues: _analogues,
                                              onSelectAnalogue:
                                                  _selectAnalogue,
                                              earnedAmount: _totalEarned,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        // ── Dashboard: full-height right panel ─────────
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Column(
                                  children: [
                                    _buildSearchBar(),
                                    const SizedBox(height: 8),
                                    Expanded(child: _buildTableCard()),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 3,
                                child: DrugDetailPanel(
                                  key: const ValueKey('detail'),
                                  drug: _selectedDrug,
                                  analogues: _analogues,
                                  onSelectAnalogue: _selectAnalogue,
                                  earnedAmount: _totalEarned,
                                ),
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(width: 8),

                  // Quick-action sidebar
                  const ActionSidebar(),
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
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Row(
        children: [
          // АНЦ logo — yellow circle with blue arcs + bold lettering
          ClipOval(
            child: Container(
              width: 40,
              height: 40,
              color: const Color(0xFFFFCC00),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.keyboard_arrow_up_rounded,
                      color: Color(0xFF1E7DC8), size: 13),
                  Text(
                    'АНЦ',
                    style: TextStyle(
                      color: Color(0xFF1E7DC8),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      height: 1.0,
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF1E7DC8), size: 13),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'EuroPharma',
            style: TextStyle(
              color: Color(0xFF1E7DC8),
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
              color: const Color(0xFFE8F3FB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF1E7DC8).withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_outline_rounded,
                    color: Color(0xFF1E7DC8), size: 15),
                SizedBox(width: 5),
                Text('Касир: Микола',
                    style:
                        TextStyle(color: Color(0xFF1E7DC8), fontSize: 13)),
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
    return KeyedSubtree(
      key: _searchBarKey,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search input — arrows intercepted via _searchFocusNode
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
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
                    const BorderSide(color: Color(0xFF1E7DC8), width: 1.5),
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
                                  ? Colors.white
                                  : const Color(0xFFF4F5F8),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Text(
                              symptom,
                              style: TextStyle(
                                color: isActive
                                    ? const Color(0xFF1E7DC8)
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
    ),
    );
  }

  // ── Customer auth card (above right panel) ─────────────────────────────────

  Widget _buildCustomerAuthCard() {
    final hasLoyalty = _customerLoyalty != null;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Header row ─────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E7DC8),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'ЛАЙК',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Картка клієнта',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (hasLoyalty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF10B981), size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '${_customerLoyalty!.bonusBalance.toStringAsFixed(0)} бонусів',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Phone input + action buttons in a row ─────────────────
            Builder(builder: (context) {
              final phoneDigits = _loyaltyPhoneController.text
                  .substring(_loyaltyPhonePrefix.length)
                  .replaceAll(RegExp(r'\D'), '');
              final hasDigits = phoneDigits.isNotEmpty;
              final canConfirm = phoneDigits.length >= 9 &&
                  !hasLoyalty &&
                  !_isLoadingLoyalty;

              return SizedBox(
                height: 34,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _loyaltyPhoneController,
                        focusNode: _loyaltyPhoneFocusNode,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_PhonePrefixFormatter()],
                        onSubmitted: (_) => _confirmPhone(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1C1C2E),
                        ),
                        decoration: InputDecoration(
                          hintText: '+380 __ ___ __ __',
                          hintStyle: const TextStyle(
                              color: Color(0xFFB0B7C3), fontSize: 13),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 10, right: 6),
                            child: Icon(Icons.phone_outlined,
                                size: 15, color: Color(0xFF9CA3AF)),
                          ),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 0, minHeight: 0),
                          suffixIcon: _isLoadingLoyalty
                              ? const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF1E7DC8),
                                    ),
                                  ),
                                )
                              : hasLoyalty
                                  ? GestureDetector(
                                      onTap: () {
                                        setState(() => _resetLoyalty());
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.close_rounded,
                                            size: 16,
                                            color: Color(0xFFB0B7C3)),
                                      ),
                                    )
                                  : null,
                          filled: true,
                          fillColor: hasLoyalty
                              ? const Color(0xFFF0FDF4)
                              : const Color(0xFFF9FAFB),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: hasLoyalty
                                  ? const Color(0xFF10B981)
                                      .withValues(alpha: 0.4)
                                  : const Color(0xFFDDE1F5),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFF1E7DC8)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildAuthActionButton(
                      label: 'Ок',
                      icon: Icons.check_rounded,
                      enabled: canConfirm,
                      primary: true,
                      onTap: _confirmPhone,
                    ),
                    // «Попередній» — visible only before typing digits
                    if (!hasDigits &&
                        !hasLoyalty &&
                        _previousCustomerPhone != null) ...[
                      const SizedBox(width: 4),
                      _buildAuthActionButton(
                        label: 'Попередній',
                        icon: Icons.history_rounded,
                        enabled: !_isLoadingLoyalty,
                        primary: false,
                        onTap: _recallPreviousCustomer,
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthActionButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required bool primary,
    required VoidCallback onTap,
  }) {
    final Color bg = !enabled
        ? const Color(0xFFF4F5F8)
        : primary
            ? const Color(0xFF1E7DC8)
            : const Color(0xFFF4F5F8);
    final Color fg = !enabled
        ? const Color(0xFFB0B7C3)
        : primary
            ? Colors.white
            : const Color(0xFF6B7280);
    final Color borderColor = !enabled
        ? const Color(0xFFE5E7EB)
        : primary
            ? const Color(0xFF1E7DC8)
            : const Color(0xFFE5E7EB);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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
                      ? const Color(0xFF1E7DC8)
                      : const Color(0xFF1C1C2E),
                  fontSize: 13,
                  fontWeight:
                      sel ? FontWeight.w700 : FontWeight.w400,
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
              ? Colors.white
              : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isActive ? _selectedSymptom : 'Більше...',
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFF6B7280),
                fontSize: 12.5,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: isActive
                  ? const Color(0xFF1E7DC8)
                  : const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  // ── Cart chip button (right end of filter row) ─────────────────────────────

  Widget _buildCartChip() {
    final hasItems = _cart.isNotEmpty;
    // Active when cart is open OR has items
    final isActive = hasItems || _cartOpen;
    final isOpen = _cartOpen;

    return GestureDetector(
      onTap: _toggleCart,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF1E7DC8)
              : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? const Color(0xFF1E7DC8)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOpen
                  ? Icons.shopping_cart_rounded
                  : Icons.shopping_cart_outlined,
              color: isActive ? Colors.white : const Color(0xFF9CA3AF),
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(
              hasItems
                  ? '$_cartItemCount поз.  |  ${_cartTotal.toStringAsFixed(2).replaceAll('.', ',')} ₴'
                  : 'Кошик',
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF6B7280),
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            // F2 key hint when cart has items or is open
            if (isActive) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'F2',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
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
            _cartOpen = false;
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
