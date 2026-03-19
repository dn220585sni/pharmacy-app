import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/cart_offers.dart';
import '../data/edk_offers.dart';
import '../data/mock_drugs.dart';
import '../services/auth_service.dart';
import '../services/drug_service.dart';
import '../services/loyalty_service.dart';
import '../services/product_browser_service.dart';
import '../data/symptom_categories.dart';
import '../models/cart_item.dart';
import '../models/cart_offer.dart';
import '../models/customer_loyalty.dart';
import '../models/drug.dart';
import '../mixins/edk_state_mixin.dart';
import '../models/edk_offer.dart';
import '../widgets/action_sidebar.dart';
import '../widgets/cart_panel.dart';
import '../widgets/clear_cart_dialog.dart';
import '../widgets/drug_detail_panel.dart';
import '../widgets/edk_panel.dart';
import '../widgets/customer_auth_card.dart';
import '../data/mock_orders.dart';
import '../models/internet_order.dart';
import '../widgets/orders_panel.dart';
import '../widgets/pharmacist_picker_dialog.dart';
import '../widgets/expenses_panel.dart';
import '../widgets/order_success_dialog.dart';
import '../widgets/out_of_stock_panel.dart';
import '../widgets/reservation_success_dialog.dart';
import '../widgets/prescription_panel.dart';
import '../widgets/social_projects_panel.dart';
import '../models/prescription.dart';
import '../data/mock_nearby_pharmacies.dart';
import '../models/nearby_pharmacy.dart';
import '../widgets/top_bar.dart';
import '../widgets/drug_list_item.dart';
import '../utils/fuzzy_search.dart';

