import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/mock_drugs.dart';
import '../data/symptom_categories.dart';
import '../models/cart_item.dart';
import '../models/cart_offer.dart';
import '../models/customer_loyalty.dart';
import '../models/drug.dart';
import '../models/edk_offer.dart';
import '../widgets/action_sidebar.dart';
import '../widgets/cart_panel.dart';
import '../widgets/clear_cart_dialog.dart';
import '../widgets/drug_detail_panel.dart';
import '../widgets/edk_panel.dart';
import '../widgets/customer_auth_card.dart';
import '../widgets/top_bar.dart';
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

  // ── ЄДК (Є Дещо Краще) — pharmaceutical substitution ────────────────────
  EdkOffer? _activeEdkOffer;
  final Set<String> _dismissedEdkDrugIds = {};

  /// Key for accessing CartPanelState (enterCheckout via F5).
  final _cartPanelKey = GlobalKey<CartPanelState>();

  void _toggleCart() {
    setState(() => _cartOpen = !_cartOpen);
    if (_cartOpen) _focusPhoneField();
  }

  /// Focus the loyalty phone field with the cursor after the prefix.
  void _focusPhoneField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final len = _loyaltyPhoneController.text.length;
      _loyaltyPhoneController.selection =
          TextSelection.collapsed(offset: len);
      _loyaltyPhoneFocusNode.requestFocus();
    });
  }

  /// Prevent the cursor / selection from landing inside the "+380 " prefix.
  void _guardPhoneCursor() {
    final sel = _loyaltyPhoneController.selection;
    if (!sel.isValid) return;
    final minOffset = _loyaltyPhonePrefix.length;
    if (sel.baseOffset < minOffset || sel.extentOffset < minOffset) {
      _loyaltyPhoneController.selection =
          TextSelection.collapsed(offset: _loyaltyPhoneController.text.length);
    }
  }

  /// Auth card is visible when a drug row is selected OR cart is open.
  /// Hidden only on the dashboard view (no drug selected, cart closed).
  bool get _showAuthCard => _cartOpen || _selectedDrug != null;

  // ── Customer loyalty (phone auth) ─────────────────────────────────────────
  final _loyaltyPhoneController = TextEditingController();
  final _loyaltyPhoneFocusNode = FocusNode();
  CustomerLoyalty? _customerLoyalty;
  bool _isLoadingLoyalty = false;
  String? _previousCustomerPhone;

  static const _loyaltyPhonePrefix = CustomerAuthCard.loyaltyPhonePrefix;

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
    _loyaltyPhoneController.addListener(_guardPhoneCursor);

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

    // ── Ctrl+digit → fractional qty (blisters) when a row is selected ──────
    if (HardwareKeyboard.instance.isControlPressed) {
      final digit = _ctrlDigitFromKey(event.logicalKey);
      if (digit != null && _selectedDrug != null && _selectedDrug!.stock > 0) {
        if (_selectedDrug!.unitsPerPackage != null) {
          _setFractionalQuantity(_selectedDrug!, digit);
        } else {
          _showFractionalUnavailable();
        }
        return true;
      }
      return false; // other Ctrl combos — pass through
    }

    // Don't intercept system shortcuts (Cmd/Alt)
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }

    // ── F2: toggle cart panel (focus handled inside _toggleCart) ────────────
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      _toggleCart();
      return true;
    }

    // ── F5: enter checkout mode (cart must be open with items) ──────────────
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      if (_cart.isNotEmpty) {
        _loyaltyPhoneFocusNode.unfocus();
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
      } else if (_activeEdkOffer != null) {
        _dismissEdk();
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

    // ── Enter: accept ЄДК offer ──────────────────────────────────────────────
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_activeEdkOffer != null) {
        _addEdkToCart();
        return true;
      }
      return false;
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
    final targetCats = symptomCategories[_selectedSymptom] ?? [];
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
      _activeEdkOffer = null;
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

  CartItem? _getCartItem(String drugId) {
    final idx = _cart.indexWhere((item) => item.drug.id == drugId);
    return idx >= 0 ? _cart[idx] : null;
  }

  void _setQuantity(Drug drug, int qty) {
    final wasInCart = _cart.any((item) => item.drug.id == drug.id);
    setState(() {
      final idx = _cart.indexWhere((item) => item.drug.id == drug.id);
      if (qty <= 0) {
        if (idx >= 0) _cart.removeAt(idx);
      } else {
        final clamped = qty.clamp(1, drug.stock);
        if (idx >= 0) {
          _cart[idx].quantity = clamped;
          _cart[idx].fractionalQty = null; // exit fractional mode
        } else {
          _cart.add(CartItem(drug: drug, quantity: clamped));
        }
      }
    });
    // Show ЄДК offer when a drug is first added to cart
    if (!wasInCart && qty > 0) _tryShowEdk(drug);
  }

  void _setFractionalQuantity(Drug drug, int blisters) {
    if (drug.unitsPerPackage == null) return;
    final wasInCart = _cart.any((item) => item.drug.id == drug.id);
    setState(() {
      final idx = _cart.indexWhere((item) => item.drug.id == drug.id);
      if (blisters <= 0) {
        if (idx >= 0) _cart.removeAt(idx);
      } else {
        final clamped = blisters.clamp(1, drug.unitsPerPackage!);
        if (idx >= 0) {
          _cart[idx].fractionalQty = clamped;
          _cart[idx].quantity = 0;
        } else {
          _cart.add(CartItem(drug: drug, quantity: 0, fractionalQty: clamped));
        }
      }
    });
    if (!wasInCart && blisters > 0) _tryShowEdk(drug);
  }

  /// Map a LogicalKeyboardKey to digit 0-9, or null.
  static int? _ctrlDigitFromKey(LogicalKeyboardKey key) {
    final id = key.keyId;
    if (id >= 0x30 && id <= 0x39) return id - 0x30;
    if (id >= 0x0000000100000060 && id <= 0x0000000100000069) {
      return id - 0x0000000100000060;
    }
    return null;
  }

  void _showFractionalUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Дроблення недоступне для цього препарату'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── ЄДК logic ────────────────────────────────────────────────────────────

  /// Hardcoded EDK offers (simulates external service).
  /// Key = donor drug id, value = replacement offer.
  late final Map<String, EdkOffer> _edkOffers = {
    // Ібупрофен 200мг №20 id:'024' (bonus 8) → Нурофен Експрес id:'009' (bonus 20)
    '024': EdkOffer(
      drug: mockDrugs.firstWhere((d) => d.id == '009'),
      donorDrugId: '024',
      description:
          'Капсульна форма для швидшого всмоктування — '
          'ефект настає вже через 15 хвилин.',
      script:
          'Зверніть увагу, є аналогічний препарат у капсулах — '
          'діє значно швидше. Бажаєте спробувати?',
    ),
    // Парацетамол 500мг №20 id:'001' (bonus 5) → Панадол 500мг №12 id:'031' (bonus 12)
    '001': EdkOffer(
      drug: mockDrugs.firstWhere((d) => d.id == '031'),
      donorDrugId: '001',
      description:
          'Європейська якість, та сама діюча речовина. '
          'Покращена формула для швидшого всмоктування.',
      script:
          'Є такий самий парацетамол європейського виробництва — '
          'діє швидше завдяки покращеній формулі. Рекомендую!',
    ),
    // МІГ 400 №20 id:'025' (bonus 12) → Нурофен форте 400мг id:'035' (bonus 20)
    '025': EdkOffer(
      drug: mockDrugs.firstWhere((d) => d.id == '035'),
      donorDrugId: '025',
      description:
          'Преміальна якість від світового виробника. '
          'Швидкодіюча формула для максимального ефекту.',
      script:
          'Якщо потрібен максимальний ефект — рекомендую цей варіант. '
          'Швидкодіюча формула, перевірена якість.',
    ),
  };

  /// Check and show EDK offer after adding a donor drug to cart.
  void _tryShowEdk(Drug donorDrug) {
    if (_dismissedEdkDrugIds.contains(donorDrug.id)) return;
    final offer = _edkOffers[donorDrug.id];
    if (offer == null) return;
    setState(() => _activeEdkOffer = offer);
  }

  void _addEdkToCart() {
    if (_activeEdkOffer == null) return;
    final replacementDrug = _activeEdkOffer!.drug;
    final donorId = _activeEdkOffer!.donorDrugId;
    setState(() {
      _dismissedEdkDrugIds.add(donorId);
      _activeEdkOffer = null;
      // Add replacement to cart (qty=1) or increment
      final idx = _cart.indexWhere((i) => i.drug.id == replacementDrug.id);
      if (idx >= 0) {
        _cart[idx].quantity =
            (_cart[idx].quantity + 1).clamp(1, replacementDrug.stock);
      } else {
        _cart.add(CartItem(drug: replacementDrug, quantity: 1));
      }
    });
  }

  void _dismissEdk() {
    if (_activeEdkOffer == null) return;
    setState(() {
      _dismissedEdkDrugIds.add(_activeEdkOffer!.donorDrugId);
      _activeEdkOffer = null;
    });
  }

  void _removeFromCart(int index) => setState(() => _cart.removeAt(index));

  void _increaseQty(int index) {
    setState(() {
      final item = _cart[index];
      if (item.isFractional) {
        if (item.fractionalQty! < item.drug.unitsPerPackage!) {
          item.fractionalQty = item.fractionalQty! + 1;
        }
      } else {
        if (item.quantity < item.drug.stock) item.quantity++;
      }
    });
  }

  void _decreaseQty(int index) {
    setState(() {
      final item = _cart[index];
      if (item.isFractional) {
        if (item.fractionalQty! > 1) {
          item.fractionalQty = item.fractionalQty! - 1;
        } else {
          _cart.removeAt(index);
        }
      } else {
        if (item.quantity > 1) {
          item.quantity--;
        } else {
          _cart.removeAt(index);
        }
      }
    });
  }

  double get _cartTotal => _cart.fold(0, (s, i) => s + i.total);
  int get _cartItemCount => _cart.length;

  void _clearCart() {
    // Reset search without triggering _filterDrugs (which would auto-select)
    _searchController.removeListener(_filterDrugs);
    _searchController.clear();
    _searchController.addListener(_filterDrugs);

    setState(() {
      _cart.clear();
      _selectedDrug = null;
      _searchResults = mockDrugs;
      _selectedSymptom = 'Всі';
      _cartOpen = false;
      _resetLoyalty();
      _dismissedEdkDrugIds.clear();
      _activeEdkOffer = null;
    });

    // Unfocus everything — true zero state
    FocusManager.instance.primaryFocus?.unfocus();
  }

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
    _loyaltyPhoneController.removeListener(_guardPhoneCursor);
    _loyaltyPhoneController.text = _loyaltyPhonePrefix;
    _loyaltyPhoneController.addListener(_onLoyaltyPhoneChanged);
    _loyaltyPhoneController.addListener(_guardPhoneCursor);
    _customerLoyalty = null;
    _isLoadingLoyalty = false;
  }

  void _recallPreviousCustomer() {
    if (_previousCustomerPhone == null) return;
    _loyaltyPhoneController.removeListener(_onLoyaltyPhoneChanged);
    _loyaltyPhoneController.removeListener(_guardPhoneCursor);
    _loyaltyPhoneController.text = _previousCustomerPhone!;
    _loyaltyPhoneController.addListener(_onLoyaltyPhoneChanged);
    _loyaltyPhoneController.addListener(_guardPhoneCursor);
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
      promoLabel: 'Акція 1+1',
      script:
          'Рекомендую додати вітамін С — він підтримує імунітет і прискорює одужання при застуді.',
    ),
    CartOffer(
      drug: mockDrugs.firstWhere((d) => d.id == '017'),
      reason: 'Супутній препарат при кашлі',
      script:
          'Для полегшення кашлю рекомендую цей муколітик — він розріджує мокротиння.',
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
      _activeEdkOffer = null;
    });
    final idx = _searchResults.indexWhere((d) => d.id == drug.id);
    if (idx >= 0) _scrollToIndex(idx);
  }

  // ─── Cart dialog ────────────────────────────────────────────────────────────

  void _openClearCartConfirmDialog() {
    showClearCartDialog(
      context: context,
      itemCount: _cartItemCount,
      cartTotal: _cartTotal,
    ).then((confirmed) {
      if (confirmed == true) _clearCart();
    });
  }


  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Column(
        children: [
          const TopBar(),

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
                                      child: CustomerAuthCard(
                                        phoneController: _loyaltyPhoneController,
                                        phoneFocusNode: _loyaltyPhoneFocusNode,
                                        loyalty: _customerLoyalty,
                                        isLoadingLoyalty: _isLoadingLoyalty,
                                        previousCustomerPhone: _previousCustomerPhone,
                                        onConfirmPhone: _confirmPhone,
                                        onRecallPrevious: _recallPreviousCustomer,
                                        onResetLoyalty: () => setState(() => _resetLoyalty()),
                                      ),
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
                                          : _buildRightPanel(),
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
                                child: _buildRightPanel(),
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

  // ── Search bar (open strip, no card) ───────────────────────────────────────

  /// Right panel: switches between EdkPanel and DrugDetailPanel with animation.
  Widget _buildRightPanel() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      // Stretch children to fill available space (prevents vertical centering
      // of ShiftDashboard when drug == null).
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
          ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: _activeEdkOffer != null
          ? EdkPanel(
              key: ValueKey('edk-${_activeEdkOffer!.drug.id}'),
              offer: _activeEdkOffer!,
              onAdd: _addEdkToCart,
              onDismiss: _dismissEdk,
            )
          : DrugDetailPanel(
              key: const ValueKey('detail'),
              drug: _selectedDrug,
              analogues: _analogues,
              onSelectAnalogue: _selectAnalogue,
              earnedAmount: _totalEarned,
            ),
    );
  }

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
                      ...quickSymptoms.map((symptom) {
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

  // ── «Більше…» symptom dropdown ─────────────────────────────────────────────

  Widget _buildMoreSymptomButton() {
    final isActive = moreSymptoms.contains(_selectedSymptom);
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
        for (final group in moreSymptomsGroups) {
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
        final cartItem = _getCartItem(drug.id);
        return DrugListItem(
          key: ValueKey(drug.id),
          drug: drug,
          isSelected: isSelected,
          shouldFocusQty: isSelected && _focusQtyOnSelect,
          isEvenRow: index.isEven,
          cartQuantity: cartItem?.quantity ?? 0,
          cartFractionalQty: cartItem?.fractionalQty,
          pendingInput: isSelected ? _pendingQtyInput : null,
          onTap: () => setState(() {
            _selectedDrug = drug;
            _focusQtyOnSelect = true;
            _cartOpen = false;
            _activeEdkOffer = null;
          }),
          onQuantityChanged: (qty) => _setQuantity(drug, qty),
          onFractionalChanged: (blisters) =>
              _setFractionalQuantity(drug, blisters),
          onFractionalUnavailable: _showFractionalUnavailable,
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
