import 'dart:async';
import '../models/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/cart_offers.dart';
import '../data/edk_offers.dart';
import '../data/mock_drugs.dart';
import '../models/social_project.dart';
import '../models/stop_price_action.dart';
import '../services/auth_service.dart';
import '../services/cart_price_service.dart';
import '../services/drug_service.dart';
import '../services/pakunok_service.dart';
import '../services/social_projects_service.dart';
import '../services/stop_price_service.dart';
import '../services/farmasell_service.dart';
import '../services/loyalty_service.dart';
import '../services/product_browser_service.dart';
import '../services/skarb_service.dart';
import '../services/session_service.dart';
import '../services/shift_service.dart';
import '../widgets/shift_start_dialog.dart';
import '../widgets/cash_operation_dialog.dart';
import '../widgets/cash_settings_dialog.dart';
import '../widgets/fractional_input_dialog.dart';
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
import '../widgets/messages_panel.dart';
import '../widgets/barcode_input_dialog.dart';
import '../widgets/robot_panel.dart';
import '../services/api_config.dart';
import '../data/mock_messages.dart';
import '../models/prescription.dart';
import '../models/nearby_pharmacy.dart';
import '../widgets/top_bar.dart';
import '../widgets/drug_list_item.dart';

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

  List<Drug> _searchResults = [];
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
  Timer? _localFilterTimer;
  bool _isServerLookup = false;

  // ── Top drugs cache (pre-loaded at shift start) ────────────────────────
  /// Cached top drugs for instant local search.
  List<DrugSearchItem> _topDrugsCache = [];

  // ── Nearby pharmacies (for out-of-stock drugs) ─────────────────────────
  List<NearbyPharmacy> _nearbyPharmacies = [];
  String? _nearbyPharmaciesForDrugId;

  // ── Product Browser (drug safety tags + external analogues) ─────────────
  /// Drug IDs we've already tried fetching from Product Browser.
  final _productBrowserFetched = <String>{};
  /// External analogues from anc.ua search API (by INN/active substance).
  List<ProductSearchResult> _externalAnalogues = [];
  /// Drug ID for which external analogues are currently loaded.
  String? _externalAnaloguesForDrugId;

  // ── Caché analogues (GetAnalog) ────────────────────────────────────────
  /// Analogues from Caché GetAnalog API (by s-code).
  List<AnalogItem> _cacheAnalogues = [];
  /// Drug ID for which Caché analogues are currently loaded.
  String? _cacheAnaloguesForDrugId;

  // ── SKU Detail (Caché GetSKUdetail) ────────────────────────────────────
  /// Drug IDs we've already tried fetching from GetSKUdetail.
  final _skuDetailFetched = <String>{};

  /// A digit character waiting to be injected into the qty field on the
  /// next frame after focus transfers from the search field.
  String? _pendingQtyInput;

  /// Whether the cart panel is shown in the right column.
  bool _cartOpen = false;

  // ── Server-side pricing state (GetSumSkid) ─────────────────────────────
  /// Останнє обчислення цін з сервера (з усіма знижками + округленням).
  CartPricing? _serverPricing;
  bool _isLoadingPricing = false;
  Timer? _pricingDebounce;
  /// Sequence — захист від race conditions при швидких змінах кошика.
  int _pricingRequestSeq = 0;
  String _lastPricingKey = '';
  static const _pricingDebounceDuration = Duration(milliseconds: 500);

  /// Список соц-програм (server + always-shown local). Завантажується
  /// один раз після логіну.
  List<SocialProject> _socialProjects = const [];

  /// Versioning лічильник — інкрементується після prefetch акцій,
  /// щоб тригернути rebuild cart позицій що читають з `StopPriceService`.
  int _stopPriceVersion = 0;
  String _lastStopPriceUkods = '';

  /// Whether the internet orders panel is shown in the right column.
  bool _ordersOpen = false;

  /// Layout mode for orders panel (left / right / fullscreen).
  OrdersPanelLayout _ordersPanelLayout = OrdersPanelLayout.right;

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

  /// Активний режим "Пакунок Малюка". Активується вибором цього соц-проекту.
  /// Накладає обмеження: тільки товари зі списку ПМ, тільки картка, тільки
  /// контактна оплата, потрібна прив'язка каси до терміналу.
  bool get _isPakunokMode =>
      _selectedSocialProject == PakunokService.displayName;

  /// Перевірити чи можна додати товар у кошик у поточному ПМ-режимі.
  /// Повертає `true` якщо немає ПМ-режиму, або товар входить у програму.
  /// При відмові показує snackbar.
  bool _assertPakunokAllowed(Drug drug) {
    if (!_isPakunokMode) return true;
    if (PakunokService.isPakunok(drug)) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${drug.displayName} не входить у Пакунок Малюка'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFDC2626),
      ),
    );
    return false;
  }

  /// Активація соц-проекту з перевіркою для Пакунка Малюка.
  /// Якщо в кошику є товари не зі списку ПМ — пропонує очистити їх.
  /// Після успішного вибору — панель соц-проектів закривається автоматично.
  Future<void> _onSocialProjectSelected(String? p) async {
    if (p == PakunokService.displayName) {
      final invalid = _cart
          .where((i) => !PakunokService.isPakunok(i.drug))
          .toList(growable: false);
      if (invalid.isNotEmpty) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            icon: const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B), size: 36),
            title: const Text('У кошику є товари не з програми',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: Text(
              'Знайдено ${invalid.length} позицій, що не входять у Пакунок Малюка:\n'
              '${invalid.take(3).map((i) => "• ${i.drug.displayName}").join("\n")}'
              '${invalid.length > 3 ? "\n…ще ${invalid.length - 3}" : ""}\n\n'
              'Видалити їх з кошика для активації режиму?',
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Скасувати'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Видалити та активувати'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        // Зняти з server cart і видалити локально.
        for (final item in invalid) {
          _lockStock(item.drug, 0.0);
        }
        setState(() {
          _cart.removeWhere((i) => !PakunokService.isPakunok(i.drug));
        });
      }
    }
    setState(() => _selectedSocialProject = p);
    if (p != null && _socialProjectsOpen) {
      // Невелика затримка — щоб фармацевт побачив галочку "обрано"
      // у панелі перед її закриттям.
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() => _socialProjectsOpen = false);
    }
  }

  /// Key for accessing SocialProjectsPanelState.
  final _socialProjectsPanelKey = GlobalKey<SocialProjectsPanelState>();

  /// Whether the messages panel is shown in the right column.
  bool _messagesOpen = false;
  bool _robotOpen = false;

  /// Key for accessing MessagesPanelState.
  final _messagesPanelKey = GlobalKey<MessagesPanelState>();
  final _robotPanelKey = GlobalKey<RobotPanelState>();

  void _toggleCart() {
    setState(() {
      _cartOpen = !_cartOpen;
      if (_cartOpen) {
        _ordersOpen = false;
        _expensesOpen = false;
        _prescriptionOpen = false;
        _socialProjectsOpen = false;
        _messagesOpen = false;
        _robotOpen = false;
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
        _messagesOpen = false;
        _robotOpen = false;
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
        _messagesOpen = false;
        _robotOpen = false;
      }
    });
    if (_expensesOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _expensesPanelKey.currentState?.focusSearch();
      });
    }
  }

  void _togglePrescription() async {
    if (_prescriptionOpen) {
      // Closing — check for refusal reason
      final canClose =
          await _prescriptionPanelKey.currentState?.tryCloseWithRefusal() ??
              true;
      if (!canClose) return;
      setState(() => _prescriptionOpen = false);
    } else {
      setState(() {
        _prescriptionOpen = true;
        _cartOpen = false;
        _ordersOpen = false;
        _expensesOpen = false;
        _socialProjectsOpen = false;
        _messagesOpen = false;
        _robotOpen = false;
      });
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
        _messagesOpen = false;
        _robotOpen = false;
      }
    });
    if (_socialProjectsOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _socialProjectsPanelKey.currentState?.focusSearch();
      });
    }
  }

  void _toggleMessages() {
    setState(() {
      _messagesOpen = !_messagesOpen;
      if (_messagesOpen) {
        _cartOpen = false;
        _ordersOpen = false;
        _expensesOpen = false;
        _prescriptionOpen = false;
        _socialProjectsOpen = false;
        _robotOpen = false;
      }
    });
    if (_messagesOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messagesPanelKey.currentState?.focusSearch();
      });
    }
  }

  void _toggleRobot() {
    setState(() {
      _robotOpen = !_robotOpen;
      if (_robotOpen) {
        _cartOpen = false;
        _ordersOpen = false;
        _expensesOpen = false;
        _prescriptionOpen = false;
        _socialProjectsOpen = false;
        _messagesOpen = false;
      }
    });
  }

  /// Search drugs on server for prescription matching.
  Future<List<Drug>> _searchDrugsForPrescription(String query) async {
    if (query.isEmpty) return [];
    try {
      final items = await DrugService.searchByName(query);
      return items
          .where((item) => item.qtyRaw > 0)
          .map((item) => Drug(
                id: 'srv_${item.ids}',
                name: item.nameUkr ?? item.name,
                nameUkr: item.nameUkr,
                manufacturer: item.manufacturer,
                category: '',
                price: item.price,
                stock: item.qty,
                stockRaw: item.qtyRaw != item.qty.toDouble() ? item.qtyRaw : null,
                unit: 'шт',
                ukod: item.ukod.isNotEmpty ? item.ukod : null,
                skuCode: item.ids,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _addPrescriptionToCart(
      List<PrescriptionMatch> selectedMatches,
      Prescription rx,
      SkarbPrescriptionData? skarbData) {
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
            quantityUnit: rx.quantityUnit,
            concentration: rx.concentration,
            diseaseCategory: rx.diseaseCategory,
            medicalInstitution: rx.medicalInstitution,
            skarbMedicationRequestId: skarbData?.medicationRequestId,
            skarbMedicalProgramId: skarbData?.medicalProgramId,
            skarbParticipantId: match.skarbParticipantId,
            skarbMedicationId: match.skarbMedicationId,
          ),
        ));
      }
      _prescriptionOpen = false;
      _cartOpen = true;
    });
    // Lock stock for prescription items
    for (final match in selectedMatches) {
      _lockStock(match.drug, match.selectedQuantity.toDouble());
    }
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
  bool get _showAuthCard => _cartOpen || _ordersOpen || _expensesOpen || _prescriptionOpen || _socialProjectsOpen || _messagesOpen || _robotOpen || _selectedDrug != null;

  // ── Customer loyalty (phone auth) ─────────────────────────────────────────
  final _loyaltyPhoneController = TextEditingController();
  final _loyaltyPhoneFocusNode = FocusNode();
  CustomerLoyalty? _customerLoyalty;
  bool _isLoadingLoyalty = false;
  String? _previousCustomerPhone;

  static const _loyaltyPhonePrefix = CustomerAuthCard.loyaltyPhonePrefix;

  /// Whether the customer has been authorized via loyalty phone.
  bool get _isCustomerAuthorized => _customerLoyalty != null;

  // ── Рука допомоги (social discount program) ─────────────────────────────
  int _helpingHandRemaining = 10;
  final Map<String, double> _helpingHandPrices = {}; // drugId → discounted price
  bool _showHelpingHandMarkers = false;
  Timer? _helpingHandTimer;
  bool _helpingHandSuppressed = false; // true = не показувати сердечка для поточного пошуку

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

    // Cleanup any previous session that wasn't properly closed
    AuthService.cleanupPreviousSession();

    // Load pharmacists from server and auto-show picker
    _loadPharmacists(autoShow: true);

    // Load EDK offers
    _initEdkOffers();
  }

  /// Initialize EDK offers: mock only (live uses per-drug GetEdkOffers).
  Future<void> _initEdkOffers() async {
    if (ApiConfig.useMock) {
      _edkOffers = buildMockRetailEdkOffers(mockDrugs);
    }
  }

  /// Fetch EDK offers for a specific drug from Caché GetEdkOffers.
  ///
  /// [drug] — товар-донор
  /// [detailIds] — короткий ids з GetSKUdetail (напр. "3257")
  void _fetchEdkOffers(Drug drug, String detailIds) {
    if (ApiConfig.useMock) return;

    DrugService.fetchEdkOffers(detailIds).then((apiOffers) async {
      if (!mounted || apiOffers.isEmpty) return;
      final offer = apiOffers.first;
      final edkKey = drug.ukod ?? drug.id;

      // Fetch image from anc.ua for replacement drug
      String? imageUrl;
      try {
        final searchName = offer.replacementName
            .split(' ')
            .map((w) => w.isNotEmpty
                ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
                : w)
            .join(' ');
        final results = await ProductBrowserService.searchProducts(searchName, limit: 3);
        if (results.isNotEmpty) {
          imageUrl = results.first.imageUrl;
        }
      } catch (_) {}

      if (!mounted) return;

      // Fetch SKUDetail for replacement drug to get pharmacistBonus, manufacturer, category etc.
      SKUDetailResult? replacementDetail;
      if (offer.replacementId.isNotEmpty) {
        try {
          replacementDetail = await DrugService.fetchSKUDetail(offer.replacementId);
        } catch (_) {}
      }

      if (!mounted) return;

      final replacementDrug = Drug(
        id: 'edk_${offer.replacementId}',
        name: offer.replacementName,
        manufacturer: replacementDetail?.manufacturer ?? '',
        category: replacementDetail?.category ?? '',
        price: offer.replacementPrice,
        stock: 1,
        unit: 'шт',
        skuCode: offer.replacementId,
        imageUrl: imageUrl ?? replacementDetail?.imageUrl,
        pharmacistBonus: replacementDetail?.pharmacistBonus,
      );

      String? promo;
      if (offer.replacementBonus > 0) {
        promo = 'Бонус +${offer.replacementBonus}';
      }

      setState(() {
        _edkOffers[edkKey] = EdkOffer(
          drug: replacementDrug,
          donorDrugId: edkKey,
          description: '${offer.replacementName} — ${offer.reason.toLowerCase()}.',
          script: offer.script,
          promoLabel: promo,
          bonus: offer.replacementBonus,
        );
      });
      debugPrint('ЄДК: GetEdkOffers ids=$detailIds → ${offer.replacementName} '
          '(${offer.reason}, ціна=${offer.replacementPrice}, '
          'бонус ЄДК=${offer.replacementBonus}, '
          'бонус фарм=${replacementDetail?.pharmacistBonus ?? 0})');
    }).catchError((e) {
      debugPrint('ЄДК: GetEdkOffers error for ids=$detailIds: $e');
    });
  }

  /// Rebuild EDK offers — no-op in live mode (offers are per-drug now).
  void _rebuildEdkOffers() {
    // In live mode, EDK offers are fetched per-drug via GetEdkOffers.
    // Nothing to rebuild.
  }

  /// EDK key helper: mock uses Drug.id, live uses Drug.ukod.
  String _edkKey(Drug d) => ApiConfig.useMock ? d.id : (d.ukod ?? '');

  Future<void> _loadPharmacists({bool autoShow = false}) async {
    try {
      debugPrint('Loading pharmacists...');
      final users = await AuthService.getUsers();
      debugPrint('Loaded ${users.length} pharmacists');
      if (!mounted) return;
      users.sort((a, b) => a.user.toLowerCase().compareTo(b.user.toLowerCase()));
      setState(() => _pharmacists = users);
      if (autoShow && _currentPharmacist == null && users.isNotEmpty) {
        _showPharmacistPicker();
      }
    } catch (e) {
      debugPrint('LoadPharmacists error: $e');
    }
  }

  void _showPharmacistPicker() {
    if (_pharmacists.isEmpty) {
      _loadPharmacists(autoShow: true);
      return;
    }
    // If already logged in — show logout menu instead of picker
    if (_currentPharmacist != null) {
      _showPharmacistMenu();
      return;
    }
    _openPharmacistPicker();
  }

  void _openPharmacistPicker() {
    showPharmacistPicker(context, _pharmacists).then((selected) {
      if (selected != null && mounted) {
        setState(() => _currentPharmacist = selected);
        // Fire-and-forget Skarb login for e-prescription support
        if (!ApiConfig.useMock && SkarbConfig.apiKey.isNotEmpty) {
          SkarbService.login().then((r) {
            if (!r.success) debugPrint('Skarb login warning: ${r.error}');
          });
        }
        // Pre-load top drugs cache for instant search
        _loadTopDrugsCache();
        // Завантажити перелік соц-програм для аптеки.
        _loadSocialProjects();
        // Початок зміни: ProvSumZOtchet — чи потрібне службове внесення +
        // залишок з останнього Z-звіту. Діалог показуємо лише коли потрібне.
        if (!ShiftService.state.isOpen) {
          ShiftService.checkServiceDeposit().then((check) {
            if (!mounted || !check.needed) return;
            showShiftStartDialog(
              context,
              pharmacist: selected.user,
              carryover: check.carryover,
            );
          });
        }
      }
    });
  }

  /// Show pharmacist menu with "Змінити" and "Завершити роботу" options.
  void _showPharmacistMenu() {
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pharmacist avatar + name
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F3FB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _currentPharmacist!.user.isNotEmpty
                      ? _currentPharmacist!.user[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Color(0xFF1E7DC8),
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _currentPharmacist!.user,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C2E),
              ),
            ),
            if (_currentPharmacist!.ipn.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'ІПН: ${_currentPharmacist!.ipn}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            // Каса — внесення / винесення
            ListTile(
              dense: true,
              leading: const Icon(Icons.savings_outlined,
                  size: 20, color: Color(0xFF1E7DC8)),
              title: const Text('Каса (внесення / винесення)',
                  style: TextStyle(fontSize: 13)),
              onTap: () => Navigator.of(ctx).pop('cash'),
            ),
            // Налаштування каси (адмінка) — лише спецкористувач (typezuser==1)
            if (_currentPharmacist!.isSpecial)
              ListTile(
                dense: true,
                leading: const Icon(Icons.settings_outlined,
                    size: 20, color: Color(0xFF1E7DC8)),
                title: const Text('Налаштування каси',
                    style: TextStyle(fontSize: 13)),
                onTap: () => Navigator.of(ctx).pop('cash_settings'),
              ),
            // Change pharmacist
            ListTile(
              dense: true,
              leading: const Icon(Icons.swap_horiz_rounded,
                  size: 20, color: Color(0xFF1E7DC8)),
              title: const Text('Змінити фармацевта',
                  style: TextStyle(fontSize: 13)),
              onTap: () => Navigator.of(ctx).pop('change'),
            ),
            // Logout
            ListTile(
              dense: true,
              leading: const Icon(Icons.logout_rounded,
                  size: 20, color: Color(0xFFEF4444)),
              title: const Text('Завершити роботу',
                  style: TextStyle(fontSize: 13, color: Color(0xFFEF4444))),
              onTap: () => Navigator.of(ctx).pop('logout'),
            ),
          ],
        ),
      ),
    ).then((action) async {
      if (action == null || !mounted) return;
      if (action == 'cash') {
        showCashOperationDialog(context);
        return;
      }
      if (action == 'cash_settings') {
        // Доступ лише спецкористувачу (typezuser==1).
        if (_currentPharmacist?.isSpecial == true) showCashSettingsDialog(context);
        return;
      }
      if (action == 'logout' || action == 'change') {
        // Очистити кошик і серверний сеанс перед зміною/виходом фармацевта.
        _clearCart();
        await AuthService.logout();
        if (mounted) {
          setState(() => _currentPharmacist = null);
          _openPharmacistPicker();
        }
      }
    });
  }

  /// LogoutRlz — закрити сесію при виході.
  Future<void> _logoutPharmacist() async {
    if (_currentPharmacist != null) {
      await AuthService.logout();
    }
  }

  @override
  void dispose() {
    _pricingDebounce?.cancel();
    // Зняти резервування всіх товарів у кошику при закритті
    _unlockAllCart();
    // LogoutRlz — fire-and-forget при закритті додатка
    _logoutPharmacist();
    _barcodeLookupTimer?.cancel();
    _nameSearchTimer?.cancel();
    _localFilterTimer?.cancel();
    _helpingHandTimer?.cancel();
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

    if (_messagesOpen) {
      // Ctrl+M: toggle messages panel (close it)
      if (HardwareKeyboard.instance.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.keyM) {
        _toggleMessages();
        return true;
      }
      // Esc: close detail/compose → close panel
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_messagesPanelKey.currentState?.isDetailOpen == true) {
          _messagesPanelKey.currentState?.closeDetail();
        } else {
          _toggleMessages();
        }
        return true;
      }
      return false; // let text input work
    }

    // Don't intercept keys when a dialog/overlay is open (e.g. pharmacist picker)
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    // ── Ctrl+digit → fractional qty (blisters) when a row is selected ──────
    if (HardwareKeyboard.instance.isControlPressed) {
      final digit = _ctrlDigitFromKey(event.logicalKey);
      if (digit != null && _selectedDrug != null && _selectedDrug!.stock > 0) {
        if (_selectedDrug!.canSplitByBlister) {
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
      // ── Ctrl+B: toggle robot panel ────────────────────────────────────
      if (event.logicalKey == LogicalKeyboardKey.keyB &&
          ApiConfig.hasRobot) {
        _toggleRobot();
        return true;
      }
      // ── Ctrl+R: toggle e-Prescription panel ────────────────────────────
      if (event.logicalKey == LogicalKeyboardKey.keyR) {
        _togglePrescription();
        return true;
      }
      // ── Ctrl+M: toggle messages panel ────────────────────────────────
      if (event.logicalKey == LogicalKeyboardKey.keyM) {
        _toggleMessages();
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

    // ── F4: manual barcode input ──────────────────────────────────────────
    if (event.logicalKey == LogicalKeyboardKey.f4) {
      _showManualBarcodeDialog();
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

    // ── F6: ручне введення дробової кількості (блістерів) ─────────────────────
    if (event.logicalKey == LogicalKeyboardKey.f6) {
      _openFractionalInput();
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
      } else if (_robotOpen) {
        setState(() => _robotOpen = false);
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

    // Empty query: apply immediately (no debounce needed)
    if (query.isEmpty) {
      _localFilterTimer?.cancel();
      _applyLocalFilter(query);
    } else {
      // Debounce local fuzzy filter: 50ms to batch rapid keystrokes
      _localFilterTimer?.cancel();
      _localFilterTimer = Timer(const Duration(milliseconds: 50), () {
        _applyLocalFilter(query);
      });
    }

    // ── Рука допомоги + server search (runs regardless of debounce) ─────
    _helpingHandTimer?.cancel();
    _helpingHandSuppressed = false; // новий пошук — скидаємо suppress
    if (query.isEmpty) {
      if (_showHelpingHandMarkers) {
        setState(() => _showHelpingHandMarkers = false);
      }
    } else if (!_showHelpingHandMarkers) {
      _helpingHandTimer = Timer(const Duration(seconds: 7), () {
        if (mounted && !_helpingHandSuppressed) {
          setState(() => _showHelpingHandMarkers = true);
        }
      });
    }

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
      // Send original query — Caché now searches both name and nameukr
      _nameSearchTimer = Timer(
        const Duration(milliseconds: 300),
        () => _searchByNameOnServer(query),
      );
    }
  }

  void _applyLocalFilter(String query) {
    if (!mounted) return;
    setState(() {
      final existingServerDrugs =
          _searchResults.where((d) => d.id.startsWith('srv_')).toList();

      if (query.isEmpty) {
        // Очистити попередні результати пошуку (Esc / хрестик).
        _searchResults = const [];
        _selectedDrug = null;
      } else {
        // Show instant results from top drugs cache while server searches
        if (existingServerDrugs.isEmpty && _topDrugsCache.isNotEmpty) {
          final lowerQuery = query.toLowerCase();
          final cached = _topDrugsCache
              .where((item) =>
                  item.name.toLowerCase().contains(lowerQuery) ||
                  (item.nameUkr?.toLowerCase().contains(lowerQuery) ?? false))
              .take(30)
              .map((item) => Drug(
                    id: 'srv_${item.ids}',
                    name: item.nameUkr ?? item.name,
                    nameUkr: item.nameUkr,
                    manufacturer: item.manufacturer,
                    category: item.category ?? '',
                    price: item.price,
                    stock: item.qty,
                    stockRaw: item.qtyRaw != item.qty.toDouble() ? item.qtyRaw : null,
                    unit: 'шт',
                    locationCode: item.shelf.isNotEmpty ? item.shelf : null,
                    expiryDate: item.expiryDate,
                    comingPrice: item.comingPrice,
                    comingCode: item.comingCode,
                    ukod: item.ukod.isNotEmpty ? item.ukod : null,
                    skuCode: item.ids,
                    pharmacistBonus: item.bonus,
                    isOwnBrand: item.isOwnBrand,
                    dosageForm: item.dosageForm,
                    hasHelpingHand: item.comingPrice != null && item.comingCode != null,
                  ))
              .toList();
          if (cached.isNotEmpty) {
            _searchResults = cached;
          }
        } else {
          _searchResults = existingServerDrugs;
        }
      }

      _focusQtyOnSelect = false;
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
    // Ліниво підтягнути стоп-ціни для видимих результатів (гібрид).
    _prefetchStopPriceUkods(_searchResults.map((d) => d.ukod));
  }

  /// Fetch pharmacies that have the selected out-of-stock drug.
  void _fetchNearbyPharmacies(Drug drug) {
    if (_nearbyPharmaciesForDrugId == drug.id) return;
    if (!drug.isOutOfStock) return;

    _nearbyPharmaciesForDrugId = drug.id;
    setState(() => _nearbyPharmacies = []);

    // Need slug from ProductBrowser — use the one we've already fetched
    final slug = drug.productBrowserSlug;
    if (slug == null || slug.isEmpty) {
      // Try to find slug by searching
      ProductBrowserService.searchProducts(drug.name, limit: 1).then((results) {
        if (!mounted || results.isEmpty) return;
        if (_selectedDrug?.id != drug.id) return;
        _fetchPharmaciesBySlug(drug, results.first.link);
      });
      return;
    }
    _fetchPharmaciesBySlug(drug, slug);
  }

  void _fetchPharmaciesBySlug(Drug drug, String slug) {
    ProductBrowserService.fetchPharmaciesWithStock(
      slug,
      city: ApiConfig.cityId,
    ).then((pharmacies) {
      if (!mounted) return;
      if (_selectedDrug?.id != drug.id) return;
      // Розрахувати відстань і відсортувати від найближчої
      final withDistance = pharmacies
          .map((ph) => ph.withDistanceFrom(
                ApiConfig.pharmacyLat, ApiConfig.pharmacyLng))
          .toList()
        ..sort((a, b) {
          // Open first, then by distance
          if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
          return (a.distanceKm ?? 999).compareTo(b.distanceKm ?? 999);
        });
      // Показати макс. 3 найближчі аптеки в радіусі 10 км
      final nearby = withDistance
          .where((ph) => ph.distanceKm != null && ph.distanceKm! <= 10.0)
          .take(3)
          .toList();
      setState(() => _nearbyPharmacies = nearby);
    }).catchError((e) {
      debugPrint('NearbyPharmacies: error — $e');
    });
  }

  /// Pre-load top drugs from Caché for instant local search.
  void _loadTopDrugsCache() {
    DrugService.fetchTopDrugs().then((items) {
      if (!mounted) return;
      _topDrugsCache = items;
      debugPrint('TopDrugsCache: loaded ${items.length} items');
      // Гібрид: фоновий префетч стоп-цін для топ-500 (де сконцентровані акції) —
      // популярні товари показують акційну ціну в таблиці миттєво.
      _prefetchStopPriceUkods(items.map((i) => i.ukod));
    }).catchError((e) {
      debugPrint('TopDrugsCache: error — $e');
    });
  }

  /// Search drugs by name on Caché server; merge results into table.
  /// [originalQuery] — original user input (for stale-check against search field).
  Future<void> _searchByNameOnServer(String query, {String? originalQuery}) async {
    if (!mounted) return;
    setState(() => _isServerLookup = true);

    try {
      // Run both searches in parallel:
      // - SearchByNameSKU: s-codes with prices, expiry, comingPrice (in-stock only)
      // - SearchByName: u-codes including out-of-stock items
      final results = await Future.wait([
        DrugService.searchByName(query),
        DrugService.searchByNameUcodes(query),
      ]);
      if (!mounted) return;

      final skuItems = results[0]; // s-codes (in-stock with prices)
      final uItems = results[1];   // u-codes (all, including zero stock)

      // Ignore if user already changed the search query.
      final currentText = _searchController.text.trim();
      if (currentText != query && currentText != (originalQuery ?? query)) {
        setState(() => _isServerLookup = false);
        return;
      }

      if (skuItems.isEmpty && uItems.isEmpty) {
        setState(() => _isServerLookup = false);
        return;
      }

      // Build Drug objects from s-codes (with full pricing data)
      final serverDrugs = <Drug>[];
      final seenUkods = <String>{};

      // Індекс u-codes за ukod — щоб виявити дробові залишки яких немає в s-codes.
      final uByUkod = <String, DrugSearchItem>{};
      for (final u in uItems) {
        if (u.ids.isNotEmpty) uByUkod[u.ids] = u;
      }

      for (final item in skuItems) {
        // Якщо s-code з qty=0 але в u-codes для того ж ukod є дробовий
        // залишок (qtyRaw>0) — пропускаємо s-code. u-code додасться нижче з
        // правильним stockRaw, інакше в seenUkods він би заблокувався.
        if (item.qty == 0 && item.qtyRaw == 0) {
          final uMatch = uByUkod[item.ukod];
          if (uMatch != null && uMatch.qtyRaw > 0) continue;
        }
        if (item.ukod.isNotEmpty) seenUkods.add(item.ukod);
        final locations = <StorageLocation>[];
        if (item.shelf.isNotEmpty) {
          locations.add(StorageLocation(
            type: StorageLocationType.shelf,
            code: item.shelf,
            qty: item.qty,
          ));
        }
        final hasHH = item.comingPrice != null && item.comingCode != null;
        serverDrugs.add(Drug(
          id: 'srv_${item.ids}',
          name: item.nameUkr ?? item.name,
          nameUkr: item.nameUkr,
          manufacturer: item.manufacturer,
          category: '',
          price: item.price,
          stock: item.qty,
          stockRaw: item.qtyRaw != item.qty.toDouble() ? item.qtyRaw : null,
          unit: 'шт',
          locationCode: item.shelf.isNotEmpty ? item.shelf : null,
          storageLocations: locations.isNotEmpty ? locations : null,
          expiryDate: item.expiryDate,
          comingPrice: item.comingPrice,
          comingCode: item.comingCode,
          ukod: item.ukod.isNotEmpty ? item.ukod : null,
          skuCode: item.ids,
          hasHelpingHand: hasHH,
        ));
      }

      // Add items from u-codes not already covered by s-codes.
      // Включає як out-of-stock (qtyRaw=0), так і дробові залишки (qtyRaw<1,
      // які SearchByNameSKU фільтрує, бо там qty має бути ≥1).
      for (final item in uItems) {
        if (item.ids.isEmpty) continue;
        if (seenUkods.contains(item.ids)) continue; // u-code already has s-codes
        if (item.qty > 0) continue; // skip integer in-stock (already in s-codes)
        serverDrugs.add(Drug(
          id: 'srv_u_${item.ids}',
          name: item.nameUkr ?? item.name,
          nameUkr: item.nameUkr,
          manufacturer: item.manufacturer,
          category: '',
          price: item.price,
          stock: item.qty,
          stockRaw: item.qtyRaw > 0 ? item.qtyRaw : null,
          unit: 'шт',
          locationCode: item.shelf.isNotEmpty ? item.shelf : null,
          ukod: item.ids, // u-code ids IS the ukod
        ));
      }

      // Sort: in-stock first → FEFO (shortest expiry first) → by name.
      serverDrugs.sort((a, b) {
        // 1. In-stock before out-of-stock
        if (a.stock > 0 && b.stock <= 0) return -1;
        if (a.stock <= 0 && b.stock > 0) return 1;

        // 2. Same name group: sort by expiry date (FEFO — shortest expiry first)
        final nameCmp = a.name.compareTo(b.name);
        if (nameCmp == 0) {
          final aExp = a.parsedExpiry;
          final bExp = b.parsedExpiry;
          if (aExp != null && bExp != null) return aExp.compareTo(bExp);
          if (aExp != null) return -1; // has expiry before no-expiry
          if (bExp != null) return 1;
        }

        // 3. Different names: alphabetical
        return nameCmp;
      });

      setState(() {
        // Remove old server drugs, prepend new ones before mock results.
        final mockResults =
            _searchResults.where((d) => !d.id.startsWith('srv_')).toList();
        // Clear SKUDetail cache for new server drugs so they get re-enriched
        for (final d in serverDrugs) {
          _skuDetailFetched.remove(d.id);
        }
        _searchResults = [...serverDrugs, ...mockResults];
        _rebuildEdkOffers(); // оновити ЄДК з новими ukod
        // Always select first server drug when results arrive
        // (server drugs are more relevant than mocks).
        if (serverDrugs.isNotEmpty) {
          _selectedDrug = serverDrugs.first;
        } else if (_selectedDrug == null ||
            !_searchResults.any((d) => d.id == _selectedDrug!.id)) {
          _selectedDrug =
              _searchResults.isNotEmpty ? _searchResults.first : null;
        }
        _isServerLookup = false;
      });
      // Ліниво підтягнути стоп-ціни для видимих результатів (гібрид).
      _prefetchStopPriceUkods(_searchResults.map((d) => d.ukod));
      // Fetch SKU detail for ALL server drugs
      for (final drug in serverDrugs) {
        _fetchSKUDetail(drug);
      }
      // Fetch safety tags + external analogues for the selected drug
      if (_selectedDrug != null) {
        _fetchProductBrowserInfo(_selectedDrug!);
        _fetchExternalAnalogues(_selectedDrug!);
        _fetchCacheAnalogues(_selectedDrug!);
        if (_selectedDrug!.isOutOfStock) _fetchNearbyPharmacies(_selectedDrug!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isServerLookup = false);
    }
  }

  // ── Product Browser: auto-fetch safety tags ──────────────────────────────

  /// Fetch drug info from Product Browser API (anc.ua).
  /// Enriches drug with images, instructions, indications, usage info.
  void _fetchProductBrowserInfo(Drug drug) {
    // Skip if already tried this drug
    if (_productBrowserFetched.contains(drug.id)) return;
    _productBrowserFetched.add(drug.id);

    // Use pre-mapped slug if available, otherwise search by article ID / name
    Future<ProductBrowserResult?> future;
    if (drug.productBrowserSlug != null && drug.productBrowserSlug!.isNotEmpty) {
      future = ProductBrowserService.fetchBySlug(drug.productBrowserSlug!);
    } else {
      // Server drugs have id like "srv_12345" — extract the numeric part.
      final articleId = drug.id.replaceFirst('srv_', '');
      // Search API finds slug by article ID or name, then fetches full details
      future = ProductBrowserService.searchAndFetch(
        articleId: articleId,
        name: drug.name,
      );
    }

    // Fire-and-forget async fetch
    future.then((result) async {
      if (!mounted || result == null) return;

      final usageInfo = result.toUsageInfo();

      // Fetch Ukrainian indications from full_description or instructions HTML
      String? indicationsUa;
      final descUrl = result.fullDescriptionUrl ?? result.instructionsUrl;
      if (descUrl != null) {
        indicationsUa = await ProductBrowserService.fetchIndicationsUa(descUrl);
      }

      if (!mounted) return;

      // Update the drug in _searchResults and _selectedDrug
      setState(() {
        // Use CURRENT version of drug (may have been enriched by SKUDetail)
        final currentDrug = _searchResults.firstWhere(
          (d) => d.id == drug.id,
          orElse: () => drug,
        );
        final updatedDrug = currentDrug.copyWithProductBrowser(
          // SKUDetail (internal) has priority for usageInfo over Product Browser
          usageInfo: currentDrug.usageInfo == null ? usageInfo : null,
          imageUrl: result.imageUrl,
          indications: indicationsUa ?? result.information,
          instructionsUrl: result.instructionsUrl,
          countryOfOrigin: result.countryOfOrigin,
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

  // ── Caché GetSKUdetail: auto-fetch drug detail ──────────────────────────

  /// Fetch drug detail from Caché GetSKUdetail API.
  /// Enriches drug with inn, dosageForm, dosage, expiryDate, unitsPerPackage, etc.
  void _fetchSKUDetail(Drug drug) {
    if (_skuDetailFetched.contains(drug.id)) return;
    _skuDetailFetched.add(drug.id);

    // GetSKUdetail works with u-codes (e.g. "5511*3*14").
    // Use ukod; fall back to s-code from drug.id for legacy items.
    final ids = drug.ukod ?? drug.id.replaceFirst('srv_u_', '').replaceFirst('srv_', '');
    if (ids.isEmpty) {
      debugPrint('SKUDetail: skip — ids is empty for ${drug.name} (id=${drug.id}, ukod=${drug.ukod})');
      return;
    }
    debugPrint('SKUDetail: fetching ids="$ids" for ${drug.name} (id=${drug.id})');

    DrugService.fetchSKUDetail(ids).then((detail) {
      if (!mounted) return;
      if (detail == null) {
        debugPrint('SKUDetail: returned null for ids="$ids"');
        return;
      }

      setState(() {
        // Use CURRENT version of drug (may have been enriched by ProductBrowser)
        final currentDrug = _searchResults.firstWhere(
          (d) => d.id == drug.id,
          orElse: () => drug,
        );
        final updatedDrug = currentDrug.copyWithSKUDetail(
          nameUkr: detail.nameUkr,
          inn: detail.inn,
          dosageForm: detail.dosageForm,
          dosage: detail.dosage,
          manufacturer: detail.manufacturer,
          category: detail.category,
          expiryDate: detail.expiryDate,
          unitsPerPackage: detail.unitsPerPackage,
          variableDivisor: detail.variableDivisor,
          pharmacistBonus: detail.pharmacistBonus,
          barcode: detail.barcode,
          series: detail.series,
          storageConditions: detail.storageConditions,
          requiresPrescription: detail.requiresPrescription,
          isOwnBrand: detail.isOwnBrand,
          analogueGroup: detail.analogueGroup,
          imageUrl: detail.imageUrl,
          intakeWarning: detail.intakeWarning,
          usageInfo: detail.toUsageInfo(),
          skuCode: detail.skuCode,
          comingPrice: detail.comingPrice,
          comingCode: detail.comingCode,
        );

        _searchResults = _searchResults.map((d) {
          return d.id == drug.id ? updatedDrug : d;
        }).toList();

        if (_selectedDrug?.id == drug.id) {
          _selectedDrug = updatedDrug;
        }

        // Update cart item if already added
        final cartIdx = _cart.indexWhere((item) => item.drug.id == drug.id);
        if (cartIdx >= 0) {
          _cart[cartIdx] = CartItem(
            drug: updatedDrug,
            quantity: _cart[cartIdx].quantity,
            fractionalQty: _cart[cartIdx].fractionalQty,
          );
        }
      });

      // If INN was just populated, try fetching external analogues
      debugPrint('SKUDetail: inn=${detail.inn}, analogueGroup=${detail.analogueGroup} for ${drug.name}');
      if (detail.inn != null && detail.inn!.isNotEmpty) {
        final updated = _selectedDrug;
        if (updated != null && updated.id == drug.id) {
          _fetchExternalAnalogues(updated);
        } else {
          debugPrint('Analogues: skip after SKUDetail — drug changed (selected=${_selectedDrug?.id}, detail=${drug.id})');
        }
      }

      // Fetch EDK and analogues only for the selected drug (not all search results)
      if (_selectedDrug?.id == drug.id) {
        if (detail.skuCode != null && detail.skuCode!.isNotEmpty) {
          _fetchEdkOffers(drug, detail.skuCode!);
        }
        _fetchCacheAnalogues(drug);
      }
    }).catchError((e) {
      debugPrint('SKUDetail: error for ids="$ids" — $e');
    });
  }

  /// Fetch external analogues from anc.ua by INN (active substance).
  /// Fire-and-forget async: updates _externalAnalogues on success.
  void _fetchExternalAnalogues(Drug drug) {
    // Only fetch if drug has INN and we haven't loaded for this drug yet
    if (drug.inn == null || drug.inn!.isEmpty) {
      debugPrint('Analogues: skip — INN is empty for ${drug.name}');
      return;
    }
    if (_externalAnaloguesForDrugId == drug.id) {
      debugPrint('Analogues: skip — already fetched for ${drug.id}');
      return;
    }

    _externalAnaloguesForDrugId = drug.id;
    setState(() => _externalAnalogues = []);
    debugPrint('Analogues: searching by INN="${drug.inn}" for ${drug.name}');

    // Search by INN to find analogues from the entire market
    ProductBrowserService.searchProducts(drug.inn!, limit: 15).then((results) {
      if (!mounted) return;
      if (_selectedDrug?.id != drug.id) return; // user changed selection

      debugPrint('Analogues: found ${results.length} results for INN="${drug.inn}"');
      setState(() {
        _externalAnalogues = results;
      });
    }).catchError((e) {
      debugPrint('Analogues: error — $e');
    });
  }

  /// Fetch analogues from Caché GetAnalog API (by s-code).
  /// The original s-code from SearchByNameSKU is preserved in drug.id
  /// as 'srv_{ids}' — extract it since drug.skuCode gets overwritten
  /// by GetSKUdetail with the reference code.
  void _fetchCacheAnalogues(Drug drug) {
    // Extract original s-code from drug.id (srv_{ids} format)
    final effectiveSkod = drug.id.startsWith('srv_u_')
        ? '' // u-code drugs don't have s-codes
        : drug.id.replaceFirst('srv_', '');
    if (effectiveSkod.isEmpty) return;
    if (_cacheAnaloguesForDrugId == drug.id) return;

    _cacheAnaloguesForDrugId = drug.id;
    setState(() => _cacheAnalogues = []);
    debugPrint('CacheAnalog: fetching SKod=$effectiveSkod for ${drug.name}');

    DrugService.fetchAnalogs(effectiveSkod).then((results) {
      if (!mounted) return;
      if (_selectedDrug?.id != drug.id) return;

      debugPrint('CacheAnalog: found ${results.length} results for SKod=$effectiveSkod');
      // Remove the donor drug itself from analogs list
      results.removeWhere((a) => a.ukod == (drug.ukod ?? '') || a.name == drug.name);

      // Sort: analogs (analog=1) first, then by bonus descending
      results.sort((a, b) {
        if (a.isAnalog != b.isAnalog) return a.isAnalog ? -1 : 1;
        return (b.bonus ?? 0).compareTo(a.bonus ?? 0);
      });
      setState(() {
        _cacheAnalogues = results;
      });
    }).catchError((e) {
      debugPrint('CacheAnalog: error — $e');
    });
  }

  // ── Manual barcode input (F4) ───────────────────────────────────────────
  Future<void> _showManualBarcodeDialog() async {
    final barcode = await showBarcodeInputDialog(context: context);
    if (barcode != null && barcode.isNotEmpty && mounted) {
      _searchController.text = barcode;
      _lookupBarcodeOnServer(barcode);
    }
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
          name: result.nameUkr ?? result.name ?? 'Невідомо',
          nameUkr: result.nameUkr,
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
        _fetchExternalAnalogues(drug);
        _fetchCacheAnalogues(drug);
        _fetchSKUDetail(drug);
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

    // Suppress helping hand markers on cursor movement
    _suppressHelpingHand();

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
    _fetchExternalAnalogues(newDrug);
    _fetchCacheAnalogues(newDrug);
    _fetchSKUDetail(newDrug);
    if (newDrug.isOutOfStock) _fetchNearbyPharmacies(newDrug);
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

  /// Отримати оригінальний с-код товару з drug.id (srv_{ids} формат).
  /// drug.skuCode перезаписується GetSKUdetail — не використовувати.
  String _stockSkod(Drug drug) {
    // ЄДК-заміна ідентифікується лише u-кодом (GetEdkOffers.replacementId —
    // композит `6077.999*...`), s-коду (коду приходу) для неї немає.
    // sgVRoznSetLock приймає тільки s-код → резервування пропускаємо,
    // інакше сервер відповідає «Перевірте SKod». Аналогічно до u-кодів нижче.
    if (drug.id.startsWith('edk_')) {
      debugPrint('sgVRoznSetLock: skip ЄДК ${drug.id} (немає s-коду)');
      return '';
    }
    if (drug.id.startsWith('srv_u_')) return ''; // u-code, немає с-коду
    return drug.id.replaceFirst('srv_', '');
  }

  /// Зарезервувати залишок на сервері.
  /// Повертає [StockLockResult] з фактичною зарезервованою кількістю.
  /// [qty] — десятковий дріб (0.5 = половина упаковки, 1.5 = упаковка + половина).
  /// При qty=0 знімає резервування.
  Future<StockLockResult> _lockStock(Drug drug, double qty) async {
    final skod = _stockSkod(drug);
    if (skod.isEmpty) return StockLockResult(ok: true, grantedQty: qty);
    return DrugService.setStockLock(skod, qty);
  }

  /// Оновити залишок товару в таблиці (колонка «Наявність») після резервування —
  /// `kolStock` з sgVRoznSetLock (напр. було 5, відпустили 1 → стало 4).
  void _applyKolStock(String drugId, double? kolStock) {
    if (kolStock == null || !mounted) return;
    final whole = kolStock <= 0 ? 0 : kolStock.floor();
    setState(() {
      _searchResults = _searchResults
          .map((d) => d.id == drugId
              ? d.copyWithStock(stock: whole, stockRaw: kolStock)
              : d)
          .toList();
      if (_selectedDrug?.id == drugId) {
        _selectedDrug =
            _selectedDrug!.copyWithStock(stock: whole, stockRaw: kolStock);
      }
    });
  }

  /// Обчислити кількість для резервування з CartItem.
  /// Цілі упаковки = quantity, блістери = fractionalQty / unitsPerPackage.
  double _cartItemLockQty(CartItem item) {
    if (item.isFractional && item.drug.unitsPerPackage != null) {
      return item.fractionalQty! / item.drug.unitsPerPackage!;
    }
    return item.quantity.toDouble();
  }

  /// Придушити показ сердечок Рука допомоги для поточного пошуку.
  /// Спрацьовує при русі курсором або введенні кількості.
  void _suppressHelpingHand() {
    if (!_helpingHandSuppressed) {
      _helpingHandSuppressed = true;
      _helpingHandTimer?.cancel();
      if (_showHelpingHandMarkers) {
        setState(() => _showHelpingHandMarkers = false);
      }
    }
  }

  /// Зняти резервування для всіх товарів в кошику.
  void _unlockAllCart() {
    for (final item in _cart) {
      _lockStock(item.drug, 0.0);
    }
  }

  void _setQuantity(Drug drug, int qty) async {
    _suppressHelpingHand();
    final wasInCart = _cart.any((item) => item.drug.id == drug.id);

    // ПМ-режим: блокуємо додавання товарів не зі списку Пакунок Малюка.
    if (qty > 0 && !wasInCart && !_assertPakunokAllowed(drug)) return;

    if (qty <= 0) {
      // Видалення з кошика — зняти резервування
      setState(() {
        final idx = _cart.indexWhere((item) => item.drug.id == drug.id);
        if (idx >= 0) _cart.removeAt(idx);
      });
      final r = await _lockStock(drug, 0.0);
      if (mounted) _applyKolStock(drug.id, r.kolStock); // відновити «Наявність»
      return;
    }

    final clamped = qty.clamp(1, drug.stock);

    // Спочатку резервуємо на сервері
    final result = await _lockStock(drug, clamped.toDouble());
    if (!mounted) return;

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Помилка резервування: ${drug.name}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Оновити «Наявність» у таблиці актуальним залишком із сервера.
    _applyKolStock(drug.id, result.kolStock);

    // Сервер міг видати менше ніж запитали (інша каса вже зарезервувала)
    final granted = result.grantedQty.round();
    if (granted <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${drug.name} — залишок зарезервовано іншою касою'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final actualQty = granted < clamped ? granted : clamped;
    if (granted < clamped) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${drug.name} — доступно лише $granted шт (решта зарезервована)'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // Показати cause/causeTitle якщо є обмеження
    if (result.causeTitle != null && result.causeTitle!.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${drug.name}: ${result.causeTitle}'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB45309),
        ),
      );
    }

    setState(() {
      final idx = _cart.indexWhere((item) => item.drug.id == drug.id);
      if (idx >= 0) {
        _cart[idx].quantity = actualQty;
        _cart[idx].fractionalQty = null; // exit fractional mode
      } else {
        _cart.add(CartItem(drug: drug, quantity: actualQty));
      }
    });
    // Show ЄДК offer when a drug is first added to cart
    if (!wasInCart && qty > 0) _tryShowEdk(drug);
  }

  void _setFractionalQuantity(Drug drug, int blisters) async {
    _suppressHelpingHand();
    if (!drug.canSplitByBlister) return;
    final wasInCart = _cart.any((item) => item.drug.id == drug.id);

    if (blisters <= 0) {
      setState(() {
        final idx = _cart.indexWhere((item) => item.drug.id == drug.id);
        if (idx >= 0) _cart.removeAt(idx);
      });
      final r = await _lockStock(drug, 0.0);
      if (mounted) _applyKolStock(drug.id, r.kolStock); // відновити «Наявність»
      return;
    }

    final clamped = blisters.clamp(1, drug.unitsPerPackage!);
    final lockQty = clamped / drug.unitsPerPackage!;
    final result = await _lockStock(drug, lockQty);
    if (!mounted) return;
    if (!result.ok || result.grantedQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${drug.name} — залишок зарезервовано іншою касою'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _applyKolStock(drug.id, result.kolStock);
    setState(() {
      final idx = _cart.indexWhere((item) => item.drug.id == drug.id);
      if (idx >= 0) {
        _cart[idx].fractionalQty = clamped;
        _cart[idx].quantity = 0;
      } else {
        _cart.add(CartItem(drug: drug, quantity: 0, fractionalQty: clamped));
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

  /// F6 — попап ручного введення дробу (блістерів / усього в упаковці).
  /// Працює для вибраного товару; дільник можна задати вручну (навіть якщо
  /// сервер не позначив товар подільним).
  Future<void> _openFractionalInput() async {
    final drug = _selectedDrug;
    if (drug == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Спочатку виберіть товар у списку'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    // Дроблення лише для подільних або з варіативним дільником (varDel==1).
    if (!drug.canSplitByBlister && !drug.variableDivisor) {
      _showFractionalUnavailable();
      return;
    }
    final res = await showFractionalInputDialog(context,
        drugName: drug.name,
        totalPerPackage: drug.unitsPerPackage,
        // Знаменник редагується лише для варіативного дільника.
        totalEditable: drug.variableDivisor);
    if (res == null || !mounted) return;
    // Drug із заданим дільником (Y) — щоб ціна блістера й дисплей X/Y були вірні.
    final d = drug.unitsPerPackage == res.total
        ? drug
        : drug.copyWithSKUDetail(unitsPerPackage: res.total);
    // Прибрати наявний рядок цього товару, щоб оновити drug з новим Y.
    final idx = _cart.indexWhere((it) => it.drug.id == d.id);
    if (idx >= 0) setState(() => _cart.removeAt(idx));
    _setFractionalQuantity(d, res.blisters);
  }

  // ── ЄДК logic ────────────────────────────────────────────────────────────

  /// EDK offers map. Mock: keyed by Drug.id, live: keyed by Drug.ukod.
  Map<String, EdkOffer> _edkOffers = {};

  /// Check and show EDK offer after adding a donor drug to cart.
  /// If EDK not yet fetched for this drug — fetch first, then activate.
  void _tryShowEdk(Drug donorDrug) {
    final edkKey = _edkKey(donorDrug);
    if (_edkOffers.containsKey(edkKey)) {
      tryActivateEdk(edkKey, _edkOffers);
    } else if (!ApiConfig.useMock && donorDrug.skuCode != null) {
      // EDK not loaded yet (drug wasn't selected) — fetch now
      _fetchEdkOffers(donorDrug, donorDrug.skuCode!);
    }
  }

  /// Accept EDK: add 1 package of replacement, remove donor from cart.
  void _addEdkToCart() {
    if (activeEdkOffer == null) return;
    final replacement = activeEdkOffer!.drug;
    final donorId = activeEdkOffer!.donorDrugId;
    // Unlock donor drugs being removed
    for (final item in _cart) {
      final match = ApiConfig.useMock
          ? item.drug.id == donorId
          : item.drug.ukod == donorId;
      if (match) _lockStock(item.drug, 0.0);
    }
    setState(() {
      dismissedEdkIds.add(donorId);
      activeEdkOffer = null;
      _cart.removeWhere((i) =>
          ApiConfig.useMock ? i.drug.id == donorId : i.drug.ukod == donorId);
      final idx = _cart.indexWhere((i) => i.drug.id == replacement.id);
      if (idx >= 0) {
        if (_cart[idx].quantity < replacement.stock) _cart[idx].quantity++;
      } else {
        _cart.add(CartItem(drug: replacement, quantity: 1));
      }
      _selectedDrug = replacement;
    });
    // Lock replacement
    final cartItem = _cart.firstWhere((i) => i.drug.id == replacement.id);
    _lockStock(replacement, _cartItemLockQty(cartItem));
    final ri = _searchResults.indexWhere((d) => d.id == replacement.id);
    if (ri >= 0) _scrollToIndex(ri);
  }

  /// Accept EDK as blister: add 1 blister of replacement, remove donor.
  void _addEdkBlisterToCart() {
    if (activeEdkOffer == null) return;
    final replacement = activeEdkOffer!.drug;
    final donorId = activeEdkOffer!.donorDrugId;
    if (!replacement.canSplitByBlister) return;
    // Unlock donor
    for (final item in _cart) {
      final match = ApiConfig.useMock
          ? item.drug.id == donorId
          : item.drug.ukod == donorId;
      if (match) _lockStock(item.drug, 0.0);
    }
    setState(() {
      dismissedEdkIds.add(donorId);
      activeEdkOffer = null;
      _cart.removeWhere((i) =>
          ApiConfig.useMock ? i.drug.id == donorId : i.drug.ukod == donorId);
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
    _lockStock(replacement, _cartItemLockQty(_cart.firstWhere((i) => i.drug.id == replacement.id)));
    final ri = _searchResults.indexWhere((d) => d.id == replacement.id);
    if (ri >= 0) _scrollToIndex(ri);
  }

  void _dismissEdk() => dismissActiveEdk();

  // ── OOS (Out-of-Stock) EDK actions ──────────────────────────────────────

  /// Add EDK replacement for an out-of-stock drug (whole package).
  void _addOosEdkPackage(Drug oosDrug) {
    final offer = _edkOffers[_edkKey(oosDrug)];
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
    final cartItem = _cart.firstWhere((i) => i.drug.id == replacement.id);
    _lockStock(replacement, _cartItemLockQty(cartItem));
    final ri = _searchResults.indexWhere((d) => d.id == replacement.id);
    if (ri >= 0) _scrollToIndex(ri);
  }

  /// Add EDK replacement for an out-of-stock drug (1 blister).
  void _addOosEdkBlister(Drug oosDrug) {
    final offer = _edkOffers[_edkKey(oosDrug)];
    if (offer == null) return;
    final replacement = offer.drug;
    if (!replacement.canSplitByBlister) return;
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
    _lockStock(replacement, _cartItemLockQty(_cart.firstWhere((i) => i.drug.id == replacement.id)));
    final ri = _searchResults.indexWhere((d) => d.id == replacement.id);
    if (ri >= 0) _scrollToIndex(ri);
  }

  void _removeFromCart(int index) async {
    final drug = _cart[index].drug;
    setState(() => _cart.removeAt(index));
    final r = await _lockStock(drug, 0.0);
    if (mounted) _applyKolStock(drug.id, r.kolStock); // відновити «Наявність»
  }

  void _increaseQty(int index) async {
    final item = _cart[index];

    if (!item.isFractional && item.quantity >= item.drug.stock) return;
    if (item.isFractional && item.fractionalQty! >= item.drug.unitsPerPackage!) return;

    // Обчислити нову кількість для резервування (десятковий дріб)
    final double newLockQty;
    if (item.isFractional && item.drug.unitsPerPackage != null) {
      newLockQty = (item.fractionalQty! + 1) / item.drug.unitsPerPackage!;
    } else {
      newLockQty = (item.quantity + 1).toDouble();
    }

    final result = await _lockStock(item.drug, newLockQty);
    if (!mounted) return;
    if (result.grantedQty < newLockQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.grantedQty > 0
              ? '${item.drug.name} — доступно лише ${result.grantedQty.round()} шт'
              : '${item.drug.name} — залишок зарезервовано іншою касою'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _applyKolStock(item.drug.id, result.kolStock);
    setState(() {
      if (item.isFractional) {
        item.fractionalQty = item.fractionalQty! + 1;
      } else {
        item.quantity++;
      }
    });
  }

  void _decreaseQty(int index) async {
    final item = _cart[index];
    Drug? removedDrug;
    setState(() {
      if (item.isFractional) {
        if (item.fractionalQty! > 1) {
          item.fractionalQty = item.fractionalQty! - 1;
        } else {
          removedDrug = item.drug;
          _cart.removeAt(index);
        }
      } else {
        if (item.quantity > 1) {
          item.quantity--;
        } else {
          removedDrug = item.drug;
          _cart.removeAt(index);
        }
      }
    });
    if (removedDrug != null) {
      final r = await _lockStock(removedDrug!, 0.0);
      if (mounted) _applyKolStock(removedDrug!.id, r.kolStock);
    } else if (index < _cart.length) {
      final drug = _cart[index].drug;
      final r = await _lockStock(drug, _cartItemLockQty(_cart[index]));
      if (mounted) _applyKolStock(drug.id, r.kolStock);
    }
  }

  double get _cartTotal => _cart.fold(0, (s, i) => s + i.total);

  // ── Server pricing (GetSumSkid) ─────────────────────────────────────────

  /// Сума до показу в UI: серверна якщо є валідний `_serverPricing`,
  /// інакше fallback на локальну `_cartTotal`.
  double get _displayCartTotal => _serverPricing?.total ?? _cartTotal;

  /// Snapshot тих параметрів, що впливають на калькуляцію цін на сервері.
  String _pricingKey() {
    final cartPart = _cart
        .map((i) => '${i.drug.id}:${i.quantity}:${i.fractionalQty ?? 0}')
        .join('|');
    final loyaltyPart = _customerLoyalty?.cardNo ?? _customerLoyalty?.phone ?? '';
    return '$cartPart#$loyaltyPart';
  }

  /// Перевірити чи треба перерахувати ціни. Викликається з build().
  void _maybeSchedulePricing() {
    final key = _pricingKey();
    if (key == _lastPricingKey) return;
    _lastPricingKey = key;
    _schedulePricingRefresh();
    _maybePrefetchStopPrices();
  }

  /// Eager-prefetch активних акцій для всіх ukod-ів у поточному кошику.
  /// Лічильник версії інкрементується після завершення → cart rebuild'иться.
  void _maybePrefetchStopPrices() {
    final ukods = <String>{};
    for (final item in _cart) {
      final u = item.drug.ukod;
      if (u != null && u.isNotEmpty) ukods.add(u);
    }
    final ukodsKey = (ukods.toList()..sort()).join(',');
    if (ukodsKey == _lastStopPriceUkods) return;
    _lastStopPriceUkods = ukodsKey;
    if (ukods.isEmpty) return;
    unawaited(
      StopPriceService.prefetch(ukods).then((_) {
        if (!mounted) return;
        setState(() => _stopPriceVersion++);
      }),
    );
  }

  /// Префетч стоп-цін для довільного набору ukod-ів (таблиця пошуку / топ-500).
  /// Гібрид: топ-500 тягнемо у фоні після логіну, видимі результати — ліниво.
  /// Прогресивно інкрементуємо версію → таблиця rebuild'иться з акційними цінами
  /// по мірі надходження даних.
  void _prefetchStopPriceUkods(Iterable<String?> ukods) {
    final set = <String>{};
    for (final u in ukods) {
      if (u != null && u.isNotEmpty) set.add(u);
    }
    if (set.isEmpty) return;
    unawaited(
      StopPriceService.prefetch(
        set,
        onBatch: () {
          if (mounted) setState(() => _stopPriceVersion++);
        },
      ),
    );
  }

  /// Зібрати акції для кожної позиції кошика — для проброса в `cart_panel`.
  Map<String, List<StopPriceAction>> get _cartStopPrices {
    final result = <String, List<StopPriceAction>>{};
    for (final item in _cart) {
      final u = item.drug.ukod;
      if (u == null || u.isEmpty) continue;
      final actions = StopPriceService.get(u);
      if (actions != null && actions.isNotEmpty) result[u] = actions;
    }
    return result;
  }

  void _schedulePricingRefresh() {
    _pricingDebounce?.cancel();
    if (_cart.isEmpty) {
      _pricingRequestSeq++;
      _serverPricing = CartPricing.empty();
      _isLoadingPricing = false;
      return;
    }
    if (CartPriceService.isStubMode) {
      unawaited(_fetchPricing(showLoading: false));
      return;
    }
    if (!_isLoadingPricing) {
      _isLoadingPricing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    _pricingDebounce = Timer(_pricingDebounceDuration, _fetchPricing);
  }

  Future<void> _fetchPricing({bool showLoading = true}) async {
    final mySeq = ++_pricingRequestSeq;
    try {
      final pricing = await CartPriceService.fetchTotals(
        cart: _cart,
        loyalty: _customerLoyalty,
        typeProject: _isPakunokMode ? PakunokService.typeProjectTag : null,
      );
      if (!mounted || mySeq != _pricingRequestSeq) return;
      setState(() {
        _serverPricing = pricing;
        if (showLoading) _isLoadingPricing = false;
      });
    } catch (e) {
      debugPrint('CartPriceService FAIL: $e');
      if (!mounted || mySeq != _pricingRequestSeq) return;
      if (showLoading) setState(() => _isLoadingPricing = false);
    }
  }

  /// Завантажити перелік соц-програм для аптеки (один раз після логіну).
  Future<void> _loadSocialProjects() async {
    final list = await SocialProjectsService.fetchAvailable();
    if (!mounted) return;
    setState(() => _socialProjects = list);
  }

  int get _cartItemCount => _cart.length;

  void _reserveAtPharmacy(NearbyPharmacy pharmacy) async {
    final drug = _selectedDrug;
    if (drug == null) return;

    // Get product ID from ProductBrowser slug
    final slug = drug.productBrowserSlug;
    String? productId;
    if (slug != null && slug.isNotEmpty) {
      // Extract ID from slug: "bepanten-maz-5--tuba-30-g-606" → "606"
      final parts = slug.split('-');
      productId = parts.isNotEmpty ? parts.last : null;
    }

    if (productId == null) {
      // Try search to find product ID
      final results = await ProductBrowserService.searchProducts(drug.name, limit: 1);
      if (results.isNotEmpty) {
        productId = results.first.id.toString();
      }
    }

    if (productId == null || !mounted) return;

    // Get customer phone
    final phone = _customerLoyalty?.phone ?? '';
    final employeeName = _currentPharmacist?.user;

    // Create booking via API
    final result = await ProductBrowserService.createBooking(
      pharmacyId: pharmacy.id,
      productId: productId,
      price: pharmacy.price,
      phone: phone.isNotEmpty ? phone : '+380000000000',
      employeeName: employeeName,
    );

    if (!mounted) return;

    if (result.success) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReservationSuccessDialog(
          drugName: drug.displayName,
          pharmacyAddress: pharmacy.displayAddress,
        ),
      ).then((_) {
        _clearCart();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Помилка бронювання'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
    // Зняти блокування для всіх товарів перед очищенням
    _unlockAllCart();
    // NewClient — серверний reset сеансу (відмова / очищення кошика).
    unawaited(SessionService.newClient());

    // Reset search without triggering _filterDrugs (which would auto-select)
    _searchController.removeListener(_filterDrugs);
    _searchController.clear();
    _searchController.addListener(_filterDrugs);

    _barcodeLookupTimer?.cancel();
    _nameSearchTimer?.cancel();
    _helpingHandTimer?.cancel();
    setState(() {
      _cart.clear();
      _selectedDrug = null;
      _searchResults = [];
      _selectedSymptom = 'Всі';
      _cartOpen = false;
      _prescriptionOpen = false;
      _socialProjectsOpen = false;
      _showHelpingHandMarkers = false;
      _selectedSocialProject = null;
      _isServerLookup = false;
      _resetLoyalty();
      _helpingHandPrices.clear();
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
      // IdentSPL — зберегти клієнта у серверному сеансі (для накладної).
      unawaited(SessionService.identSPL(
        phone: '+380$digits',
        card: result.cardNo,
      ));
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

  // ── Рука допомоги: reveal discounted price ─────────────────────────────
  void _requestHelpingHand() {
    final drug = _selectedDrug;
    if (drug == null || !drug.hasHelpingHand) return;
    if (_helpingHandRemaining <= 0) return;
    if (_helpingHandPrices.containsKey(drug.id)) return; // already revealed

    final phone = _customerLoyalty?.phone;

    // If we have FarmaSell data, call real API
    if (drug.comingPrice != null && drug.comingCode != null && phone != null) {
      _fetchHelpingHandPrice(drug, phone);
    } else {
      // Fallback: mock discount
      final discountPct = drug.price > 100 ? 0.20 : drug.price > 50 ? 0.18 : 0.15;
      final discounted = (drug.price * (1 - discountPct)).roundToDouble();
      setState(() {
        _helpingHandPrices[drug.id] = discounted;
        _helpingHandRemaining--;
      });
    }
  }

  /// Call FarmaSell API to get real Helping Hand discount.
  Future<void> _fetchHelpingHandPrice(Drug drug, String phone) async {
    final comingPrice = double.tryParse(drug.comingPrice ?? '');
    if (comingPrice == null || drug.comingCode == null) return;

    final sku = drug.skuCode ?? drug.id.replaceFirst('srv_', '');

    final result = await FarmaSellService.getHelpingHandDiscount(
      clientPhone: phone,
      sku: sku,
      comingPrice: comingPrice,
      comingCode: drug.comingCode!,
    );

    if (!mounted) return;

    if (result.success && result.discountPrice != null) {
      setState(() {
        _helpingHandPrices[drug.id] = result.discountPrice!;
        _helpingHandRemaining--;
      });
    } else {
      // Fallback to mock on API error
      final discountPct = drug.price > 100 ? 0.20 : drug.price > 50 ? 0.18 : 0.15;
      final discounted = (drug.price * (1 - discountPct)).roundToDouble();
      setState(() {
        _helpingHandPrices[drug.id] = discounted;
        _helpingHandRemaining--;
      });
    }
  }

  // ── Рука допомоги: open dialog from table A ────────────────────────────
  void _showHelpingHandDialog(Drug drug) {
    showDialog(
      context: context,
      builder: (ctx) => HelpingHandDialog(
        drug: drug,
        remaining: _helpingHandRemaining,
        onConfirm: (phone, price, fractionalQty) {
          _onHelpingHandAddToCart(phone, price, fractionalQty, drug);
        },
      ),
    );
  }

  // ── Рука допомоги: dialog confirmed with phone + discount ────────────────
  void _onHelpingHandAddToCart(String phone, double discountPrice, int? fractionalQty, [Drug? overrideDrug]) {
    final drug = overrideDrug ?? _selectedDrug;
    if (drug == null) return;

    setState(() {
      // Store discount price
      _helpingHandPrices[drug.id] = discountPrice;
      _helpingHandRemaining--;

      // Mock-authorize customer if not yet authorized
      if (_customerLoyalty == null) {
        final masked = '+380${phone.substring(0, 2)}***${phone.substring(phone.length - 4)}';
        _customerLoyalty = CustomerLoyalty(
          phone: '+380$phone',
          bonusBalance: 0,
          cardNo: 'HH-${phone.substring(phone.length - 4)}',
        );
        // Update phone field to show masked number
        _loyaltyPhoneController.removeListener(_onLoyaltyPhoneChanged);
        _loyaltyPhoneController.removeListener(_guardPhoneCursor);
        _loyaltyPhoneController.text = masked;
        _loyaltyPhoneController.addListener(_onLoyaltyPhoneChanged);
        _loyaltyPhoneController.addListener(_guardPhoneCursor);
      }

      // Add 1 unit to cart if not already there
      final existing = _cart.indexWhere((c) => c.drug.id == drug.id);
      if (existing < 0) {
        _cart.add(CartItem(
          drug: drug,
          quantity: fractionalQty != null ? 1 : 1,
          fractionalQty: fractionalQty,
          discountPrice: discountPrice,
        ));
      } else {
        // Update existing item with discount if it didn't have one
        if (!_cart[existing].hasDiscount) {
          _cart[existing] = CartItem(
            drug: drug,
            quantity: _cart[existing].quantity,
            fractionalQty: fractionalQty ?? _cart[existing].fractionalQty,
            prescriptionData: _cart[existing].prescriptionData,
            discountPrice: discountPrice,
          );
        }
      }
    });
    final cartItem = _cart.firstWhere((c) => c.drug.id == drug.id);
    _lockStock(drug, _cartItemLockQty(cartItem));
  }

  void _confirmPhone() {
    final digits = _loyaltyPhoneController.text
        .substring(_loyaltyPhonePrefix.length)
        .replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 9 && !_isLoadingLoyalty) {
      _fetchLoyalty(digits);
    }
  }

  static final List<CartOffer> _allOffers =
      ApiConfig.useMock ? buildCartOffers(mockDrugs) : [];

  List<CartOffer> get _recommendedOffers {
    final cartIds = _cart.map((item) => item.drug.id).toSet();
    return _allOffers.where((o) => !cartIds.contains(o.drug.id)).toList();
  }

  void _addOfferToCart(Drug drug) {
    if (!_assertPakunokAllowed(drug)) return;
    setState(() {
      final idx = _cart.indexWhere((item) => item.drug.id == drug.id);
      if (idx >= 0) {
        if (_cart[idx].quantity < drug.stock) _cart[idx].quantity++;
      } else {
        _cart.add(CartItem(drug: drug, quantity: 1));
      }
    });
    final cartItem = _cart.firstWhere((i) => i.drug.id == drug.id);
    _lockStock(drug, _cartItemLockQty(cartItem));
  }

  void _addOfferBlisterToCart(Drug drug) {
    if (!drug.canSplitByBlister) return;
    if (!_assertPakunokAllowed(drug)) return;
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
    _lockStock(drug, 1);
  }

  void _processPayment({double paidByPoints = 0}) {
    if (_cart.isEmpty) return;

    // ── Calculate pharmacist earnings BEFORE clearing cart ────────────────
    // 1% of the amount actually paid by the client (total minus bonus write-off)
    final actualPaid = _cartTotal - paidByPoints;
    final percentEarning = actualPaid * 0.01;

    // Sum of pharmacist bonus badges from all cart items
    final bonusBadgesTotal = _cart.fold<double>(0, (sum, item) {
      final bonus = item.drug.pharmacistBonus ?? 0;
      final qty = item.isFractional ? 1 : item.quantity;
      return sum + bonus * qty;
    });

    final earned = percentEarning + bonusBadgesTotal;

    // ── ЛАЙК: fire-and-forget sale registration ──────────────────────────
    if (_customerLoyalty != null && _customerLoyalty!.cardNo != null) {
      _registerLoyaltySale(paidByPoints: paidByPoints);
    }

    // Очистити server-side cart (sgVRoznSetLock з qty=0 для кожної позиції) —
    // інакше товари залишаться в server-side кошику і GetSumSkid буде
    // повертати їх у наступних викликах разом з новими.
    _unlockAllCart();
    // NewClient — серверний reset сеансу для наступного клієнта (після продажу).
    unawaited(SessionService.newClient());

    // Bypass the listener so _filterDrugs doesn't auto-select a drug,
    // then reset everything including _selectedDrug → ShiftDashboard appears.
    _searchController.removeListener(_filterDrugs);
    _searchController.clear();
    _searchController.addListener(_filterDrugs);
    setState(() {
      _totalEarned += earned;
      _cart.clear();
      _selectedDrug = null;   // show ShiftDashboard after payment
      _searchResults = [];
      _resetLoyalty();
    });
  }

  /// Register sale with Sparta Loyalty (ЛАЙК) — fire-and-forget.
  ///
  /// Formats cart items into Sparta basket format and calls sale API.
  /// Runs asynchronously; failures are logged but don't block the user.
  void _registerLoyaltySale({double paidByPoints = 0}) {
    final loyalty = _customerLoyalty;
    if (loyalty == null || loyalty.cardNo == null) return;

    // Format cart → Sparta basket
    final basket = _cart.map((item) {
      final qty = item.isFractional
          ? item.fractionalQty! / item.drug.unitsPerPackage!
          : item.quantity.toDouble();
      return <String, dynamic>{
        'sku': item.drug.id.replaceFirst('srv_', ''),
        'price': item.effectivePrice,
        'qty': qty,
        // sum == price*qty з повною точністю (як очікують зовнішні API);
        // item.total округлений у копійки — лише для відображення.
        'sum': item.effectivePrice * qty,
      };
    }).toList();

    // Generate receipt number: timestamp-based for uniqueness
    final receiptNo = 'POS-${DateTime.now().millisecondsSinceEpoch}';

    LoyaltyService.sale(
      receiptNo: receiptNo,
      basket: basket,
      cardNo: loyalty.cardNo,
      paidByPoints: paidByPoints,
      cashierName: _currentPharmacist?.user,
    ).then((result) {
      if (result.success) {
        debugPrint('[ЛАЙК] Sale OK: earned=${result.balanceEarn}, '
            'burned=${result.balanceBurn}, after=${result.balanceAfter}');
      } else {
        debugPrint('[ЛАЙК] Sale FAILED: ${result.errorMsg}');
      }
    }).catchError((e) {
      debugPrint('[ЛАЙК] Sale ERROR: $e');
    });
  }

  /// Called by OrdersPanel after successful internet order payment.
  /// Accumulates pharmacist bonuses and resets to zero state.
  void _onOrderPaid(double amount) {
    _searchController.removeListener(_filterDrugs);
    _searchController.clear();
    _searchController.addListener(_filterDrugs);
    _helpingHandTimer?.cancel();
    // Очистити server-side cart перед локальним.
    _unlockAllCart();
    setState(() {
      _totalEarned += amount;
      _ordersOpen = false;
      _cart.clear();
      _selectedDrug = null;
      _searchResults = [];
      _selectedSymptom = 'Всі';
      _showHelpingHandMarkers = false;
      _helpingHandPrices.clear();
      _resetLoyalty();
      clearEdkState();
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // ─── Analogues ─────────────────────────────────────────────────────────────

  List<Drug> get _analogues {
    final group = _selectedDrug?.analogueGroup;
    if (group == null) return [];
    return (_searchResults
          .where((d) => d.analogueGroup == group && d.id != _selectedDrug!.id)
          .toList()
        ..sort((a, b) =>
            (b.pharmacistBonus ?? 0).compareTo(a.pharmacistBonus ?? 0)));
  }

  void _selectAnalogue(Drug drug) {
    // Reset analogue tracking so new drug's analogues will be fetched
    _externalAnaloguesForDrugId = null;
    _cacheAnaloguesForDrugId = null;

    // If this drug is already in search results — just select it
    final existingIdx = _searchResults.indexWhere((d) => d.id == drug.id);
    if (existingIdx >= 0) {
      setState(() {
        _selectedDrug = _searchResults[existingIdx];
        _focusQtyOnSelect = true;
        _cartOpen = false;
        activeEdkOffer = null;
      });
      _scrollToIndex(existingIdx);
      _fetchProductBrowserInfo(_searchResults[existingIdx]);
      _fetchExternalAnalogues(_searchResults[existingIdx]);
      _fetchCacheAnalogues(_searchResults[existingIdx]);
      _fetchSKUDetail(_searchResults[existingIdx]);
      return;
    }

    // Analogue not in current search results — look up Ukrainian name by ukod
    // then search by it.
    if (drug.ukod != null && drug.ukod!.isNotEmpty) {
      DrugService.searchByNameUcodes(drug.name).then((items) {
        if (!mounted) return;
        // Find item with matching ukod to get nameukr
        final match = items.cast<DrugSearchItem?>().firstWhere(
          (item) => item!.ukod == drug.ukod,
          orElse: () => null,
        );
        final searchName = match?.nameUkr ?? match?.name ?? drug.name;
        _searchController.text = searchName;
      });
    } else if (drug.name.length >= 2) {
      _searchController.text = drug.name;
    }
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
    // Перевірити чи cart змінився → запустити debounced GetSumSkid.
    _maybeSchedulePricing();

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
                                  children: _buildMainContentChildren(),
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
                            o.status != OrderStatus.paidOnline &&
                            o.status != OrderStatus.dispensed)
                        .length,
                    onExpensesTap: _toggleExpenses,
                    expensesActive: _expensesOpen,
                    onPrescriptionTap: _togglePrescription,
                    prescriptionActive: _prescriptionOpen,
                    onSocialProjectsTap: _toggleSocialProjects,
                    socialProjectsActive: _socialProjectsOpen,
                    socialProjectsHasSelection: _selectedSocialProject != null,
                    onMessagesTap: _toggleMessages,
                    messagesActive: _messagesOpen,
                    unreadMessageCount: mockMessages
                        .where((m) => m.folder == 'inbox' && !m.isRead)
                        .length,
                    onRobotTap: _toggleRobot,
                    robotActive: _robotOpen,
                    hasRobot: ApiConfig.hasRobot,
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
  /// Build the detail panel (cart, orders, expenses, etc.)
  Widget _buildDetailPanel() {
    if (_cartOpen) {
      return CartPanel(
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
        serverPricing: _serverPricing,
        isLoadingPricing: _isLoadingPricing,
        socialProjects: _socialProjects,
        stopPrices: _cartStopPrices,
        isPakunokMode: _isPakunokMode,
      );
    }
    if (_ordersOpen) {
      return OrdersPanel(
        key: _ordersPanelKey,
        onClose: _toggleOrders,
        loyalty: _customerLoyalty,
        onAddEdkPackage: (drug) => _setQuantity(drug, 1),
        onAddEdkBlister: (drug) => _setFractionalQuantity(drug, 1),
        onOrderPaid: _onOrderPaid,
        onFocusPhone: _focusPhoneField,
        layout: _ordersPanelLayout,
        onLayoutChanged: (layout) =>
            setState(() => _ordersPanelLayout = layout),
      );
    }
    if (_expensesOpen) {
      return ExpensesPanel(key: _expensesPanelKey, onClose: _toggleExpenses);
    }
    if (_prescriptionOpen) {
      return PrescriptionPanel(
        key: _prescriptionPanelKey,
        onClose: _togglePrescription,
        drugCatalog: _searchResults,
        onSearchDrugs: _searchDrugsForPrescription,
        onAddToCart: _addPrescriptionToCart,
      );
    }
    if (_socialProjectsOpen) {
      return SocialProjectsPanel(
        key: _socialProjectsPanelKey,
        projects: _socialProjects,
        onClose: _toggleSocialProjects,
        selectedProject: _selectedSocialProject,
        onProjectSelected: _onSocialProjectSelected,
      );
    }
    if (_messagesOpen) {
      return MessagesPanel(key: _messagesPanelKey, onClose: _toggleMessages);
    }
    if (_robotOpen) {
      return RobotPanel(key: _robotPanelKey, onClose: _toggleRobot, cart: _cart);
    }
    return _buildRightPanel();
  }

  /// Build main content children list — supports orders panel layout modes.
  List<Widget> _buildMainContentChildren() {
    final isOrdersFullscreen =
        _ordersOpen && _ordersPanelLayout == OrdersPanelLayout.fullscreen;

    if (isOrdersFullscreen) {
      // Fullscreen: orders panel takes all space, table hidden
      return [Expanded(child: _buildDetailPanel())];
    }

    // Default: table on the left, detail panel on the right
    return [
      Expanded(flex: 6, child: _buildTableCard()),
      const SizedBox(width: 10),
      Expanded(flex: 3, child: _buildDetailPanel()),
    ];
  }

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
                      activeEdkOffer!.drug.canSplitByBlister
                          ? _addEdkBlisterToCart
                          : null,
                  onDismiss: _dismissEdk,
                )
              : (_selectedDrug != null && _selectedDrug!.isOutOfStock)
                  ? OutOfStockPanel(
                      key: _outOfStockPanelKey,
                      drug: _selectedDrug!,
                      edkOffer: _edkOffers[_edkKey(_selectedDrug!)],
                      onAddPackage: () =>
                          _addOosEdkPackage(_selectedDrug!),
                      onAddBlister:
                          (_edkOffers[_edkKey(_selectedDrug!)]
                                      ?.drug
                                      .canSplitByBlister ??
                                  false)
                              ? () => _addOosEdkBlister(_selectedDrug!)
                              : null,
                      onDismissEdk: () {},
                      nearbyPharmacies: _nearbyPharmacies,
                      cacheAnalogues: _cacheAnalogues,
                      onSelectAnalogue: _selectAnalogue,
                      hasPhone: _isCustomerAuthorized,
                      onFocusPhone: _focusPhoneField,
                      onReserve: _reserveAtPharmacy,
                      onOrderForClient: _orderForClient,
                    )
                  : DrugDetailPanel(
                      key: const ValueKey('detail'),
                      drug: _selectedDrug,
                      promoPrice: (_selectedDrug?.ukod != null &&
                              _selectedDrug!.ukod!.isNotEmpty)
                          ? StopPriceService.promoPrice(
                              _selectedDrug!.ukod!, _selectedDrug!.price)
                          : null,
                      stopPriceActions: (_selectedDrug?.ukod != null &&
                              _selectedDrug!.ukod!.isNotEmpty)
                          ? (StopPriceService.get(_selectedDrug!.ukod!) ??
                              const [])
                          : const [],
                      analogues: _analogues,
                      externalAnalogues: _externalAnalogues,
                      cacheAnalogues: _cacheAnalogues,
                      onSelectAnalogue: _selectAnalogue,
                      onStorageLocationChanged: _onStorageLocationChanged,
                      earnedAmount: _totalEarned,
                      isCustomerAuthorized: _isCustomerAuthorized,
                      helpingHandRemaining: _helpingHandRemaining,
                      helpingHandPrice: _selectedDrug != null
                          ? _helpingHandPrices[_selectedDrug!.id]
                          : null,
                      onRequestHelpingHand: _requestHelpingHand,
                      onFocusPhone: () => _loyaltyPhoneFocusNode.requestFocus(),
                      onHelpingHandAddToCart: (phone, price, frac) => _onHelpingHandAddToCart(phone, price, frac),
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
                  ? '$_cartItemCount поз.  |  ${_displayCartTotal.asMoney} ₴'
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
      final hasQuery = _searchController.text.trim().isNotEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasQuery ? Icons.search_off_rounded : Icons.search_rounded,
              color: Colors.grey.shade300,
              size: 48,
            ),
            const SizedBox(height: 10),
            Text(
              hasQuery ? 'Нічого не знайдено' : 'Розпочніть пошук, будь ласка',
              style: const TextStyle(color: Color(0xFFB0B7C3), fontSize: 15),
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
        final ukod = drug.ukod;
        final promoPrice = (ukod != null && ukod.isNotEmpty)
            ? StopPriceService.promoPrice(ukod, drug.price)
            : null;
        return DrugListItem(
          key: ValueKey(drug.id),
          drug: drug,
          promoPrice: promoPrice,
          isSelected: isSelected,
          shouldFocusQty: isSelected && _focusQtyOnSelect,
          isEvenRow: index.isEven,
          cartQuantity: cartItem?.quantity ?? 0,
          cartFractionalQty: cartItem?.fractionalQty,
          pendingInput: isSelected ? _pendingQtyInput : null,
          showHelpingHandMarker: _showHelpingHandMarkers,
          onHelpingHandTap: () => _showHelpingHandDialog(drug),
          onTap: () {
            setState(() {
              _selectedDrug = drug;
              _focusQtyOnSelect = true;
              _cartOpen = false;
              activeEdkOffer = null;
            });
            _fetchProductBrowserInfo(drug);
            _fetchExternalAnalogues(drug);
            _fetchCacheAnalogues(drug);
            _fetchSKUDetail(drug);
            if (drug.isOutOfStock) _fetchNearbyPharmacies(drug);
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