// Approximate item row height for scroll-to-selection
const double _kItemHeight = 49.0;

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with EdkStateMixin {
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

  // ── Pharmacist (from GetUsers) ──────────────────────────────────────────────
  List<PharmacistInfo> _pharmacists = [];
  PharmacistInfo? _currentPharmacist;

  // ── Server lookup (barcode + name search) ────────────────────────────────
  Timer? _barcodeLookupTimer;
  Timer? _nameSearchTimer;
  bool _isServerLookup = false;

  // ── Product Browser (drug safety tags) ──────────────────────────────────
  /// Drug IDs we've already tried fetching from Product Browser.
  final _productBrowserFetched = <String>{};

  /// A digit character waiting to be injected into the qty field on the
  /// next frame after focus transfers from the search field.
  String? _pendingQtyInput;

  /// Whether the cart panel is shown in the right column.
  bool _cartOpen = false;

  /// Whether the internet orders panel is shown in the right column.
  bool _ordersOpen = false;

  /// Whether the cash expenses panel is shown in the right column.
  bool _expensesOpen = false;

  /// Key for accessing OrdersPanelState (for Esc cascade).
  final _ordersPanelKey = GlobalKey<OrdersPanelState>();

  /// Key for accessing ExpensesPanelState (for Esc cascade).
  final _expensesPanelKey = GlobalKey<ExpensesPanelState>();

  /// Key for accessing CartPanelState (enterCheckout via F5).
  final _cartPanelKey = GlobalKey<CartPanelState>();

  /// Key for accessing OutOfStockPanelState (keyboard handling).
  final _outOfStockPanelKey = GlobalKey<OutOfStockPanelState>();

  /// Whether the e-Prescription panel is shown in the right column.
  bool _prescriptionOpen = false;

  /// Key for accessing PrescriptionPanelState (Esc cascade).
  final _prescriptionPanelKey = GlobalKey<PrescriptionPanelState>();

  /// Whether the social projects panel is shown in the right column.
  bool _socialProjectsOpen = false;

  /// Currently selected social project (shared with cart).
  String? _selectedSocialProject;

  /// Key for accessing SocialProjectsPanelState.
  final _socialProjectsPanelKey = GlobalKey<SocialProjectsPanelState>();

  void _toggleCart() {
    setState(() {
      _cartOpen = !_cartOpen;
      if (_cartOpen) {
        _ordersOpen = false;
        _expensesOpen = false;
        _prescriptionOpen = false;
        _socialProjectsOpen = false;
      }
    });
    if (_cartOpen) _focusPhoneField();
  }

  void _toggleOrders() {
    setState(() {
      _ordersOpen = !_ordersOpen;
      if (_ordersOpen) {
        _cartOpen = false;
        _expensesOpen = false;
        _prescriptionOpen = false;
        _socialProjectsOpen = false;
      }
    });
    if (_ordersOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ordersPanelKey.currentState?.focusSearch();
      });
    }
  }

  void _toggleExpenses() {
    setState(() {
      _expensesOpen = !_expensesOpen;
      if (_expensesOpen) {
        _cartOpen = false;
        _ordersOpen = false;
        _prescriptionOpen = false;
        _socialProjectsOpen = false;
      }
    });
    if (_expensesOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _expensesPanelKey.currentState?.focusSearch();
      });
    }
  }

  void _togglePrescription() {
    setState(() {
      _prescriptionOpen = !_prescriptionOpen;
      if (_prescriptionOpen) {
        _cartOpen = false;
        _ordersOpen = false;
        _expensesOpen = false;
        _socialProjectsOpen = false;
      }
    });
    if (_prescriptionOpen) {
      _searchFocusNode.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _prescriptionPanelKey.currentState?.focusSearch();
      });
    }
  }

  void _toggleSocialProjects() {
    setState(() {
      _socialProjectsOpen = !_socialProjectsOpen;
      if (_socialProjectsOpen) {
        _cartOpen = false;
        _ordersOpen = false;
        _expensesOpen = false;
        _prescriptionOpen = false;
      }
    });
    if (_socialProjectsOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _socialProjectsPanelKey.currentState?.focusSearch();
      });
    }
  }

  void _addPrescriptionToCart(
      List<PrescriptionMatch> selectedMatches, Prescription rx) {
    setState(() {
      for (final match in selectedMatches) {
        _cart.add(CartItem(
          drug: match.drug,
          quantity: match.selectedQuantity,
          prescriptionData: PrescriptionCartData(
            prescriptionNumber: rx.number,
            reimbursementPrice: match.reimbursementPrice,
            copayment: match.copayment,
            programName: rx.programName,
            prescriptionType: rx.type,
          ),
        ));
      }
      _prescriptionOpen = false;
      _cartOpen = true;
    });
    // Open cart panel for scanning → then F5 to checkout
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
  bool get _showAuthCard => _cartOpen || _ordersOpen || _expensesOpen || _prescriptionOpen || _socialProjectsOpen || _selectedDrug != null;

  // ── Customer loyalty (phone auth) ─────────────────────────────────────────
  final _loyaltyPhoneController = TextEditingController();
  final _loyaltyPhoneFocusNode = FocusNode();
  CustomerLoyalty? _customerLoyalty;
  bool _isLoadingLoyalty = false;
  String? _previousCustomerPhone;

  static const _loyaltyPhonePrefix = CustomerAuthCard.loyaltyPhonePrefix;

  /// Whether the customer has been authorized via loyalty phone.
  bool get _isCustomerAuthorized => _customerLoyalty != null;

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

    // Global key handler: redirect printable chars to search field
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);

    // Load pharmacists from server and auto-show picker
    _loadPharmacists(autoShow: true);
  }

  Future<void> _loadPharmacists({bool autoShow = false}) async {
    try {
      final users = await AuthService.getUsers();
      if (!mounted) return;
      users.sort((a, b) => a.user.toLowerCase().compareTo(b.user.toLowerCase()));
      setState(() => _pharmacists = users);
      if (autoShow && _currentPharmacist == null && users.isNotEmpty) {
        _showPharmacistPicker();
      }
    } catch (_) {
      // Silently ignore — pharmacist list stays empty
    }
  }

  void _showPharmacistPicker() {
    if (_pharmacists.isEmpty) {
      _loadPharmacists(autoShow: true);
      return;
    }
    showPharmacistPicker(context, _pharmacists).then((selected) {
      if (selected != null && mounted) {
        setState(() => _currentPharmacist = selected);
      }
    });
  }

  @override
  void dispose() {
    _barcodeLookupTimer?.cancel();
    _nameSearchTimer?.cancel();
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

    // ══════════════════════════════════════════════════════════════════════
    // PRESCRIPTION PANEL — absolute minimal handler.
    // On macOS desktop, HardwareKeyboard handlers can suppress the
    // platform text-input channel (insertText: / interpretKeyEvents:).
    // By returning false at the very top — before ANY event inspection —
    // we guarantee the platform delivers characters to the focused
    // TextField inside the prescription panel.
    // Esc is handled locally inside PrescriptionPanel (Focus.onKeyEvent).
    // ══════════════════════════════════════════════════════════════════════
    if (_prescriptionOpen) {
      // Ctrl+R: toggle prescription panel (close it)
      if (HardwareKeyboard.instance.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.keyR) {
        _togglePrescription();
        return true;
      }
      // Esc: close detail → close panel (macOS TextField blocks Focus.onKeyEvent)
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_prescriptionPanelKey.currentState?.isDetailOpen == true) {
          _prescriptionPanelKey.currentState?.closeDetail();
        } else {
          _togglePrescription();
        }
        return true;
      }
      return false; // everything else — completely transparent
    }

    if (_socialProjectsOpen) {
      // Esc: close social projects panel
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _toggleSocialProjects();
        return true;
      }
      return false; // let text input work in search field
    }

    // Don't intercept keys when a dialog/overlay is open (e.g. pharmacist picker)
    if (ModalRoute.of(context)?.isCurrent != true) return false;

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
      // ── Ctrl+I: toggle internet orders panel ─────────────────────────────
      if (event.logicalKey == LogicalKeyboardKey.keyI) {
        _toggleOrders();
        return true;
      }
      // ── Ctrl+E: toggle cash expenses panel ─────────────────────────────
      if (event.logicalKey == LogicalKeyboardKey.keyE) {
        _toggleExpenses();
        return true;
      }
      // ── Ctrl+R: toggle e-Prescription panel ────────────────────────────
      if (event.logicalKey == LogicalKeyboardKey.keyR) {
        _togglePrescription();
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

    // ── F5: enter checkout / process payment ───────────────────────────────
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      if (_cart.isNotEmpty) {
        _loyaltyPhoneFocusNode.unfocus();
        if (!_cartOpen) {
          // Cart closed → open cart + enter checkout
          setState(() => _cartOpen = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _cartPanelKey.currentState?.enterCheckout();
          });
        } else if (_cartPanelKey.currentState?.isInCheckout != true) {
          // Cart open, not in checkout → enter checkout
          _cartPanelKey.currentState?.enterCheckout();
        } else {
          // Already in checkout → process payment
          _cartPanelKey.currentState?.processPayment();
        }
      }
      return true;
    }

    // ── F10: switch payment method to card ───────────────────────────────────
    if (event.logicalKey == LogicalKeyboardKey.f10) {
      if (_cart.isNotEmpty && _cartOpen) {
        _loyaltyPhoneFocusNode.unfocus();
        if (_cartPanelKey.currentState?.isInCheckout != true) {
          // Not in checkout yet → enter checkout first, then switch to card
          _cartPanelKey.currentState?.enterCheckout();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _cartPanelKey.currentState?.switchToCard();
          });
        } else {
          _cartPanelKey.currentState?.switchToCard();
        }
      }
      return true;
    }

    // ── Esc: exit checkout → close cart → close orders → clear cart confirm → clear search → deselect
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_cartOpen && _cartPanelKey.currentState?.isInCheckout == true) {
        _cartPanelKey.currentState?.exitCheckout();
      } else if (_cartOpen) {
        setState(() => _cartOpen = false);
      } else if (_ordersOpen && _ordersPanelKey.currentState?.isInCheckout == true) {
        _ordersPanelKey.currentState?.exitOrderCheckout();
      } else if (_ordersOpen && _ordersPanelKey.currentState?.isEdkActive == true) {
        _ordersPanelKey.currentState?.dismissEdk();
      } else if (_ordersOpen && _ordersPanelKey.currentState?.isDetailOpen == true) {
        _ordersPanelKey.currentState?.closeDetail();
      } else if (_ordersOpen && _ordersPanelKey.currentState?.isDisbandedOpen == true) {
        _ordersPanelKey.currentState?.closeDisbanded();
      } else if (_ordersOpen) {
        setState(() => _ordersOpen = false);
      } else if (_expensesOpen && _expensesPanelKey.currentState?.isDetailOpen == true) {
        _expensesPanelKey.currentState?.closeDetail();
      } else if (_expensesOpen) {
        setState(() => _expensesOpen = false);
      } else if (_socialProjectsOpen) {
        setState(() => _socialProjectsOpen = false);
      } else if (_outOfStockPanelKey.currentState?.isEdkActive == true) {
        _outOfStockPanelKey.currentState?.dismissEdk();
      } else if (activeEdkOffer != null) {
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

    // ── Enter: accept ЄДК offer (but not when phone field is focused) ────────
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      // Phone field has priority — let Enter confirm the phone number
      if (_loyaltyPhoneFocusNode.hasFocus) return false;

      // Orders EDK: Enter adds whole package
      if (_ordersOpen &&
          _ordersPanelKey.currentState?.isEdkActive == true) {
        _ordersPanelKey.currentState?.acceptEdkPackage();
        return true;
      }
      // Out-of-stock EDK: Enter adds whole package
      if (_outOfStockPanelKey.currentState?.isEdkActive == true &&
          _selectedDrug != null &&
          _selectedDrug!.isOutOfStock) {
        _addOosEdkPackage(_selectedDrug!);
        return true;
      }
      // Standard EDK
      if (activeEdkOffer != null) {
        _addEdkToCart();
        return true;
      }
      return false;
    }

    // ── When orders/expenses panel is open, don't process characters ────────
    if (_expensesOpen || _ordersOpen) return false;

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
    final query = _searchController.text.trim();
    final targetCats = symptomCategories[_selectedSymptom] ?? [];
    setState(() {
      if (query.isEmpty) {
        // No query — show all (filtered by symptom only).
        _searchResults = mockDrugs.where((drug) {
          return _selectedSymptom == 'Всі' ||
              targetCats.contains(drug.category);
        }).toList();
      } else {
        // Score every drug with fuzzy matching, filter & sort.
        final scored = <MapEntry<Drug, double>>[];
        for (final drug in mockDrugs) {
          final matchesSymptom = _selectedSymptom == 'Всі' ||
              targetCats.contains(drug.category);
          if (!matchesSymptom) continue;
          final score = drugMatchScore(query, drug);
          if (score > 0) scored.add(MapEntry(drug, score));
        }
        scored.sort((a, b) => b.value.compareTo(a.value));
        _searchResults = scored.map((e) => e.key).toList();
      }

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

    // ── Server barcode lookup ──────────────────────────────────────────────
    // If the query looks like a barcode (8-13 digits), ask the live server.
    _barcodeLookupTimer?.cancel();
    _nameSearchTimer?.cancel();
    if (RegExp(r'^\d{8,13}$').hasMatch(query)) {
      _barcodeLookupTimer = Timer(
        const Duration(milliseconds: 400),
        () => _lookupBarcodeOnServer(query),
      );
    } else if (query.length >= 2) {
      // ── Server name search ────────────────────────────────────────────
      _nameSearchTimer = Timer(
        const Duration(milliseconds: 500),
        () => _searchByNameOnServer(query),
      );
    }
  }

  /// Search drugs by name on Caché server; merge results into table.
  Future<void> _searchByNameOnServer(String query) async {
    if (!mounted) return;
    setState(() => _isServerLookup = true);

    try {
      final items = await DrugService.searchByName(query);
      if (!mounted) return;

      // Ignore if user already changed the search query.
      if (_searchController.text.trim() != query) {
        setState(() => _isServerLookup = false);
        return;
      }

      if (items.isEmpty) {
        setState(() => _isServerLookup = false);
        return;
      }

      // Sort: in-stock first, then by name.
      items.sort((a, b) {
        if (a.qty > 0 && b.qty <= 0) return -1;
        if (a.qty <= 0 && b.qty > 0) return 1;
        return a.name.compareTo(b.name);
      });

      // Convert server items to Drug objects.
      final serverDrugs = items.map((item) {
        final locations = <StorageLocation>[];
        if (item.shelf.isNotEmpty) {
          locations.add(StorageLocation(
            type: StorageLocationType.shelf,
            code: item.shelf,
            qty: item.qty,
          ));
        }
        return Drug(
          id: 'srv_${item.ids}',
          name: item.name,
          manufacturer: item.manufacturer,
          category: '',
          price: item.price,
          stock: item.qty,
          unit: 'шт',
          locationCode: item.shelf.isNotEmpty ? item.shelf : null,
          storageLocations: locations.isNotEmpty ? locations : null,
        );
      }).toList();

      setState(() {
        // Remove old server drugs, prepend new ones before mock results.
        final mockResults =
            _searchResults.where((d) => !d.id.startsWith('srv_')).toList();
        _searchResults = [...serverDrugs, ...mockResults];
        // Select first result if nothing selected.
        if (_selectedDrug == null ||
            !_searchResults.any((d) => d.id == _selectedDrug!.id)) {
          _selectedDrug =
              _searchResults.isNotEmpty ? _searchResults.first : null;
        }
        _isServerLookup = false;
      });
      // Fetch safety tags for the selected drug
      if (_selectedDrug != null) {
        _fetchProductBrowserInfo(_selectedDrug!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isServerLookup = false);
    }
  }

  // ── Product Browser: auto-fetch safety tags ──────────────────────────────

  /// Fetch drug safety tags from Product Browser API (anc.ua).
  /// Called when a drug is selected that doesn't have usageInfo yet.
  void _fetchProductBrowserInfo(Drug drug) {
    // Skip if already has usage info or already tried
    if (drug.usageInfo != null) return;
    if (_productBrowserFetched.contains(drug.id)) return;
    _productBrowserFetched.add(drug.id);

    // Build slug from drug name + article ID.
    // Server drugs have id like "srv_12345" — extract the numeric part.
    final articleId = drug.id.replaceFirst('srv_', '');

    // Fire-and-forget async fetch
    ProductBrowserService.fetchByNameAndId(drug.name, articleId).then((result) {
      if (!mounted || result == null) return;

      final usageInfo = result.toUsageInfo();
      if (usageInfo == null) return;

      // Update the drug in _searchResults and _selectedDrug
      setState(() {
        final updatedDrug = drug.copyWithUsageInfo(
          usageInfo,
          newImageUrl: result.imageUrl,
        );

        _searchResults = _searchResults.map((d) {
          return d.id == drug.id ? updatedDrug : d;
        }).toList();

        if (_selectedDrug?.id == drug.id) {
          _selectedDrug = updatedDrug;
        }
      });
    }).catchError((_) {
      // Silently ignore — product browser is optional enhancement
    });
  }

  /// Call Caché GetSKUprice by barcode; if found, insert Drug at top of results.
  ///
  /// Uses [DrugService.getStockAndPrices] with the `barcode` parameter
  /// so we get name, price, stock, and location in a single request.
  Future<void> _lookupBarcodeOnServer(String barcode) async {
    if (!mounted) return;
    setState(() => _isServerLookup = true);

    try {
      final result = await DrugService.getStockAndPrices('', barcode: barcode);
      if (!mounted) return;

      // Ignore if user already changed the search query.
      if (_searchController.text.trim() != barcode) {
        setState(() => _isServerLookup = false);
        return;
      }

      if (result.found) {
        // Build storage locations from server fields.
        final locations = <StorageLocation>[];
        if ((result.stelazh ?? '').isNotEmpty) {
          locations.add(StorageLocation(
            type: StorageLocationType.shelf,
            code: result.stelazh!,
            qty: result.totalStock,
          ));
        }
        if ((result.vitrina ?? '').isNotEmpty) {
          locations.add(StorageLocation(
            type: StorageLocationType.showcase,
            code: result.vitrina!,
            qty: 0,
          ));
        }
        if ((result.polka ?? '').isNotEmpty) {
          locations.add(StorageLocation(
            type: StorageLocationType.polka,
            code: result.polka!,
            qty: 0,
          ));
        }
        if ((result.robot ?? '').isNotEmpty) {
          locations.add(StorageLocation(
            type: StorageLocationType.robot,
            code: result.robot!,
            qty: 0,
          ));
        }

        final drug = Drug(
          id: 'srv_$barcode',
          name: result.name ?? 'Невідомо',
          manufacturer: result.manufacturer ?? '',
          category: '',
          price: result.retailPrice,
          stock: result.totalStock,
          unit: 'шт',
          barcode: barcode,
          locationCode: result.stelazh,
          storageLocations: locations.isNotEmpty ? locations : null,
        );

        setState(() {
          // Remove previous server drug if any, then prepend.
          _searchResults = [
            drug,
            ..._searchResults.where((d) => !d.id.startsWith('srv_')),
          ];
          _selectedDrug = drug;
          _isServerLookup = false;
        });

        _scrollToIndex(0);
        _fetchProductBrowserInfo(drug);
      } else {
        setState(() => _isServerLookup = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isServerLookup = false);
    }
  }

  /// Move keyboard selection by [delta] rows (+1 down, -1 up).
  void _moveSelection(int delta) {
    if (_searchResults.isEmpty) return;

    final currentIdx = _selectedDrug == null
        ? -1
        : _searchResults.indexWhere((d) => d.id == _selectedDrug!.id);
    final newIdx = (currentIdx + delta).clamp(0, _searchResults.length - 1);

    if (newIdx == currentIdx && _selectedDrug != null) return;

    final newDrug = _searchResults[newIdx];
    setState(() {
      _selectedDrug = newDrug;
      _focusQtyOnSelect = true;
      activeEdkOffer = null;
    });

    _scrollToIndex(newIdx);
    _fetchProductBrowserInfo(newDrug);
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

  /// EDK offers: donor drug id → replacement offer.
  late final Map<String, EdkOffer> _edkOffers =
      buildRetailEdkOffers(mockDrugs);

  /// Check and show EDK offer after adding a donor drug to cart.
  void _tryShowEdk(Drug donorDrug) {
    tryActivateEdk(donorDrug.id, _edkOffers);
  }

  /// Accept EDK: add 1 package of replacement, remove donor from cart.
  void _addEdkToCart() {
    if (activeEdkOffer == null) return;
    final replacement = activeEdkOffer!.drug;
    final donorId = activeEdkOffer!.donorDrugId;
    setState(() {
      dismissedEdkIds.add(donorId);
      activeEdkOffer = null;
      // Remove the donor — replacement substitutes it.
      _cart.removeWhere((i) => i.drug.id == donorId);
      final idx = _cart.indexWhere((i) => i.drug.id == replacement.id);
      if (idx >= 0) {
        if (_cart[idx].quantity < replacement.stock) _cart[idx].quantity++;
      } else {
        _cart.add(CartItem(drug: replacement, quantity: 1));
      }
      _selectedDrug = replacement;
    });
    final ri = _searchResults.indexWhere((d) => d.id == replacement.id);
    if (ri >= 0) _scrollToIndex(ri);
  }

  /// Accept EDK as blister: add 1 blister of replacement, remove donor.
  void _addEdkBlisterToCart() {
    if (activeEdkOffer == null) return;
    final replacement = activeEdkOffer!.drug;
    final donorId = activeEdkOffer!.donorDrugId;
    if (replacement.unitsPerPackage == null) return;
    setState(() {
      dismissedEdkIds.add(donorId);
      activeEdkOffer = null;
      _cart.removeWhere((i) => i.drug.id == donorId);
      final idx = _cart.indexWhere((i) => i.drug.id == replacement.id);
      if (idx >= 0) {
        final current = _cart[idx].fractionalQty ?? 0;
        _cart[idx].fractionalQty =
            (current + 1).clamp(1, replacement.unitsPerPackage!);
        _cart[idx].quantity = 0;
      } else {
        _cart.add(
            CartItem(drug: replacement, quantity: 0, fractionalQty: 1));
      }
      _selectedDrug = replacement;
    });
    final ri = _searchResults.indexWhere((d) => d.id == replacement.id);
    if (ri >= 0) _scrollToIndex(ri);
  }

  void _dismissEdk() => dismissActiveEdk();

  // ── OOS (Out-of-Stock) EDK actions ──────────────────────────────────────

  /// Add EDK replacement for an out-of-stock drug (whole package).
  void _addOosEdkPackage(Drug oosDrug) {
    final offer = _edkOffers[oosDrug.id];
    if (offer == null) return;
    final replacement = offer.drug;
    setState(() {
      final idx = _cart.indexWhere((i) => i.drug.id == replacement.id);
      if (idx >= 0) {
        if (_cart[idx].quantity < replacement.stock) _cart[idx].quantity++;
      } else {
        _cart.add(CartItem(drug: replacement, quantity: 1));
      }
      _selectedDrug = replacement;
    });
    final ri = _searchResults.indexWhere((d) => d.id == replacement.id);
    if (ri >= 0) _scrollToIndex(ri);
  }

  /// Add EDK replacement for an out-of-stock drug (1 blister).
  void _addOosEdkBlister(Drug oosDrug) {
    final offer = _edkOffers[oosDrug.id];
    if (offer == null) return;
    final replacement = offer.drug;
    if (replacement.unitsPerPackage == null) return;
    setState(() {
      final idx = _cart.indexWhere((i) => i.drug.id == replacement.id);
      if (idx >= 0) {
        final current = _cart[idx].fractionalQty ?? 0;
        _cart[idx].fractionalQty =
            (current + 1).clamp(1, replacement.unitsPerPackage!);
        _cart[idx].quantity = 0;
      } else {
        _cart.add(
            CartItem(drug: replacement, quantity: 0, fractionalQty: 1));
      }
      _selectedDrug = replacement;
    });
    final ri = _searchResults.indexWhere((d) => d.id == replacement.id);
    if (ri >= 0) _scrollToIndex(ri);
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

  void _reserveAtPharmacy(NearbyPharmacy pharmacy) {
    final drugName = _selectedDrug?.name ?? '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReservationSuccessDialog(
        drugName: drugName,
        pharmacyAddress: pharmacy.displayAddress,
      ),
    ).then((_) {
      _clearCart();
    });
  }

  void _orderForClient() {
    final drugName = _selectedDrug?.name ?? '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrderSuccessDialog(drugName: drugName),
    ).then((_) {
      _clearCart();
    });
  }

  void _clearCart() {
    // Reset search without triggering _filterDrugs (which would auto-select)
    _searchController.removeListener(_filterDrugs);
    _searchController.clear();
    _searchController.addListener(_filterDrugs);

    _barcodeLookupTimer?.cancel();
    _nameSearchTimer?.cancel();
    setState(() {
      _cart.clear();
      _selectedDrug = null;
      _searchResults = mockDrugs;
      _selectedSymptom = 'Всі';
      _cartOpen = false;
      _prescriptionOpen = false;
      _socialProjectsOpen = false;
      _selectedSocialProject = null;
      _isServerLookup = false;
      _resetLoyalty();
      clearEdkState();
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

    try {
      // Call SPL checkCard with phone number (+380 prefix)
      final result = await LoyaltyService.checkCard('+380$digits');
      if (!mounted) return;

      if (!result.success) {
        setState(() => _isLoadingLoyalty = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.errorMsg ?? 'Картку не знайдено'),
            duration: const Duration(seconds: 2),
          ));
        }
        return;
      }

      // Mask the phone number: +38050***9993
      final masked = _maskPhone(digits);
      _loyaltyPhoneController.removeListener(_onLoyaltyPhoneChanged);
      _loyaltyPhoneController.removeListener(_guardPhoneCursor);
      _loyaltyPhoneController.text = masked;
      _loyaltyPhoneController.addListener(_onLoyaltyPhoneChanged);
      _loyaltyPhoneController.addListener(_guardPhoneCursor);

      setState(() {
        _customerLoyalty = CustomerLoyalty(
          phone: '+380$digits',
          bonusBalance: result.balanceAfter,
          cardNo: result.cardNo,
          firstName: result.firstName,
          lastName: result.lastName,
        );
        _isLoadingLoyalty = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingLoyalty = false);
    }
  }

  /// Format: +38050***9993 — show operator code + last 4 digits, mask the middle.
  static String _maskPhone(String digits) {
    // digits = "501234567" (9 digits after 380)
    if (digits.length < 9) return '+380$digits';
    final operator = digits.substring(0, 2);  // e.g. "50"
    final last4 = digits.substring(digits.length - 4); // e.g. "4567"
    final maskedMiddle = '*' * (digits.length - 2 - 4); // e.g. "***"
    return '+380$operator$maskedMiddle$last4';
  }

  void _resetLoyalty() {
    if (_customerLoyalty != null) {
      // Store full phone (e.g. "+380 501234567"), not masked
      _previousCustomerPhone = '$_loyaltyPhonePrefix${_customerLoyalty!.phone.substring(4)}';
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

  static final List<CartOffer> _allOffers = buildCartOffers(mockDrugs);

  List<CartOffer> get _recommendedOffers {
    final cartIds = _cart.map((item) => item.drug.id).toSet();
    return _allOffers.where((o) => !cartIds.contains(o.drug.id)).toList();
  }

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

  void _addOfferBlisterToCart(Drug drug) {
    if (drug.unitsPerPackage == null) return;
    setState(() {
      final idx = _cart.indexWhere((item) => item.drug.id == drug.id);
      if (idx >= 0) {
        final current = _cart[idx].fractionalQty ?? 0;
        _cart[idx].fractionalQty =
            (current + 1).clamp(1, drug.unitsPerPackage!);
        _cart[idx].quantity = 0;
      } else {
        _cart.add(CartItem(drug: drug, quantity: 0, fractionalQty: 1));
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

  /// Called by OrdersPanel after successful internet order payment.
  /// Accumulates pharmacist bonuses and resets to zero state.
  void _onOrderPaid(double amount) {
    _searchController.removeListener(_filterDrugs);
    _searchController.clear();
    _searchController.addListener(_filterDrugs);
    setState(() {
      _totalEarned += amount;
      _ordersOpen = false;
      _cart.clear();
      _selectedDrug = null;
      _searchResults = mockDrugs;
      _selectedSymptom = 'Всі';
      _resetLoyalty();
      clearEdkState();
    });
    FocusManager.instance.primaryFocus?.unfocus();
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
      activeEdkOffer = null;
    });
    final idx = _searchResults.indexWhere((d) => d.id == drug.id);
    if (idx >= 0) _scrollToIndex(idx);
  }

  // ─── Storage location editing ────────────────────────────────────────────────

  void _onStorageLocationChanged(StorageLocationType type, String code, bool applyToCart) {
    Drug updateDrugStorage(Drug drug) {
      // Build updated storageLocations list preserving robot, replacing non-robot
      final oldLocs = drug.storageLocations ?? <StorageLocation>[];
      final robotLocs = oldLocs.where((l) => l.type == StorageLocationType.robot).toList();
      final nonRobotOld = oldLocs.where((l) => l.type != StorageLocationType.robot);
      final oldQty = nonRobotOld.isNotEmpty ? nonRobotOld.first.qty : drug.stock;
      final newLoc = StorageLocation(type: type, code: code, qty: oldQty);
      return drug.copyWithStorage(
        locationType: type,
        locationCode: code,
        storageLocations: [...robotLocs, newLoc],
      );
    }

    setState(() {
      if (_selectedDrug != null) {
        _selectedDrug = updateDrugStorage(_selectedDrug!);
      }

      if (applyToCart) {
        for (int i = 0; i < _cart.length; i++) {
          _cart[i] = CartItem(
            drug: updateDrugStorage(_cart[i].drug),
            quantity: _cart[i].quantity,
            fractionalQty: _cart[i].fractionalQty,
          );
        }
      }
    });
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
          TopBar(
            pharmacistName: _currentPharmacist?.user,
            onPharmacistTap: _showPharmacistPicker,
          ),

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
                                              offers: _isCustomerAuthorized ? _recommendedOffers : const [],
                                              onClear: _clearCart,
                                              onIncrease: _increaseQty,
                                              onDecrease: _decreaseQty,
                                              onRemove: _removeFromCart,
                                              onPay: _processPayment,
                                              onClose: _toggleCart,
                                              onAddOffer: _addOfferToCart,
                                              onAddOfferBlister: _addOfferBlisterToCart,
                                              loyalty: _customerLoyalty,
                                              onFocusPhone: _focusPhoneField,
                                            )
                                          : _ordersOpen
                                              ? OrdersPanel(
                                                  key: _ordersPanelKey,
                                                  onClose: _toggleOrders,
                                                  loyalty: _customerLoyalty,
                                                  onAddEdkPackage: (drug) =>
                                                      _setQuantity(drug, 1),
                                                  onAddEdkBlister: (drug) =>
                                                      _setFractionalQuantity(
                                                          drug, 1),
                                                  onOrderPaid: _onOrderPaid,
                                                  onFocusPhone: _focusPhoneField,
                                                )
                                              : _expensesOpen
                                                  ? ExpensesPanel(
                                                      key: _expensesPanelKey,
                                                      onClose: _toggleExpenses,
                                                    )
                                                  : _prescriptionOpen
                                                      ? PrescriptionPanel(
                                                          key: _prescriptionPanelKey,
                                                          onClose: _togglePrescription,
                                                          drugCatalog: mockDrugs,
                                                          onAddToCart: _addPrescriptionToCart,
                                                        )
                                                      : _socialProjectsOpen
                                                          ? SocialProjectsPanel(
                                                              key: _socialProjectsPanelKey,
                                                              onClose: _toggleSocialProjects,
                                                              selectedProject: _selectedSocialProject,
                                                              onProjectSelected: (p) =>
                                                                  setState(() => _selectedSocialProject = p),
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
                  ActionSidebar(
                    onOrdersTap: _toggleOrders,
                    ordersActive: _ordersOpen,
                    urgentCount: mockOrders
                        .where((o) =>
                            o.isUrgent &&
                            o.status != OrderStatus.collected &&
                            o.status != OrderStatus.dispensed)
                        .length,
                    onExpensesTap: _toggleExpenses,
                    expensesActive: _expensesOpen,
                    onPrescriptionTap: _togglePrescription,
                    prescriptionActive: _prescriptionOpen,
                    onSocialProjectsTap: _toggleSocialProjects,
                    socialProjectsActive: _socialProjectsOpen,
                  ),
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
      transitionBuilder: (child, animation) {
        final isEdk = child.key == const ValueKey('edk');
        if (isEdk) {
          // EdkPanel: soft scale-up from 0.97 + fade — gentle overlay feel
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        }
        // Default: subtle horizontal slide + fade
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
      child: activeEdkOffer != null
              ? EdkPanel(
                  key: const ValueKey('edk'),
                  offer: activeEdkOffer!,
                  onAddPackage: _addEdkToCart,
                  onAddBlister:
                      activeEdkOffer!.drug.unitsPerPackage != null
                          ? _addEdkBlisterToCart
                          : null,
                  onDismiss: _dismissEdk,
                )
              : (_selectedDrug != null && _selectedDrug!.isOutOfStock)
                  ? OutOfStockPanel(
                      key: _outOfStockPanelKey,
                      drug: _selectedDrug!,
                      edkOffer: _edkOffers[_selectedDrug!.id],
                      onAddPackage: () =>
                          _addOosEdkPackage(_selectedDrug!),
                      onAddBlister:
                          _edkOffers[_selectedDrug!.id]
                                      ?.drug
                                      .unitsPerPackage !=
                                  null
                              ? () => _addOosEdkBlister(_selectedDrug!)
                              : null,
                      onDismissEdk: () {},
                      nearbyPharmacies: mockNearbyPharmacies,
                      hasPhone: _isCustomerAuthorized,
                      onFocusPhone: _focusPhoneField,
                      onReserve: _reserveAtPharmacy,
                      onOrderForClient: _orderForClient,
                    )
                  : DrugDetailPanel(
                      key: const ValueKey('detail'),
                      drug: _selectedDrug,
                      analogues: _analogues,
                      onSelectAnalogue: _selectAnalogue,
                      onStorageLocationChanged: _onStorageLocationChanged,
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
              prefixIcon: _isServerLookup
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF4F6EF7),
                        ),
                      ),
                    )
                  : const Icon(Icons.search_rounded,
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
          onTap: () {
            setState(() {
              _selectedDrug = drug;
              _focusQtyOnSelect = true;
              _cartOpen = false;
              activeEdkOffer = null;
            });
            _fetchProductBrowserInfo(drug);
          },
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

