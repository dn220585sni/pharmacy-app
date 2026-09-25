import 'dart:async';

import 'package:flutter/material.dart';
import '../models/money.dart';
import '../models/order_extras.dart';
import '../services/order_extras_service.dart';
import '../services/fiscal_log.dart';
import 'orders/merge_checkbox.dart';
import 'orders/order_indicators.dart';
import 'orders/order_messages_dialog.dart';
import 'orders/order_duplicate_dialog.dart';
import 'orders/order_issue_block.dart';
import 'orders/order_merge_dialog.dart';
import 'orders/orders_grid.dart';
import '../mixins/checkout_mixin.dart';
import '../mixins/edk_state_mixin.dart';
import '../models/internet_order.dart';
import '../models/customer_loyalty.dart';
import '../models/payment_method.dart';
import '../models/edk_offer.dart';
import '../models/drug.dart';
import '../data/mock_orders.dart';
import '../data/edk_offers.dart';
import '../data/mock_drugs.dart';
import '../services/api_config.dart';
import '../services/cache_api_client.dart';
import '../services/auth_service.dart';
import '../services/order_service.dart';
import '../services/drug_service.dart';
import '../services/product_browser_service.dart';
import '../utils/limited_parallel.dart';
import 'checkout/bonus_discount_block.dart';
import 'checkout/cash_change_section.dart';
import 'checkout/payment_method_toggle.dart';
import 'order_edk_card.dart';
import 'disbanded_orders_screen.dart';
import 'hover_icon_button.dart';
import 'panel_layout.dart';
import 'likomat_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OrdersPanel — Internet orders panel shown in the right detail column.
// Three-screen flow: Order List → Order Details → Checkout.
// ─────────────────────────────────────────────────────────────────────────────

/// Layout mode for the orders panel within the POS screen.
/// Спільний з іншими панелями (`panel_layout.dart`); стара назва лишається,
/// щоб не чіпати всі згадки.
typedef OrdersPanelLayout = PanelLayout;

class OrdersPanel extends StatefulWidget {
  final VoidCallback onClose;
  final CustomerLoyalty? loyalty;
  final void Function(Drug drug)? onAddEdkPackage;
  final void Function(Drug drug)? onAddEdkBlister;

  /// Called after a successful order payment with the order total.
  /// PosScreen uses this to accumulate pharmacist bonuses + reset to zero state.
  final void Function(double amount)? onOrderPaid;

  /// Called to focus the phone input when loyalty is needed.
  final VoidCallback? onFocusPhone;

  /// Current layout mode of the orders panel.
  final OrdersPanelLayout layout;

  /// Called when the user changes the layout mode.
  final void Function(OrdersPanelLayout layout)? onLayoutChanged;

  /// Лише для тестів: готовий список замість GetOrders.
  @visibleForTesting
  final List<InternetOrder>? debugOrders;

  const OrdersPanel({
    super.key,
    required this.onClose,
    this.loyalty,
    this.onAddEdkPackage,
    this.onAddEdkBlister,
    this.onOrderPaid,
    this.onFocusPhone,
    this.layout = OrdersPanelLayout.right,
    this.onLayoutChanged,
    this.debugOrders,
  });

  @override
  State<OrdersPanel> createState() => OrdersPanelState();
}

class OrdersPanelState extends State<OrdersPanel>
    with CheckoutMixin, EdkStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  InternetOrder? _selectedOrder;
  late List<InternetOrder> _filteredOrders;

  /// Mutable copy of mock orders (allows status changes).
  late List<InternetOrder> _orders;

  /// Index of the highlighted order in _filteredOrders (auto-selects first match).
  int _highlightedIndex = -1;

  /// SKUs scanned during the current order collection (simulated by price tap).
  final Set<String> _scannedSkus = {};

  /// Whether the "Розформовані замовлення" screen is open.
  bool _showDisbandedOrders = false;

  /// Обраний фільтр списку. Рівно ОДИН (ТЗ Юлії §2: статуси, що виключають
  /// один одного, не можна обрати разом).
  /// Микола 23.09: вікно відкривається одразу на «Не оплачені».
  String _activeFilter = _filterNotPaid;

  static const _filterNotPaid = 'Не оплачені';
  static const _filterPaid = 'Оплачені';
  static const _filterRefused = 'Відмови';

  /// Плашки фільтра (Микола 22.09; 23.09 «Не зібрані» → «Не оплачені»).
  /// «Всі» немає (Катя 23.09: у роздрібі такого фільтра нема — або ті, по
  /// яких ведеться робота, або обрана плашка). Повторний клік по обраній
  /// повертає «Не оплачені».
  static const List<String> _filterLabels = [
    _filterNotPaid,
    _filterPaid,
    _filterRefused,
    _filterWithMessages,
  ];

  /// «З перепискою» — повернуто як звичайну плашку (Микола 24.09): серед
  /// незавершених лише ті, де є повідомлення від кол-центру або аптеки.
  static const _filterWithMessages = 'З перепискою';

  /// Не фільтр, а ПОШУК по всіх статусах (ТЗ Юлії §2: номера не знайшли
  /// серед «Не оплачених» → «Шукати» по всіх). Тимчасова плашка з хрестиком;
  /// на сервері — три запити (дефолт + оплачені + відмови).
  static const _filterSearchAll = 'Пошук по всіх';

  /// Службовий фільтр — без плашки; вмикається кліком по сигналу «Glovo · N»
  /// над списком і показується тимчасовою плашкою з хрестиком. Сигнал і
  /// плашки «Час на збір» прибрано (Микола 24.09): таймер від отримання
  /// замовлення в списку не потрібен.
  static const _filterGlovo = 'Glovo';

  /// Ознаки замовлень, яких GetOrders ще не віддає (переписка з КЦ,
  /// автопідтвердження, час на збір, Glovo №, передоплата) — поки мок.
  Map<String, OrderExtras> _extras = {};

  OrderExtras _extrasOf(InternetOrder o) => _extras[o.id] ?? OrderExtras.empty;

  /// Замовлення, позначені чекбоксом «Об'єднати» (ТЗ §9).
  final Set<String> _checkedIds = {};

  /// Останній введений номер телефону — живе до закриття програми, щоб при
  /// відпуску 2+ замовлень одному покупцеві не перепитувати номер (ТЗ §2).
  static String? _lastPhone;

  /// Замовлення з перевіреним кодом видачі (передоплата, ТЗ §10).
  final Set<String> _issueVerifiedIds = {};
  final TextEditingController _prescriptionCtrl = TextEditingController();

  /// Захист від дублювання останніх 4 цифр номера: запит, за яким відкриття
  /// через Enter заблоковане, доки касир не уточнить повний номер.
  String? _dupBlockedQuery;
  Timer? _dupTimer;
  bool _dupDialogOpen = false;

  /// Whether the search field has non-empty text (drives highlight).
  bool get _hasQuery => _searchController.text.trim().isNotEmpty;

  /// Whether orders are loading from API.
  bool _isLoading = false;

  /// Extended order data from GetOrderData API.
  OrderData? _orderData;
  bool _orderDataLoading = false;

  /// Selected date for orders (defaults to today).
  /// Період запиту GetOrders «від — до» (як у «Витратах по касі»). null =
  /// сьогодні; «до» раніше за «від» — міняємо місцями при запиті.
  ///
  /// За замовчуванням — останні 7 діб (ТЗ Юлії §1): незібране замовлення
  /// живе в аптеці до 3 діб, плюс ті, що лишились нерозформованими.
  DateTime? _dateFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime? _dateTo = DateTime.now();

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Нормалізований період: (від, до) без часу, від ≤ до.
  (DateTime, DateTime) get _period {
    final now = DateTime.now();
    var from = _dateFrom ?? now;
    var to = _dateTo ?? from;
    from = DateTime(from.year, from.month, from.day);
    to = DateTime(to.year, to.month, to.day);
    if (to.isBefore(from)) (from, to) = (to, from);
    return (from, to);
  }

  // ── CheckoutMixin overrides ─────────────────────────────────────────────

  @override
  double get baseTotal => _selectedOrder?.total ?? 0;

  @override
  CustomerLoyalty? get checkoutLoyalty => widget.loyalty;

  // ── ЄДК (pharmaceutical substitution for order items) ─────────────────────

  /// EDK offers. Mock: keyed by OrderItem.sku, live: keyed by OrderItem.ukod.
  Map<String, EdkOffer> _orderEdkOffers = {};

  /// Initialize EDK offers for orders (mock only; live uses per-item GetEdkOffers).
  Future<void> _initOrderEdkOffers() async {
    if (ApiConfig.useMock) {
      _orderEdkOffers = buildMockOrderEdkOffers(mockDrugs);
    }
  }

  // ── Checkout state ─────────────────────────────────────────────────────────
  bool _orderCheckoutMode = false;

  /// Public — allows PosScreen to check if detail is open (for Esc cascade).
  bool get isDetailOpen => _selectedOrder != null && !_orderCheckoutMode;

  /// Public — allows PosScreen to check if checkout is open.
  bool get isInCheckout => _orderCheckoutMode;

  /// Public — allows PosScreen to close detail via Esc.
  void closeDetail() {
    setState(() {
      _selectedOrder = null;
      _scannedSkus.clear();
      _orderData = null;
      _orderDataLoading = false;
    });
  }

  /// Public — allows PosScreen to exit checkout via Esc.
  void exitOrderCheckout() {
    setState(() => _orderCheckoutMode = false);
  }

  /// Public — whether the disbanded orders screen is open.
  bool get isDisbandedOpen => _showDisbandedOrders;

  /// Public — close disbanded orders screen (Esc).
  void closeDisbanded() {
    setState(() => _showDisbandedOrders = false);
  }

  /// Refused orders for the disbanded screen.
  List<InternetOrder> get _refusedOrders =>
      _orders.where((o) => o.status == OrderStatus.refused).toList();

  /// Public — focuses the search field (called after panel opens).
  void focusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _orders = [];
    _filteredOrders = [];
    _searchController.addListener(_filterOrders);
    _loadOrders();
    _initOrderEdkOffers();
  }

  /// Load orders from GetOrders API (or mock fallback).
  /// Запити до GetOrders під активний фільтр (контракт 22.09: за
  /// замовчуванням сервер віддає лише незавершені, оплачені й відмови — за
  /// прапорцями; прапорця «все» немає і не буде — Катя 23.09). Старий сервер
  /// прапорці ігнорує і віддає все за `status=all` — тоді клієнтський фільтр
  /// [_matchesFilters] відсіює зайве, а пошук по всіх злиє три однакові
  /// відповіді.
  Future<List<InternetOrder>> _fetchForFilter(String from, String to) async {
    switch (_activeFilter) {
      case _filterPaid:
        return OrderService.fetchOrders(
            dateFrom: from, dateTo: to, onlyPay: true);
      case _filterRefused:
        return OrderService.fetchOrders(
            dateFrom: from, dateTo: to, onlyRefusal: true);
      case _filterWithMessages:
        // Катя 25.09: Chat=1 → сервер лишає лише замовлення з активною
        // перепискою. Старий сервер параметр ігнорує — тоді відсіює
        // клієнтський [_matchesFilters].
        return OrderService.fetchOrders(
            dateFrom: from, dateTo: to, onlyChat: true);
      case _filterSearchAll:
        final parts = await Future.wait([
          OrderService.fetchOrders(dateFrom: from, dateTo: to),
          OrderService.fetchOrders(dateFrom: from, dateTo: to, onlyPay: true),
          OrderService.fetchOrders(
              dateFrom: from, dateTo: to, onlyRefusal: true),
        ]);
        final seen = <String>{};
        return [
          for (final list in parts)
            for (final o in list)
              if (seen.add(o.id)) o,
        ];
      default:
        return OrderService.fetchOrders(dateFrom: from, dateTo: to);
    }
  }

  Future<void> _loadOrders() async {
    final debugOrders = widget.debugOrders;
    if (debugOrders != null) {
      setState(() {
        _orders = List<InternetOrder>.from(debugOrders);
        _filteredOrders = _sorted(_orders);
      });
      await _loadExtras();
      return;
    }
    if (ApiConfig.useMock) {
      setState(() {
        _orders = List<InternetOrder>.from(mockOrders);
        _filteredOrders = _sorted(_orders);
      });
      await _loadExtras();
      return;
    }
    setState(() => _isLoading = true);
    final (from, to) = _period;
    try {
      final orders = await _fetchForFilter(_fmtDate(from), _fmtDate(to));
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _filteredOrders = _sorted(_orders);
        _isLoading = false;
      });
      await _loadExtras();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _orders = [];
        _filteredOrders = [];
        _isLoading = false;
      });
    }
  }

  /// Public — reload orders from API (pull-to-refresh / manual).
  void refreshOrders() => _loadOrders();

  /// Дотягнути ознаки замовлень і оновити сигнал на бічній панелі.
  Future<void> _loadExtras() async {
    final extras = await OrderExtrasService.fetchExtras(_orders);
    if (!mounted) return;
    setState(() {
      _extras = extras;
      _checkedIds.removeWhere((id) => !_orders.any((o) => o.id == id));
    });
    _filterOrders();
    _publishAlerts();
  }

  int get _newGlovoCount => _orders
      .where((o) =>
          o.type == OrderType.glovo && o.status == OrderStatus.newOrder)
      .length;

  /// Лічильник на кнопці «Інтернет-замовлення» (Микола 23.09) — рівно ті
  /// замовлення, що підняті вгору «Не оплачених»: терміновий збір (Glovo,
  /// Лікомат, Нова пошта) і нові повідомлення. Прочитав фармацевт
  /// повідомлення — замовлення випадає, лічильник зменшується.
  void _publishAlerts() {
    final priority =
        _orders.where((o) => _isNotPaid(o) && _notPaidRank(o) < 2);
    OrdersAlerts.state.value = OrdersAlertState(
      count: priority.length,
      // Пульсація йшла від таймера «час вийшов» — таймер прибрано (24.09).
      pulse: false,
      hasUnread: priority.any((o) => _extrasOf(o).hasUnread),
    );
  }

  /// Спеціальне замовлення (страхова, доставка, оплачене онлайн): у картці
  /// замовлення показуємо блок видачі/атрибутів. Окремого вікна немає —
  /// усе в одному інтерфейсі (Микола 22.09).
  bool _isSpecial(InternetOrder o) =>
      o.type == OrderType.likTas ||
      o.type == OrderType.glovo ||
      o.type == OrderType.novaPoshta ||
      _extrasOf(o).prepaid;

  /// Передоплата: ознака зі списку (мок) або підтверджена GetOrderData.
  bool _isPrepaid(InternetOrder o) =>
      _extrasOf(o).prepaid ||
      (_selectedOrder?.id == o.id && _orderData?.isPaidOnline == true);

  Future<void> _pickOrdersDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
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
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
    // Період — параметр запиту, а не локальний фільтр: тягнемо заново.
    _loadOrders();
  }

  /// Чип дати «від»/«до» — такий самий, як у «Витратах по касі».
  Widget _buildDateChip(String label, DateTime? value, {required bool isFrom}) {
    final hasValue = value != null;
    final text = hasValue ? _fmtDate(value) : label;
    return GestureDetector(
      onTap: () => _pickOrdersDate(isFrom: isFrom),
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
                    : const Color(0xFF6B7280),
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
                  _loadOrders();
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

  @override
  void didUpdateWidget(covariant OrdersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loyalty == null && widget.loyalty != null && availableDiscount == null) {
      _fetchAvailableOrderDiscount();
    }
    if (widget.loyalty == null && availableDiscount != null) {
      availableDiscount = null;
    }
  }

  @override
  void dispose() {
    _dupTimer?.cancel();
    _prescriptionCtrl.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    disposeCheckout();
    super.dispose();
  }

  /// Whether an order matches any of the active filter chips.
  bool _matchesFilters(InternetOrder o) {
    switch (_activeFilter) {
      case _filterSearchAll:
        return true;
      case _filterNotPaid:
        return _isNotPaid(o);
      case _filterPaid:
        return o.status == OrderStatus.paidOnline ||
            o.status == OrderStatus.dispensed;
      case _filterRefused:
        return o.status == OrderStatus.customerRefusal ||
            o.status == OrderStatus.pharmacyRefusal ||
            o.status == OrderStatus.refused;
      case _filterWithMessages:
        // Новий контракт: сервер уже відібрав (поле `Chat` непорожнє);
        // старий — за моком повідомлень.
        return o.chat.isNotEmpty || _extrasOf(o).hasMessages;
      case _filterGlovo:
        return o.type == OrderType.glovo;
    }
    return true;
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Пошук лише за прямими ідентифікаторами (ТЗ §2): телефон клієнта, номер
  /// замовлення, П.І.Б., номер доставки Glovo. За назвою товару — НЕ шукаємо:
  /// це провокує видачу чужого замовлення.
  bool _matchesQuery(InternetOrder o, String query) {
    if (o.reserveNumber.toLowerCase().contains(query)) return true;
    // `SearchData` з контракту 22.09 свідомо не використовуємо: це внутрішній
    // рядок пошуку старого роздрібу (Alt+0), Катя 23.09 — «нам може і не
    // потрібно аналізувати».
    final name = o.customerName?.toLowerCase();
    if (name != null && name.contains(query)) return true;
    final glovo = _extrasOf(o).glovoNumber?.toLowerCase();
    if (glovo != null && glovo.contains(query)) return true;
    // Телефон: запит складається лише з цифр і знаків набору номера.
    final qDigits = _digits(query);
    final onlyPhoneChars = RegExp(r'^[\d\s()+\-]+$').hasMatch(query);
    if (onlyPhoneChars && qDigits.length >= 4) {
      final phone = _digits(o.customerPhone ?? '');
      if (phone.isNotEmpty && phone.contains(qDigits)) return true;
    }
    return false;
  }

  /// Схоже на повний номер телефону (0XXXXXXXXX / 380XXXXXXXXX).
  static bool _looksLikePhone(String query) {
    final d = _digits(query);
    return (d.length == 10 && d.startsWith('0')) ||
        (d.length == 12 && d.startsWith('380'));
  }

  /// «Не оплачені»: чинні, ще не пробиті на касі — нові, в обробці,
  /// зібрані, в роботі.
  static bool _isNotPaid(InternetOrder o) =>
      o.status == OrderStatus.newOrder ||
      o.status == OrderStatus.inProgress ||
      o.status == OrderStatus.collected ||
      o.status == OrderStatus.atWork;

  /// Терміновий збір (Микола 23.09): Glovo, Лікомат, Нова пошта — поки
  /// замовлення ще не зібране.
  bool _needsUrgentCollect(InternetOrder o) =>
      (o.type == OrderType.glovo ||
          o.type == OrderType.novaPoshta ||
          o.isLockerOrder) &&
      (o.status == OrderStatus.newOrder ||
          o.status == OrderStatus.inProgress ||
          o.status == OrderStatus.atWork);

  /// Місце в «Не оплачених»: 0 — терміновий збір, 1 — нове повідомлення,
  /// 2 — решта.
  int _notPaidRank(InternetOrder o) {
    if (_needsUrgentCollect(o)) return 0;
    if (_extrasOf(o).hasUnread) return 1;
    return 2;
  }

  /// Sort: urgent non-collected first, then the rest chronologically.
  /// «Не оплачені»: терміновий збір → нові повідомлення → решта.
  /// Усередині групи — вихідний порядок (List.sort не стабільний, тому
  /// порівнюємо ще й за індексом).
  List<InternetOrder> _sorted(List<InternetOrder> orders) {
    final list = orders.where(_matchesFilters).toList();
    if (_activeFilter == _filterNotPaid) {
      final idx = {for (var i = 0; i < list.length; i++) list[i].id: i};
      list.sort((a, b) {
        final r = _notPaidRank(a).compareTo(_notPaidRank(b));
        return r != 0 ? r : idx[a.id]!.compareTo(idx[b.id]!);
      });
      return list;
    }
    list.sort((a, b) {
      final aUrgent = a.isUrgent && a.status != OrderStatus.collected && a.status != OrderStatus.paidOnline && a.status != OrderStatus.dispensed;
      final bUrgent = b.isUrgent && b.status != OrderStatus.collected && b.status != OrderStatus.paidOnline && b.status != OrderStatus.dispensed;
      if (aUrgent && !bUrgent) return -1;
      if (!aUrgent && bUrgent) return 1;
      return 0; // preserve original order within groups
    });
    return list;
  }

  void _filterOrders() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredOrders = _sorted(_orders);
        _highlightedIndex = -1;
      } else {
        _filteredOrders = _sorted(
          _orders.where((o) => _matchesQuery(o, query)).toList(),
        );
        // Auto-highlight the first match
        _highlightedIndex = _filteredOrders.isNotEmpty ? 0 : -1;
      }
    });
    if (_looksLikePhone(query)) _lastPhone = _digits(query);
    _checkDuplicateDigits(query);
    // Статуси могли змінитись (зібрали, відпустили) — лічильник на кнопці теж.
    _publishAlerts();
  }

  // ── Захист від дублювання останніх 4 цифр номера ─────────────────────────

  /// Чинні замовлення, номер яких закінчується на [digits].
  List<InternetOrder> _duplicatesFor(String digits) => _orders
      .where((o) =>
          o.reserveNumber.endsWith(digits) &&
          (o.status == OrderStatus.newOrder ||
              o.status == OrderStatus.collected ||
              o.status == OrderStatus.inProgress))
      .toList();

  /// Рівно 4 цифри і 2+ чинних замовлень → Enter блокується, з'являється
  /// вікно уточнення. Вікно чекає 0,7 с без набору: інакше воно вискакувало
  /// б посеред введення повного номера (повний номер механізм не чіпає).
  void _checkDuplicateDigits(String query) {
    _dupTimer?.cancel();
    final isFour = RegExp(r'^\d{4}$').hasMatch(query);
    final blocked = isFour && _duplicatesFor(query).length >= 2;
    final next = blocked ? query : null;
    if (next != _dupBlockedQuery) setState(() => _dupBlockedQuery = next);
    if (blocked) {
      _dupTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted && _searchController.text.trim() == query) {
          _showDuplicateDialog(query);
        }
      });
    }
  }

  Future<void> _showDuplicateDialog(String digits) async {
    if (_dupDialogOpen || _selectedOrder != null) return;
    final dups = _duplicatesFor(digits);
    if (dups.length < 2) return;
    _dupDialogOpen = true;
    final full = await showOrderDuplicateDialog(context,
        lastDigits: digits, duplicates: dups);
    _dupDialogOpen = false;
    if (!mounted) return;
    // ОК → повний номер у пошук (Enter розблоковано); Скасувати → пошук
    // очищується, відкривати нема чого.
    _searchController.text = full ?? '';
    _searchController.selection =
        TextSelection.collapsed(offset: _searchController.text.length);
    _searchFocusNode.requestFocus();
  }

  /// Один вибір; повторний клік по обраному повертає «Не оплачені».
  /// Набір замовлень залежить від фільтра вже на сервері (контракт 22.09:
  /// оплачені/відмови — окремими прапорцями), тому фільтр = новий запит.
  void _toggleFilter(String label) {
    setState(() {
      _activeFilter = _activeFilter == label ? _filterNotPaid : label;
    });
    _loadOrders();
  }

  /// Пошук серед «Не оплачених» нічого не дав → пропонуємо шукати по всіх.
  bool get _offerSearchAll =>
      _hasQuery && _activeFilter == _filterNotPaid && _filteredOrders.isEmpty;

  /// «Шукати» (або Enter у пошуку): пошук по всіх статусах, той самий запит.
  void _searchAllOrders() {
    setState(() => _activeFilter = _filterSearchAll);
    _loadOrders();
    _searchFocusNode.requestFocus();
  }

  /// Open highlighted order (Enter from search field).
  void _openHighlighted() {
    if (_offerSearchAll) {
      _searchAllOrders();
      return;
    }
    final blocked = _dupBlockedQuery;
    if (blocked != null && blocked == _searchController.text.trim()) {
      _dupTimer?.cancel();
      _showDuplicateDialog(blocked);
      return;
    }
    if (_highlightedIndex >= 0 &&
        _highlightedIndex < _filteredOrders.length) {
      _selectOrder(_filteredOrders[_highlightedIndex]);
    }
  }

  void _selectOrder(InternetOrder order) {
    setState(() {
      _selectedOrder = order;
      _scannedSkus.clear();
      activeEdkOffer = null;
      _orderData = null;
      _orderDataLoading = false;
    });
    // Show EDK immediately when opening an eligible order
    _triggerEdkForOrder(order);
    // Enrich order items with drug details (image, storage, series, expiry)
    _enrichOrderItems(order);
    // Fetch extended order data (source, phone, delivery, payment, etc.)
    _fetchOrderData(order.id);
  }

  /// Enrich order items with data from GetSKUdetail and GetSKUprice APIs.
  Future<void> _enrichOrderItems(InternetOrder order) async {
    if (ApiConfig.useMock) {
      // In mock mode, populate with sample data
      setState(() {
        for (final item in order.items) {
          if (!item.isEnriched) {
            item.enrichedStorageLocation = 'Ст.А-${item.sku.hashCode.abs() % 20 + 1}';
            item.enrichedSeries = 'SN${item.sku.substring(0, 4)}';
            item.enrichedExpiryDate = '12.2027';
            item.isEnriched = true;
          }
        }
      });
      return;
    }

    // Відгук 23.09, п.3: раніше позиції збагачувались ПОСЛІДОВНО, і кожна
    // чекала ще й картинку з anc.ua (до 8 с × 2 пошуки) — велике замовлення
    // відкривалось хвилину. Тепер два проходи:
    //  1) деталі + стелажі для всіх позицій, не більше 3 одночасно (стільки
    //     слотів у Caché); показуємо кожну, щойно готова;
    //  2) картинки — окремо, у фоні, після першого проходу, по 2 одночасно;
    //     вони ніколи не затримують стелаж/серію/термін.
    // Відкрили інше замовлення — решту не тягнемо.
    bool abandoned() => !mounted || !identical(_selectedOrder, order);

    final todo = <OrderItem>[];
    for (final item in order.items) {
      if (item.isEnriched) continue;
      // «Знижка на чек» та інші службові рядки — без кодів, збагачувати нічого.
      if (item.isServiceLine) {
        item.isEnriched = true;
        continue;
      }
      todo.add(item);
    }
    if (todo.isEmpty) {
      // Слід у журналі: інакше «відкрив, а фото/стелажів немає» не відрізнити
      // від «збагачення не запускалось» (24.09).
      final service = order.items.where((i) => i.isServiceLine).length;
      final first = order.items.firstOrNull;
      FiscalLog.log('ІЗ ${order.id} (${order.statusLabel}): збагачувати '
          'нічого — позицій ${order.items.length}, без кодів $service, уже '
          'збагачених ${order.items.length - service}'
          '${first == null ? '' : '; перша: "${first.name}" s-код '
              '"${first.sku}" код СЦ ${first.kodSc ?? "—"}'}');
      return;
    }

    final sw = Stopwatch()..start();
    // Позиції, яким після Caché ще потрібна картинка (+ їхній detail).
    final needImage = <(OrderItem, SKUDetailResult?)>[];

    await forEachLimited(todo, 3, (item) async {
      try {
        // GetSKUdetail — за кодом СЦ (ids) або ukod; GetSKUprice (стелажі) —
        // за s-кодом партії (skod). Раніше в обидва йшов ids (код СЦ), і
        // GetSKUprice стелажів не давав — він приймає лише s-код/штрихкод.
        final results = await Future.wait([
          DrugService.fetchSKUDetail(item.detailIds),
          DrugService.getStockAndPrices(item.sku),
        ]);
        final detail = results[0] as SKUDetailResult?;
        final priceResult = results[1] as DrugPriceResult;
        if (abandoned()) return;

        setState(() {
          if (detail != null) {
            item.enrichedSeries = detail.series;
            item.enrichedExpiryDate = detail.expiryDate;
          }
          final cacheImg = detail?.imageUrl;
          if (cacheImg != null && cacheImg.isNotEmpty) {
            item.enrichedImageUrl = cacheImg;
          }
          // Build storage location string from GetSKUprice
          final parts = <String>[];
          if (priceResult.stelazh?.isNotEmpty == true) parts.add('Ст.${priceResult.stelazh}');
          if (priceResult.vitrina?.isNotEmpty == true) parts.add('Вт.${priceResult.vitrina}');
          if (priceResult.polka?.isNotEmpty == true) parts.add('П.${priceResult.polka}');
          if (priceResult.robot?.isNotEmpty == true) parts.add('Робот ${priceResult.robot}');
          if (parts.isNotEmpty) {
            item.enrichedStorageLocation = parts.join(' / ');
          }
          item.isEnriched = true;
        });
        if (item.enrichedImageUrl == null || item.enrichedImageUrl!.isEmpty) {
          needImage.add((item, detail));
        }

        // Fetch EDK offers using short ids from GetSKUdetail
        if (detail?.skuCode != null && detail!.skuCode!.isNotEmpty) {
          _fetchOrderEdkOffers(item, detail.skuCode!);
        }
      } catch (e) {
        debugPrint('Enrichment failed for SKU ${item.sku}: $e');
        item.isEnriched = true; // Don't retry
      }
    }, shouldStop: abandoned);

    final detailsMs = sw.elapsedMilliseconds;
    if (abandoned()) return;

    // Прохід 2: картинки. Кеш по ukod — усі s-коди одного товару отримують
    // одне зображення, і anc.ua питаємо про нього один раз.
    final imageCache = <String, Future<String?>>{};
    await forEachLimited(needImage, 2, (pair) async {
      final (item, detail) = pair;
      final cacheKey = item.ukod ?? item.name;
      final url = await imageCache.putIfAbsent(
          cacheKey, () => _lookupOrderItemImage(item, detail));
      if (abandoned()) return;
      if (url != null && url.isNotEmpty) {
        setState(() => item.enrichedImageUrl = url);
      }
    }, shouldStop: abandoned);

    FiscalLog.log('ІЗ ${order.id}: збагачено ${todo.length} поз. — деталі й '
        'стелажі $detailsMs мс, з картинками ${sw.elapsedMilliseconds} мс '
        '(картинок з anc.ua: ${needImage.length})');
  }

  /// Картинка позиції замовлення з anc.ua: за кодом СЦ (детерміновано),
  /// інакше пошук за торговою назвою зі звіркою форми випуску. `null` —
  /// не знайшли; помилки мережі ковтаємо (це лише картинка).
  Future<String?> _lookupOrderItemImage(
      OrderItem item, SKUDetailResult? detail) async {
    String? imageUrl;
    try {
      // anc.ua за кодом СЦ — детермінований шлях без звірки назв
      // (той самий, що в картці товару з 1f36d0c).
      final kodSc = item.kodSc ?? detail?.kodSc;
      if (kodSc != null) {
        final byKod = await ProductBrowserService.fetchByKodSc(kodSc);
        imageUrl = byKod?.imageUrl;
      }

      // Fallback: якщо ні Caché, ні код СЦ не дали зображення — пошук за назвою
      if (imageUrl == null || imageUrl.isEmpty) {
            {
              List<ProductSearchResult> searchResults = [];

              // Шукаємо по торговій назві (без форми випуску — ламає пошук anc.ua)
              {
                final words = item.name.split(RegExp(r'\s+'));
                final stopPatterns = ['ГРАН', 'ТАБЛ', 'КАПС', 'СУСП', 'СИРОП',
                  'КРЕМ', 'МАЗЬ', 'РОЗЧ', 'ГЕЛЬ', 'СПРЕЙ', 'КРАП', 'ПОР',
                  'АМП', 'СУПОЗ', 'ФЛАК', 'ШИП', 'Д/', 'Р-Н', 'Р/Н', 'N'];
                final brandWords = <String>[];
                for (final w in words) {
                  final upper = w.toUpperCase();
                  if (stopPatterns.any((p) => upper.startsWith(p))) break;
                  brandWords.add(w);
                }
                final searchName = (brandWords.isNotEmpty ? brandWords : [words.first])
                    .map((w) => w.isNotEmpty
                        ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
                        : w)
                    .join(' ')
                    .replaceAll(RegExp(r'(?<=\s|^)H(?=\s|$)'), 'Н')
                    .replaceAll(RegExp(r'(?<=\s|^)C(?=\s|$)'), 'С')
                    .replaceAll(RegExp(r'(?<=\s|^)B(?=\s|$)'), 'В')
                    .replaceAll(RegExp(r'(?<=\s|^)A(?=\s|$)'), 'А');
                searchResults = await ProductBrowserService.searchProducts(
                  searchName,
                  limit: 5,
                );
              }

              if (searchResults.isNotEmpty) {
                // Матчимо по назві + формі випуску
                String norm(String s) => s.toLowerCase().replaceAll('и', 'і').replaceAll('ы', 'і');
                final itemFirst = norm(item.name.split(RegExp(r'\s+')).first);

                // Визначаємо форму випуску з назви замовлення
                const formMap = {
                  'ТАБЛ': 'таблетк', 'КАПС': 'капсул', 'СУСП': 'суспенз',
                  'СИРОП': 'сироп', 'ГРАН': 'гранул', 'КРЕМ': 'крем',
                  'МАЗЬ': 'мазь', 'ГЕЛЬ': 'гель', 'СПРЕЙ': 'спрей',
                  'КРАП': 'крапл', 'Р-Н': 'розчин', 'Р/Н': 'розчин',
                  'РОЗЧ': 'розчин', 'ПОР': 'порош', 'АМП': 'ампул',
                  'СУПОЗ': 'супозитор', 'ШИП': 'шипуч', 'АЕРОЗОЛЬ': 'аерозол',
                };
                final itemUpper = item.name.toUpperCase();
                String? itemForm;
                for (final e in formMap.entries) {
                  if (itemUpper.contains(e.key)) {
                    itemForm = e.value;
                    break;
                  }
                }

                // Спочатку шукаємо збіг по назві + формі
                ProductSearchResult? match;
                if (itemForm != null) {
                  match = searchResults.cast<ProductSearchResult?>().firstWhere(
                    (r) => norm(r!.name.split(RegExp(r'\s+')).first) == itemFirst
                        && r.name.toLowerCase().contains(itemForm!),
                    orElse: () => null,
                  );
                }
                // Fallback: тільки по назві
                match ??= searchResults.cast<ProductSearchResult?>().firstWhere(
                  (r) => norm(r!.name.split(RegExp(r'\s+')).first) == itemFirst,
                  orElse: () => null,
                );
                imageUrl = match?.imageUrl;
              }
            }
      }
    } catch (e) {
      debugPrint('Image search failed for "${item.name}": $e');
    }
    return (imageUrl == null || imageUrl.isEmpty) ? null : imageUrl;
  }

  /// Fetch EDK offers for an order item from Caché GetEdkOffers.
  void _fetchOrderEdkOffers(OrderItem item, String detailIds) {
    if (ApiConfig.useMock) return;
    final edkKey = item.ukod ?? item.sku;

    DrugService.fetchEdkOffers(detailIds).then((apiOffers) async {
      if (!mounted || apiOffers.isEmpty) return;
      final offer = apiOffers.first;

      // Fetch image from anc.ua
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

      // Fetch SKUDetail for replacement drug to get pharmacistBonus
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
        _orderEdkOffers[edkKey] = EdkOffer(
          drug: replacementDrug,
          donorDrugId: edkKey,
          description: '${offer.replacementName} — ${offer.reason.toLowerCase()}.',
          script: offer.script,
          promoLabel: promo,
          bonus: offer.replacementBonus,
        );
      });
      debugPrint('ЄДК order: ids=$detailIds → ${offer.replacementName} '
          '(ціна=${offer.replacementPrice}, бонус ЄДК=${offer.replacementBonus}, '
          'бонус фарм=${replacementDetail?.pharmacistBonus ?? 0})');
    }).catchError((e) {
      debugPrint('ЄДК order: error for ids=$detailIds: $e');
    });
  }

  /// Fetch extended order data from GetOrderData API.
  Future<void> _fetchOrderData(String orderId) async {
    setState(() => _orderDataLoading = true);
    try {
      final resp = await CacheApiClient().call(
        'GetOrderData',
        params: {'orderId': orderId},
      );
      if (!mounted || _selectedOrder?.id != orderId) return;
      if (resp.isOk) {
        setState(() {
          _orderData = OrderData.fromJson(resp.data);
          _orderDataLoading = false;
        });
      } else {
        setState(() => _orderDataLoading = false);
      }
    } catch (e) {
      debugPrint('GetOrderData failed for $orderId: $e');
      if (mounted) setState(() => _orderDataLoading = false);
    }
  }

  /// Find the first EDK offer for an order's items and activate it.
  void _triggerEdkForOrder(InternetOrder order) {
    if (order.isLockerOrder) return;
    if (order.type == OrderType.glovo) return;
    if (order.type == OrderType.novaPoshta) return;
    if (order.status == OrderStatus.dispensed) return;
    if (order.status == OrderStatus.paidOnline) return;
    for (final item in order.items) {
      final edkKey = ApiConfig.useMock ? item.sku : (item.ukod ?? '');
      if (tryActivateEdk(edkKey, _orderEdkOffers)) return;
    }
  }

  /// Whether EDK is allowed for the current order.
  /// Disabled for Glovo, Nova Poshta, and locker-eligible orders.
  bool get _edkAllowed {
    final order = _selectedOrder;
    if (order == null) return false;
    if (order.isLockerOrder) return false;
    if (order.type == OrderType.glovo) return false;
    if (order.type == OrderType.novaPoshta) return false;
    return true;
  }

  /// Simulate barcode scan (triggered by tapping item price).
  void _scanItem(OrderItem item) {
    final wasScanned = _scannedSkus.contains(item.sku);
    setState(() => _scannedSkus.add(item.sku));
    // Trigger EDK if this item has an offer and wasn't already scanned
    if (_edkAllowed && !wasScanned) {
      final edkKey = ApiConfig.useMock ? item.sku : (item.ukod ?? '');
      tryActivateEdk(edkKey, _orderEdkOffers);
    }
  }

  void _acceptEdkPackage() {
    final offer = activeEdkOffer;
    if (offer == null) return;
    widget.onAddEdkPackage?.call(offer.drug);
    setState(() => activeEdkOffer = null);
  }

  void _acceptEdkBlister() {
    final offer = activeEdkOffer;
    if (offer == null) return;
    widget.onAddEdkBlister?.call(offer.drug);
    setState(() => activeEdkOffer = null);
  }

  /// Public — dismiss EDK from PosScreen (Esc).
  /// Delegates to [EdkStateMixin.dismissActiveEdk].
  void dismissEdk() => dismissActiveEdk();

  /// Public — accept EDK package from PosScreen (Enter)
  void acceptEdkPackage() => _acceptEdkPackage();

  /// Whether all real items (total >= 0) in the current order have been scanned.
  bool get _allScanned {
    final order = _selectedOrder;
    if (order == null) return false;
    final realItems = order.items.where((i) => i.total >= 0);
    return realItems.every((i) => _scannedSkus.contains(i.sku));
  }

  /// Enter checkout mode for the current order.
  void _enterOrderCheckout() {
    final order = _selectedOrder;
    if (order == null) return;
    // Передоплачене (LiqPay): каса заблокована, доки код видачі з SMS
    // покупця не пройшов перевірку (ТЗ §10).
    if (_isPrepaid(order) && !_issueVerifiedIds.contains(order.id)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Спершу введіть і перевірте код видачі замовлення '
            'з SMS покупця.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFFB45309),
        duration: Duration(seconds: 4),
      ));
      return;
    }
    // Collected/paidOnline orders skip scan check (already collected).
    // Non-collected orders require all items to be scanned first.
    // TODO: paidOnline — skip register payment step (separate task)
    if (order.status != OrderStatus.collected &&
        order.status != OrderStatus.paidOnline &&
        !_allScanned) {
      return;
    }
    setState(() => _orderCheckoutMode = true);
  }

  /// Place order into locker → show cell picker → change status to collected.
  void _placeInLocker() {
    final order = _selectedOrder;
    if (order == null || !_allScanned) return;

    showLikomatDialog(context).then((selectedCell) async {
      if (selectedCell == null) return; // user cancelled
      final idx = _orders.indexWhere((o) => o.id == order.id);
      if (idx < 0) return;

      // Оновлюємо статус на сервері
      final response = await OrderService.updateOrderStatus(
        orderId: order.id,
        newStatus: 'apteka make',
        user: AuthService.currentUser ?? '',
      );
      if (!response.isOk) {
        debugPrint('UpdateOrderStatus failed: ${response.result}');
      }

      final updated = order.copyWith(
        status: OrderStatus.collected,
        lockerCell: selectedCell,
      );
      setState(() {
        _orders[idx] = updated;
        _selectedOrder = null;
        _scannedSkus.clear();
        _filterOrders();
      });
    });
  }

  // ── Refusal flow ──────────────────────────────────────────────────────────

  /// Регламентовані причини (ТЗ Юлії §5). «Негабарит» потрібен для
  /// кур'єрських замовлень: Glovo великогабаритні позиції не відсікає.
  static const _refusalReasons = [
    'Товару немає на залишку',
    'Пересорт',
    'Негабарит',
  ];

  /// Show refusal reason picker dialog.
  void _showRefuseDialog() {
    final order = _selectedOrder;
    if (order == null) return;

    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: const Icon(Icons.cancel_outlined,
            color: Color(0xFFEF4444), size: 32),
        title: const Text(
          'Причина відмови',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Оберіть причину відмови від замовлення:',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            for (final reason in _refusalReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, reason),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1C1C2E),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(reason,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Скасувати',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ).then((reason) {
      if (reason != null) _refuseOrder(reason);
    });
  }

  /// Apply refusal with the selected reason.
  void _refuseOrder(String reason) async {
    final order = _selectedOrder;
    if (order == null) return;
    final idx = _orders.indexWhere((o) => o.id == order.id);
    if (idx < 0) return;

    // Оновлюємо статус на сервері
    final response = await OrderService.updateOrderStatus(
      orderId: order.id,
      newStatus: 'apteka otkaz',
      user: AuthService.currentUser ?? '',
    );
    if (!response.isOk) {
      debugPrint('UpdateOrderStatus (refuse) failed: ${response.result}');
    }

    final updated = order.copyWith(
      status: OrderStatus.pharmacyRefusal,
      refusalReason: reason,
    );
    setState(() {
      _orders[idx] = updated;
      _selectedOrder = updated;
      _scannedSkus.clear();
      _filterOrders();
    });
  }

  /// Cancel refusal and return order to newOrder status.
  void _cancelRefusal() {
    final order = _selectedOrder;
    if (order == null) return;
    final idx = _orders.indexWhere((o) => o.id == order.id);
    if (idx < 0) return;
    final updated = order.copyWith(
      status: OrderStatus.newOrder,
      clearRefusalReason: true,
    );
    setState(() {
      _orders[idx] = updated;
      _selectedOrder = updated;
      _filterOrders();
    });
  }

  void _resetOrderCheckoutState() {
    _orderCheckoutMode = false;
    resetCheckout();
  }

  /// A8: чи можна проводити оплату інтернет-замовлення.
  ///
  /// `false` на живому сервері: цей шлях ставить `UpdateOrderStatus('apteka
  /// pay')` БЕЗ фіскального чека — гроші беруться, чек не пробивається. Кошик
  /// (`cart_panel`) має повний конвеєр (накладна → ПРРО → PutKasa), а
  /// OrdersPanel до нього ще не підключений (задача D1 — спільний SaleService).
  /// У mock-режимі лишаємо робочим: там немає ні грошей, ні ПРРО.
  static bool get _orderPaymentAllowed => ApiConfig.useMock;

  void _processOrderPayment() {
    final order = _selectedOrder;
    if (order == null) return;

    if (!_orderPaymentAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Оплата інтернет-замовлення тимчасово недоступна: фіскальний чек '
            'для цього шляху ще не підключено. Проведіть продаж через кошик.',
          ),
          duration: Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFB45309),
        ),
      );
      return;
    }

    // Оновлюємо статус на сервері
    // Об'єднаний чек: статус оновлюється по кожному вихідному замовленню.
    final paidIds =
        order.isMerged ? order.mergedFrom.map((r) => r.id) : [order.id];
    for (final id in paidIds) {
      OrderService.updateOrderStatus(
        orderId: id,
        newStatus: 'apteka pay',
        user: AuthService.currentUser ?? '',
      ).then((response) {
        if (!response.isOk) {
          debugPrint('UpdateOrderStatus (pay) $id failed: ${response.result}');
        }
      });
    }

    setState(() => showPaymentSuccess = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      // Mark order as dispensed
      final idx = _orders.indexWhere((o) => o.id == order.id);
      if (idx >= 0) {
        _orders[idx] = order.copyWith(status: OrderStatus.dispensed);
      }
      setState(() {
        _resetOrderCheckoutState();
        _selectedOrder = null;
        _scannedSkus.clear();
        _filterOrders();
      });
      // Notify PosScreen → accumulate pharmacist bonuses + go to zero state
      widget.onOrderPaid?.call(order.total);
    });
  }

  Future<void> _fetchAvailableOrderDiscount() async {
    if (widget.loyalty == null) return;
    // Реального API персональної знижки ще немає — на live не вигадуємо її з
    // останньої цифри телефону (див. cart_panel).
    if (!ApiConfig.useMock) return;
    final lastDigit = widget.loyalty!.phone.characters.last;
    final d = int.tryParse(lastDigit) ?? 0;
    final discount = d >= 5 ? d.toDouble() : null;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => availableDiscount = discount);
  }

  Future<void> _requestOrderDiscount() async {
    if (widget.loyalty == null || isLoadingDiscount) return;
    if (availableDiscount != null) {
      setState(() => personalDiscount = availableDiscount);
      return;
    }
    if (!ApiConfig.useMock) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Персональна знижка недоступна'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => isLoadingDiscount = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final lastDigit = widget.loyalty!.phone.characters.last;
    final d = int.tryParse(lastDigit) ?? 0;
    final discount = d >= 5 ? (d.toDouble()) : null;
    setState(() {
      availableDiscount = discount;
      personalDiscount = discount;
      isLoadingDiscount = false;
    });
    if (discount == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Знижка для цього клієнта не передбачена'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

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
        child: _orderCheckoutMode && _selectedOrder != null
            ? _buildCheckoutScreen(_selectedOrder!)
            : _selectedOrder != null
                ? _buildDetailScreen(_selectedOrder!)
                : _showDisbandedOrders
                    ? DisbandedOrdersScreen(
                        refusedOrders: _refusedOrders,
                        onBack: () =>
                            setState(() => _showDisbandedOrders = false),
                        onClose: widget.onClose,
                        onDisband: (checkedIds) {
                          setState(() {
                            _orders.removeWhere(
                                (o) => checkedIds.contains(o.id));
                            _filteredOrders = _sorted(_orders);
                            if (_refusedOrders.isEmpty) {
                              _showDisbandedOrders = false;
                            }
                          });
                        },
                      )
                    : _buildListScreen(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 1 — ORDER LIST
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildListScreen() {
    return Column(
      key: const ValueKey('orders_list'),
      children: [
        _buildListHeader(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        _buildSearchField(),
        _buildDateRow(),
        _buildAlertRow(),
        _buildFilterChips(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        Expanded(child: _buildOrdersList()),
        _buildListFooter(),
      ],
    );
  }

  /// Рядок періоду «від — до» під пошуком (як у «Витратах по касі»).
  Widget _buildDateRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Row(
        children: [
          _buildDateChip('від', _dateFrom, isFrom: true),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('—',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
          ),
          _buildDateChip('до', _dateTo, isFrom: false),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const Icon(Icons.shopping_bag_outlined,
              color: Color(0xFF1E7DC8), size: 17),
          const SizedBox(width: 8),
          const Text(
            'Замовлення',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          // Hotkey badge matching CartPanel F2 style
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Text(
              'Ctrl+I',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Spacer(),
          // Refresh button
          if (!_isLoading)
            HoverIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Оновити замовлення',
              onTap: () => _loadOrders(),
            )
          else
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          const SizedBox(width: 4),
          // Fullscreen toggle — next to close button
          if (widget.onLayoutChanged != null)
            HoverIconButton(
              icon: widget.layout == OrdersPanelLayout.fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              tooltip: widget.layout == OrdersPanelLayout.fullscreen
                  ? 'Звичайний розмір'
                  : 'На весь екран',
              onTap: () => widget.onLayoutChanged!(
                widget.layout == OrdersPanelLayout.fullscreen
                    ? OrdersPanelLayout.right
                    : OrdersPanelLayout.fullscreen,
              ),
            ),
          const SizedBox(width: 2),
          // Close button
          HoverIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Закрити',
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  /// Сигнал списку (ТЗ §8): нові Glovo. Рядка немає, доки сигналу немає.
  /// Клік — фільтр списку. Лічильник «Від кол-центру» прибрано (Микола
  /// 23.09), сигнал «Час на збір» — 24.09.
  Widget _buildAlertRow() {
    final glovo = _newGlovoCount;
    if (glovo == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (glovo > 0)
            OrderPill(
              icon: Icons.delivery_dining_rounded,
              text: 'Glovo · $glovo',
              color: const Color(0xFFEA580C),
              background: const Color(0xFFFFF7ED),
              border: const Color(0xFFFED7AA),
              tooltip: 'Нові замовлення Glovo',
              onTap: () => _toggleFilter(_filterGlovo),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final last = _lastPhone;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(child: _buildSearchInput()),
          const SizedBox(width: 6),
          // «Останній №» — номер телефону, введений раніше в цій сесії.
          Tooltip(
            message: last == null
                ? 'Номер телефону ще не вводили'
                : 'Підставити $last',
            child: SizedBox(
              height: 34,
              child: OutlinedButton(
                onPressed: last == null
                    ? null
                    : () {
                        _searchController.text = last;
                        _searchController.selection =
                            TextSelection.collapsed(offset: last.length);
                        _searchFocusNode.requestFocus();
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E7DC8),
                  disabledForegroundColor: const Color(0xFF9CA3AF),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: const Text('Останній №'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchInput() {
    return Padding(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 34,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C2E)),
          onSubmitted: (_) => _openHighlighted(),
          decoration: InputDecoration(
            hintText: 'Телефон, № замовлення, П.І.Б., Glovo',
            hintStyle:
                const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
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
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.requestFocus();
                    },
                    child: const Icon(Icons.close_rounded,
                        size: 16, color: Color(0xFF9CA3AF)),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        children: [
          // Тимчасова плашка (пошук по всіх, Glovo) — першою, щоб її було
          // видно й у вузькій панелі, де рядок плашок прокручується.
          if (!_filterLabels.contains(_activeFilter)) _activeFilter,
          ..._filterLabels,
        ].map((label) {
          final isSelected = _activeFilter == label;
          final isTemporary = !_filterLabels.contains(label);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => _toggleFilter(label),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF6B7280),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isTemporary) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.close_rounded,
                          size: 12, color: Colors.white),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrdersList() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 12),
              Text(
                'Завантаження замовлень...',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    if (_filteredOrders.isEmpty && _offerSearchAll) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded,
                  size: 40, color: Color(0xFFD1D5DB)),
              const SizedBox(height: 8),
              const Text(
                'Замовлення за таким номером серед Не оплачених не знайдено, '
                'зробити пошук по всіх замовленнях',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF374151), fontSize: 14),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _searchAllOrders,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E7DC8),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: const Text('Шукати'),
              ),
            ],
          ),
        ),
      );
    }
    if (_filteredOrders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, size: 40, color: Color(0xFFD1D5DB)),
              SizedBox(height: 8),
              Text(
                'Замовлень не знайдено',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final dupBlocked = _dupBlockedQuery != null;
    if (widget.layout == OrdersPanelLayout.fullscreen) {
      return OrdersGrid(
        orders: _filteredOrders,
        extras: _extras,
        checkedIds: _checkedIds,
        canCheck: _canCheck,
        onToggleCheck: _toggleCheck,
        onOpen: _selectOrder,
        onOpenMessages: _openMessages,
        highlightedIndex: _hasQuery && !dupBlocked ? _highlightedIndex : -1,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: _filteredOrders.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, thickness: 1, color: Color(0xFFF4F5F8)),
      itemBuilder: (context, index) {
        final order = _filteredOrders[index];
        final extras = _extrasOf(order);
        return _OrderListTile(
          order: order,
          extras: extras,
          checked: _checkedIds.contains(order.id),
          onCheck: _canCheck(order) ? () => _toggleCheck(order) : null,
          onOpenMessages: () => _openMessages(order),
          highlighted:
              _hasQuery && !dupBlocked && index == _highlightedIndex,
          onTap: () => _selectOrder(order),
        );
      },
    );
  }

  Widget _buildListFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_checkedIds.isNotEmpty) _buildMergeBar(),
        _buildDisbandedFooter(),
      ],
    );
  }

  /// «Об'єднати (N)» — відпуск 2+ замовлень одного клієнта одним чеком.
  Widget _buildMergeBar() {
    final n = _checkedIds.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F7FF),
        border: Border(top: BorderSide(color: Color(0xFFBFDBFE))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: n >= 2 ? _mergeChecked : null,
                icon: const _MergeIcon(size: 15),
                label: Text(n >= 2
                    ? 'Об\'єднати ($n)'
                    : 'Оберіть ще одне'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E7DC8),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  disabledForegroundColor: const Color(0xFF6B7280),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => setState(_checkedIds.clear),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Зняти позначки'),
          ),
        ],
      ),
    );
  }

  /// Об'єднувати можна лише чинні, ще не об'єднані замовлення.
  bool _canCheck(InternetOrder o) =>
      !o.isMerged &&
      (o.status == OrderStatus.newOrder ||
          o.status == OrderStatus.inProgress ||
          o.status == OrderStatus.collected ||
          o.status == OrderStatus.atWork);

  void _toggleCheck(InternetOrder o) {
    setState(() {
      if (!_checkedIds.remove(o.id)) _checkedIds.add(o.id);
    });
  }

  /// Об'єднання позначених замовлень в один чек (ТЗ §9).
  Future<void> _mergeChecked() async {
    final list = _orders.where((o) => _checkedIds.contains(o.id)).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    if (list.length < 2) return;

    // Один чек — один клієнт: різні телефони об'єднувати не даємо.
    final phones = {
      for (final o in list)
        if (_digits(o.customerPhone ?? '').isNotEmpty)
          _digits(o.customerPhone!).replaceFirst(RegExp(r'^38'), ''),
    };
    if (phones.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Обрані замовлення належать різним клієнтам — '
            'в один чек об\'єднуються лише замовлення одного клієнта.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFFB45309),
        duration: Duration(seconds: 5),
      ));
      return;
    }

    // Повний склад кожного замовлення у вікні підтвердження (Микола, 24.09):
    // об'єднують часто прямо зі списку, не відкриваючи, і до цього моменту
    // ніде не видно, що саме піде в один чек.
    final yes = await showOrderMergeDialog(context, list);
    if (yes != true || !mounted) return;
    _mergeOrderList(list);
  }

  Future<void> _openMessages(InternetOrder order) async {
    final next = await showOrderMessagesDialog(context, order);
    if (!mounted) return;
    setState(() => _extras = {..._extras, order.id: next});
    _filterOrders();
    _publishAlerts();
  }

  Widget _buildDisbandedFooter() {
    final refusedCount = _refusedOrders.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: refusedCount > 0
          ? SizedBox(
              width: double.infinity,
              height: 34,
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _showDisbandedOrders = true;
                }),
                icon: const Icon(Icons.inventory_2_outlined, size: 15),
                label: Text('Розформовані замовлення · $refusedCount'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  backgroundColor: const Color(0xFFF9FAFB),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 2 — ORDER DETAIL (mirrors CartPanel layout)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetailScreen(InternetOrder order) {
    final showEdk = activeEdkOffer != null &&
        order.status != OrderStatus.dispensed &&
        order.status != OrderStatus.paidOnline;

    return Column(
      key: ValueKey('order_detail_${order.id}'),
      children: [
        _buildDetailHeader(order),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        // Items + order data + EDK card scroll together
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              // ── Extended order data (GetOrderData) ───────────────
              // Only shown when there are extra fields not in the header
              // (payment, delivery, insurance, medical programs, etc.)
              _buildOrderDataSection(),
              if (_isSpecial(order) || _isPrepaid(order))
                OrderIssueBlock(
                  key: ValueKey('issue_${order.id}'),
                  order: order,
                  extras: _extrasOf(order),
                  paidOnlineConfirmed: _orderData?.isPaidOnline == true,
                  verified: _issueVerifiedIds.contains(order.id),
                  onVerifiedChanged: (ok) => setState(() {
                    if (ok) {
                      _issueVerifiedIds.add(order.id);
                    } else {
                      _issueVerifiedIds.remove(order.id);
                    }
                  }),
                  prescriptionController: _prescriptionCtrl,
                ),
              if (order.isMerged) _buildMergedSummary(order),
              for (final item in order.items)
                _OrderItemRow(
                  item: item,
                  isScanned: _scannedSkus.contains(item.sku),
                  canScan: order.status != OrderStatus.collected &&
                      order.status != OrderStatus.paidOnline &&
                      order.status != OrderStatus.dispensed,
                  onScan: () => _scanItem(item),
                ),
              // ── EDK offer card (inline after items) ────────────────
              if (showEdk)
                OrderEdkCard(
                  offer: activeEdkOffer!,
                  onAcceptPackage: _acceptEdkPackage,
                  onAcceptBlister: _acceptEdkBlister,
                  onDismiss: dismissActiveEdk,
                ),
            ],
          ),
        ),
        _buildDetailFooter(order),
      ],
    );
  }

  // ── Extended order data section (GetOrderData) ───────────────────────────

  Widget _buildOrderDataSection() {
    if (_orderDataLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            SizedBox(width: 8),
            Text(
              'Завантаження даних замовлення...',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      );
    }
    if (_orderData == null || _orderData!.isEmpty) {
      return const SizedBox.shrink();
    }
    final fields = _orderData!.fields;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF64748B)),
              SizedBox(width: 6),
              Text(
                'Дані замовлення',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final entry in fields.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1E293B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Detail header (mirrors CartPanel header) ──────────────────────────────

  Widget _buildDetailHeader(InternetOrder order) {
    final dateStr =
        '${order.dateTime.day.toString().padLeft(2, '0')}.${order.dateTime.month.toString().padLeft(2, '0')}'
        '  ${order.dateTime.hour}:${order.dateTime.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 10, 12),
      child: Column(
        children: [
          // Row 1: back + reserve number + status badge
          Row(
            children: [
              HoverIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'До списку',
                onTap: () => setState(() {
                  _selectedOrder = null;
                  _orderData = null;
                  _orderDataLoading = false;
                }),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.receipt_long_rounded,
                  color: Color(0xFF1E7DC8), size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '#${order.reserveNumber}',
                  style: const TextStyle(
                    color: Color(0xFF1C1C2E),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Галочка автопідтвердження (мок) прибрана з шапки (24.09).
              // Бейдж часу «Час спливає/вийшов» у шапці прибрано (24.09),
              // як і в списку.
              _OrderStatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: date + source type + locker cell
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Row(
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF6B7280)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: order.type == OrderType.glovo
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFFF4F5F8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    order.typeLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: order.type == OrderType.glovo
                          ? const Color(0xFFB45309)
                          : const Color(0xFF6B7280),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (order.isLockerOrder) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7FF),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 11, color: Color(0xFF1E7DC8)),
                        SizedBox(width: 4),
                        Text(
                          'Лікомат',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E7DC8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Online payment badge (from GetOrderData LiqPay fields)
                if (_orderData?.isPaidOnline == true) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF6EE7B7)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.payment_rounded,
                            size: 11, color: Color(0xFF059669)),
                        SizedBox(width: 4),
                        Text(
                          'Оплачено онлайн',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Customer info
                if (order.customerPhone != null || order.customerName != null) ...[
                  const Spacer(),
                  Icon(Icons.person_outline_rounded,
                      size: 12, color: const Color(0xFF9CA3AF)),
                  const SizedBox(width: 4),
                  Text(
                    [
                      if (order.customerName != null) order.customerName!,
                      if (order.customerPhone != null) order.customerPhone!,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Collected order actions: single "Розрахувати F5" button ────────────────

  Widget _buildCollectedActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton(
            onPressed: _enterOrderCheckout,
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF1E7DC8),
              elevation: 0,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.point_of_sale_rounded, size: 16),
                const SizedBox(width: 8),
                Text(
                    _selectedOrder != null && _isPrepaid(_selectedOrder!)
                        ? 'Пробити по касі'
                        : 'Розрахувати',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'F5',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Звести кілька замовлень в одне (перше — цільове). Об'єднання поки
  /// ЛОКАЛЬНЕ: серверної зведеної накладної немає, статуси після оплати
  /// оновлюються по кожному вихідному замовленню окремо.
  void _mergeOrderList(List<InternetOrder> list) {
    if (list.length < 2) return;
    final target = list.first;
    final targetIdx = _orders.indexWhere((o) => o.id == target.id);
    if (targetIdx < 0) return;

    final refs = <MergedOrderRef>[
      for (final o in list)
        if (o.isMerged)
          ...o.mergedFrom
        else
          MergedOrderRef(
              id: o.id, reserveNumber: o.reserveNumber, total: o.total),
    ];
    final allCollected =
        list.every((o) => o.status == OrderStatus.collected);
    final merged = InternetOrder(
      id: target.id,
      reserveNumber: target.reserveNumber,
      dateTime: target.dateTime,
      total: list.fold(0.0, (s, o) => s + o.total),
      // Якщо хоч одне ще не зібране — об'єднане треба досканувати.
      status: allCollected ? OrderStatus.collected : OrderStatus.inProgress,
      lockerCell: target.lockerCell,
      type: target.type,
      items: [for (final o in list) ...o.items],
      customerPhone: target.customerPhone ??
          list.map((o) => o.customerPhone).whereType<String>().firstOrNull,
      customerName: target.customerName ??
          list.map((o) => o.customerName).whereType<String>().firstOrNull,
      isUrgent: list.any((o) => o.isUrgent),
      isLockerEligible: false,
      refusalReason: target.refusalReason,
      mergedFrom: refs,
    );

    final sourceIds = {for (final o in list.skip(1)) o.id};
    FiscalLog.log('ІЗ об\'єднання в один чек: '
        '${refs.map((r) => '№${r.reserveNumber}').join(' + ')} = '
        '${merged.total.asMoney} ₴ (локально)');
    setState(() {
      _orders[targetIdx] = merged;
      _orders.removeWhere((o) => sourceIds.contains(o.id));
      _checkedIds.clear();
      _selectedOrder = merged;
      _scannedSkus.clear();
      _orderData = null;
      _orderDataLoading = false;
      // Усе зібране → одразу форма оплати об'єднаного замовлення.
      _orderCheckoutMode = allCollected;
    });
    _filterOrders();
    // Об'єднане замовлення — новий об'єкт, і якщо джерела не відкривали
    // окремо, його позиції ще без стелажів/серій/фото (Микола 24.09:
    // «фото взагалі не відображаються»). Збагачуємо як звичайне відкриття;
    // уже збагачені позиції пропускаються.
    _enrichOrderItems(merged);
    _fetchOrderData(merged.id);
  }

  // ── Not-collected order actions: Розрахувати + Лікомат + Відмовити + Відсутність

  Widget _buildNotCollectedActions() {
    final allDone = _allScanned;
    final order = _selectedOrder;
    final showLocker = order != null && order.isLockerEligible;

    return Column(
      children: [
        // Primary row: Розрахувати + Покласти в лікомат (both disabled until scanned)
        if (showLocker)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: allDone ? _enterOrderCheckout : null,
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF1E7DC8),
                      disabledForegroundColor: const Color(0xFFD1D5DB),
                      disabledBackgroundColor: const Color(0xFFF4F5F8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.point_of_sale_rounded, size: 15),
                        const SizedBox(width: 4),
                        const Flexible(
                          child: Text('Розрахувати',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (allDone) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0x33FFFFFF),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'F5',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: allDone ? _placeInLocker : null,
                    icon: const Icon(Icons.lock_outline_rounded, size: 16),
                    label: const Text('В лікомат',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF1E7DC8),
                      disabledForegroundColor: const Color(0xFFD1D5DB),
                      disabledBackgroundColor: const Color(0xFFF4F5F8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          // Only "Розрахувати" full-width for non-locker orders
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              onPressed: allDone ? _enterOrderCheckout : null,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF1E7DC8),
                disabledForegroundColor: const Color(0xFFD1D5DB),
                disabledBackgroundColor: const Color(0xFFF4F5F8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.point_of_sale_rounded, size: 16),
                  const SizedBox(width: 8),
                  const Text('Розрахувати',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (allDone) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'F5',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        // Secondary row: Відмовити + Повідомити
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: _showRefuseDialog,
                  icon: const Icon(Icons.cancel_outlined, size: 15),
                  label: const Text('Відмовити',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    backgroundColor: const Color(0xFFFEF2F2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // TODO: wire up notify
                  },
                  icon: const Icon(Icons.sms_failed_outlined, size: 15),
                  label: const Text('Відсутність',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Refused order actions (cancel refusal) ──────────────────────────────

  Widget _buildRefusedActions(InternetOrder order) {
    return Column(
      children: [
        // Refusal reason banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.cancel_rounded,
                      size: 15, color: Color(0xFFEF4444)),
                  SizedBox(width: 6),
                  Text('Замовлення відмовлено',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFDC2626))),
                ],
              ),
              if (order.refusalReason != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 21),
                  child: Text(
                    'Причина: ${order.refusalReason}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF991B1B),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Cancel refusal button
        SizedBox(
          width: double.infinity,
          height: 42,
          child: OutlinedButton.icon(
            onPressed: _cancelRefusal,
            icon: const Icon(Icons.undo_rounded, size: 16),
            label: const Text('Скасувати відмову',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1E7DC8),
              side: const BorderSide(color: Color(0xFFBFDBFE)),
              backgroundColor: const Color(0xFFF0F7FF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Detail footer (mirrors CartPanel footer with total) ───────────────────

  Widget _buildDetailFooter(InternetOrder order) {
    final formattedTotal =
        order.total.asMoney;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Сума:',
                style: TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$formattedTotal ₴',
                style: const TextStyle(
                  color: Color(0xFF1E7DC8),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          // Locker hint for collected orders awaiting pickup
          if (order.lockerCell != null &&
              order.status == OrderStatus.collected) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF1E7DC8),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Запропонуйте клієнту забрати замовлення '
                      'самостійно в лікоматі, будь ласка',
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
          ],
          // Scan hint for not-yet-collected orders
          if (order.status != OrderStatus.collected &&
              order.status != OrderStatus.paidOnline &&
              order.status != OrderStatus.dispensed &&
              !_allScanned) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF1E7DC8),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Зберіть і відскануйте весь товар '
                      'в замовленні, будь ласка',
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
          ],
          const SizedBox(height: 10),
          _buildMessagesButton(order),
          const SizedBox(height: 8),
          // Action buttons — depend on order status
          if (order.status == OrderStatus.paidOnline ||
              order.status == OrderStatus.dispensed)
            const SizedBox.shrink()
          else if (order.status == OrderStatus.pharmacyRefusal)
            _buildRefusedActions(order)
          else if (order.status == OrderStatus.collected)
            _buildCollectedActions()
          else
            _buildNotCollectedActions(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 3 — CHECKOUT (identical to CartPanel checkout)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCheckoutScreen(InternetOrder order) {
    return Column(
      key: const ValueKey('order_checkout'),
      children: [
        _buildCheckoutHeader(order),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (order.isMerged) _buildMergedSummary(order),
                _buildCheckoutBody(order),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// «Перелік замовлень» об'єднаного чека (ТЗ §9): № резерву й сума
  /// кожного, кількість і загальна сума. Накладні з'являться, коли сервер
  /// навчиться створювати зведену.
  Widget _buildMergedSummary(InternetOrder order) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _MergeIcon(size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Об\'єднане замовлення · ${order.mergedFrom.length} шт.',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C2E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final r in order.mergedFrom)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text('№ резерву ${r.reserveNumber}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF374151))),
                  ),
                  Text('${r.total.asMoney} ₴',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1C1C2E))),
                ],
              ),
            ),
          const Divider(height: 12, color: Color(0xFFBFDBFE)),
          Row(
            children: [
              const Expanded(
                child: Text('Сума замовлень',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C2E))),
              ),
              Text('${order.total.asMoney} ₴',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E7DC8))),
            ],
          ),
        ],
      ),
    );
  }

  /// «Повідомлення» — переписка з кол-центром (ТЗ §5). Читати можна завжди;
  /// писати першим — лише по замовленнях понад 1000 грн.
  Widget _buildMessagesButton(InternetOrder order) {
    final extras = _extrasOf(order);
    final canOpen = extras.hasMessages || OrderExtrasService.canSend(order);
    final count = extras.messages.length;
    return SizedBox(
      width: double.infinity,
      height: 34,
      child: OutlinedButton.icon(
        onPressed: () {
          if (canOpen) {
            _openMessages(order);
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Написати кол-центру можна лише по замовленнях на '
                'суму понад ${OrderExtrasService.outgoingMinTotal.asMoney} ₴ '
                '(обмеження передачі персональних даних).'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB45309),
            duration: const Duration(seconds: 4),
          ));
        },
        icon: Icon(
          extras.hasUnread
              ? Icons.mark_email_unread_rounded
              : Icons.mail_outline_rounded,
          size: 15,
        ),
        label: Text(
          extras.hasUnread
              ? 'Повідомлення · нове від кол-центру'
              : count > 0
                  ? 'Повідомлення · $count'
                  : 'Повідомлення',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor:
              canOpen ? const Color(0xFF1E7DC8) : const Color(0xFF9CA3AF),
          side: BorderSide(
              color: extras.hasUnread
                  ? const Color(0xFF1E7DC8)
                  : const Color(0xFFE5E7EB)),
          backgroundColor:
              extras.hasUnread ? const Color(0xFFE8F3FB) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildCheckoutHeader(InternetOrder order) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              _resetOrderCheckoutState();
              setState(() => _orderCheckoutMode = false);
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F8),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: Color(0xFF6B7280), size: 16),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.point_of_sale_rounded,
              color: Color(0xFF1E7DC8), size: 17),
          const SizedBox(width: 8),
          const Text(
            'Розрахунок',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Order number badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F3FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '#${order.reserveNumber}',
              style: const TextStyle(
                color: Color(0xFF1E7DC8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 7),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F8),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Color(0xFF9CA3AF), size: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutBody(InternetOrder order) {
    final formattedTotal =
        finalTotal.asMoney;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── "До сплати" — big total ──────────────────────────────────────
          Row(
            children: [
              const Text(
                'До сплати:',
                style: TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$formattedTotal ₴',
                style: const TextStyle(
                  color: Color(0xFF1E7DC8),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          // ── Bonuses + Discount block ───────────────────────────────────────
          const SizedBox(height: 12),
          BonusDiscountBlock(
            loyalty: widget.loyalty,
            useBonuses: useBonuses,
            onUseBonusesChanged: (v) {
              setState(() {
                useBonuses = v;
                if (useBonuses && widget.loyalty != null) {
                  final max = baseTotal - discountAmount;
                  final capped =
                      widget.loyalty!.bonusBalance.clamp(0, max);
                  bonusCtr.text = capped.toStringAsFixed(0);
                }
              });
            },
            bonusController: bonusCtr,
            cartTotal: baseTotal,
            discountAmount: discountAmount,
            effectiveBonusAmount: effectiveBonusAmount,
            personalDiscount: personalDiscount,
            availableDiscountAmount: availableDiscount != null
                ? baseTotal * availableDiscount! / 100
                : null,
            isLoadingDiscount: isLoadingDiscount,
            onRequestDiscount: _requestOrderDiscount,
            onClearDiscount: () =>
                setState(() => personalDiscount = null),
            onBonusAmountChanged: () => setState(() {}),
          ),

          const SizedBox(height: 14),

          // ── Payment method toggle ──────────────────────────────────────────
          PaymentMethodToggle(
            selectedMethod: paymentMethod,
            onMethodChanged: (method) => setState(() {
              paymentMethod = method;
              if (method == PaymentMethod.cash) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  cashFocus.requestFocus();
                });
              } else {
                cashCtr.clear();
              }
            }),
          ),

          // ── Cash section ───────────────────────────────────────────────────
          if (paymentMethod == PaymentMethod.cash && !showPaymentSuccess)
            CashChangeSection(
              cashController: cashCtr,
              cashFocusNode: cashFocus,
              finalTotal: finalTotal,
              onChanged: () => setState(() {}),
              showBonusTransfer: true,
              hasLoyalty: widget.loyalty != null,
              transferChangeToBonus: transferChangeToBonus,
              onTransferChangeToBonusChanged: (v) =>
                  setState(() => transferChangeToBonus = v),
              bonusTransferController: bonusTransferCtr,
              bonusTransferFocusNode: bonusTransferFocus,
              onBonusTransferAmountChanged: () => setState(() {}),
              onFocusPhone: widget.onFocusPhone,
            ),

          const SizedBox(height: 10),

          // ── Pay / success button ───────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: showPaymentSuccess
                ? _orderPaySuccessWidget()
                : _orderPayButtonWidget(),
          ),

          const SizedBox(height: 8),

          // ── Secondary actions ──────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _OrderSmallButton(
                    icon: Icons.inventory_2_outlined,
                    label: 'Резерв F6',
                    onTap: () {}),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _OrderSmallButton(
                    icon: Icons.smart_toy_outlined,
                    label: 'Привезти чек',
                    onTap: () {}),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderPaySuccessWidget() => Container(
        key: const ValueKey('order_pay_success'),
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 19),
            SizedBox(width: 7),
            Text(
              'Оплата проведена!',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _orderPayButtonWidget() {
    // A8: поки фіскального конвеєра для замовлень немає, кнопка неактивна на
    // вигляд, а натискання пояснює причину (нічого не «клацає» мовчки).
    final enabled = _orderPaymentAllowed;
    return GestureDetector(
      key: const ValueKey('order_pay_btn'),
      onTap: _processOrderPayment,
      child: Container(
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF1E7DC8) : const Color(0xFF94A3B8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(enabled ? Icons.payment_rounded : Icons.lock_outline_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 7),
            Text(
              enabled ? 'Провести оплату' : 'Оплата недоступна',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _OrderSmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _OrderSmallButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isEnabled
              ? const Color(0xFFE8F3FB)
              : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isEnabled
                ? const Color(0xFF1E7DC8).withValues(alpha: 0.2)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isEnabled
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFFD1D5DB),
                size: 16),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                  color: isEnabled
                      ? const Color(0xFF1E7DC8)
                      : const Color(0xFFD1D5DB),
                  fontSize: 11,
                )),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

// ── Order list tile ─────────────────────────────────────────────────────────

class _OrderListTile extends StatefulWidget {
  final InternetOrder order;
  final OrderExtras extras;
  final bool checked;

  /// null — замовлення не можна об'єднувати (чекбокса немає).
  final VoidCallback? onCheck;
  final VoidCallback? onOpenMessages;
  final bool highlighted;
  final VoidCallback onTap;
  const _OrderListTile({
    required this.order,
    this.extras = OrderExtras.empty,
    this.checked = false,
    this.onCheck,
    this.onOpenMessages,
    this.highlighted = false,
    required this.onTap,
  });

  @override
  State<_OrderListTile> createState() => _OrderListTileState();
}

class _OrderListTileState extends State<_OrderListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isHighlighted = widget.highlighted;
    // Склад замовлення: одна позиція — повна назва, кілька — перші 15
    // символів кожної через кому (ТЗ §3).
    final realItems = order.items.where((i) => !i.isServiceLine).toList();
    final itemsSummary = realItems.length == 1
        ? realItems.first.name
        : orderItemsPreview(order);
    final extras = widget.extras;
    final t = order.dateTime;
    final dateLabel =
        '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isHighlighted
                ? const Color(0xFFEEF2FF)
                : _hovered
                    ? const Color(0xFFF8FAFF)
                    : Colors.transparent,
            border: isHighlighted
                ? const Border(
                    left: BorderSide(color: Color(0xFF1E7DC8), width: 3))
                : null,
          ),
          child: Row(
            children: [
              // «Об'єднати» — відпуск кількох замовлень одним чеком
              if (widget.onCheck != null) ...[
                Tooltip(
                  message: 'Позначити для об\'єднання в один чек',
                  child: MergeCheckbox(
                    value: widget.checked,
                    onChanged: widget.onCheck,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Status dot
              _StatusDot(status: order.status, isUrgent: order.isUrgent),
              const SizedBox(width: 10),
              // Reserve number + locker cell + urgent badge + product names
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 3,
                      children: [
                        Text(
                          order.reserveNumber,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1C1C2E),
                          ),
                        ),
                        if (order.isUrgent &&
                            order.status != OrderStatus.collected &&
                            order.status != OrderStatus.paidOnline &&
                            order.status != OrderStatus.dispensed) ...[
                          // Reason badge: Лікомат or Glovo
                          if (order.isLockerOrder) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F7FF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: const Color(0xFFBFDBFE)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline_rounded,
                                      size: 9, color: Color(0xFF1E7DC8)),
                                  SizedBox(width: 3),
                                  Text(
                                    'Лікомат',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E7DC8),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Термінове badge
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0xFFFECACA)),
                            ),
                            child: const Text(
                              'Термінове',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFDC2626),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                        if (order.lockerCell != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F7FF),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0xFFBFDBFE)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.inventory_2_outlined,
                                    size: 10, color: Color(0xFF1E7DC8)),
                                const SizedBox(width: 3),
                                Text(
                                  '${order.lockerCell}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E7DC8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // ── Stale order badge (3+ days) ──
                        if (order.isStale) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0xFFFECACA)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    size: 10, color: Color(0xFFDC2626)),
                                const SizedBox(width: 2),
                                Text(
                                  order.staleLabel,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFDC2626),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // ── Glovo: окрема позначка завжди (ТЗ §8) ──
                        if (order.type == OrderType.glovo) ...[
                          const SizedBox(width: 6),
                          const OrderPill(
                            icon: Icons.delivery_dining_rounded,
                            text: 'Glovo',
                            color: Color(0xFFEA580C),
                            background: Color(0xFFFFF7ED),
                            border: Color(0xFFFED7AA),
                          ),
                        ],
                        if (order.isMerged) ...[
                          const SizedBox(width: 6),
                          OrderPill(
                            text: 'Об\'єднано ${order.mergedFrom.length}',
                            color: const Color(0xFF1E7DC8),
                            background: const Color(0xFFF0F7FF),
                            border: const Color(0xFFBFDBFE),
                          ),
                        ],
                        // Плашка «Час спливає/вийшов» і галочка
                        // автопідтвердження (мок) прибрані (24.09).
                        if (extras.hasMessages) ...[
                          const SizedBox(width: 6),
                          MessageEnvelope(
                            unread: extras.hasUnread,
                            onTap: widget.onOpenMessages,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Date-time + source + customer name + items summary
                    Text(
                      [
                        dateLabel,
                        order.typeLabel,
                        if (order.customerName != null) order.customerName!,
                        itemsSummary,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Price
              Text(
                '${order.total.asMoney} ₴',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 6),
              if (isHighlighted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E7DC8),
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
                )
              else
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Color(0xFFD1D5DB)),
            ],
          ),
        ),
      ),
    );
  }

}

// ── Status dot ──────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final OrderStatus status;
  final bool isUrgent;
  const _StatusDot({required this.status, this.isUrgent = false});

  @override
  Widget build(BuildContext context) {
    // Urgent + not yet collected/paid/dispensed → red filled dot
    final isActiveUrgent = isUrgent &&
        status != OrderStatus.collected &&
        status != OrderStatus.paidOnline &&
        status != OrderStatus.dispensed;

    final color = isActiveUrgent
        ? const Color(0xFFEF4444)
        : switch (status) {
            OrderStatus.newOrder => const Color(0xFF3B82F6),     // blue
            OrderStatus.inProgress => const Color(0xFFF59E0B),   // amber
            OrderStatus.collected => const Color(0xFF22C55E),    // green
            OrderStatus.atWork => const Color(0xFF8B5CF6),       // purple
            OrderStatus.paidOnline => const Color(0xFF06B6D4),   // cyan
            OrderStatus.dispensed => const Color(0xFF6B7280),    // gray (legacy)
            OrderStatus.refused => const Color(0xFFEF4444),      // red (legacy)
            OrderStatus.customerRefusal => const Color(0xFFEF4444),
            OrderStatus.pharmacyRefusal => const Color(0xFFD97706),
          };

    final isFilled = isActiveUrgent ||
        status == OrderStatus.collected ||
        status == OrderStatus.paidOnline ||
        status == OrderStatus.dispensed;

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: isFilled ? color : Colors.transparent,
        border: isFilled ? null : Border.all(color: color, width: 1.5),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ── Status badge (for detail header) ────────────────────────────────────────

class _OrderStatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _OrderStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, bgColor) = switch (status) {
      OrderStatus.newOrder => (
          const Color(0xFF3B82F6),
          const Color(0xFFEFF6FF)
        ),
      OrderStatus.inProgress => (
          const Color(0xFFF59E0B),
          const Color(0xFFFFFBEB)
        ),
      OrderStatus.collected => (
          const Color(0xFF22C55E),
          const Color(0xFFF0FDF4)
        ),
      OrderStatus.atWork => (
          const Color(0xFF8B5CF6),
          const Color(0xFFF5F3FF)
        ),
      OrderStatus.paidOnline => (
          const Color(0xFF06B6D4),
          const Color(0xFFECFEFF)
        ),
      OrderStatus.dispensed => (
          const Color(0xFF6B7280),
          const Color(0xFFF9FAFB)
        ),
      OrderStatus.refused => (
          const Color(0xFFEF4444),
          const Color(0xFFFEF2F2)
        ),
      OrderStatus.customerRefusal => (
          const Color(0xFFEF4444),
          const Color(0xFFFEF2F2)
        ),
      OrderStatus.pharmacyRefusal => (
          const Color(0xFFD97706),
          const Color(0xFFFFFBEB)
        ),
    };

    final label = switch (status) {
      OrderStatus.newOrder => 'Нове',
      OrderStatus.inProgress => 'В обробці',
      OrderStatus.collected => 'Зібране',
      OrderStatus.atWork => 'В роботі',
      OrderStatus.paidOnline => 'Відпущено',
      OrderStatus.dispensed => 'Видане',
      OrderStatus.refused => 'Розформоване',
      OrderStatus.customerRefusal => 'Відмова клієнта',
      OrderStatus.pharmacyRefusal => 'Відмова аптеки',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Order item row (mirrors CartItemWidget layout) ──────────────────────────

class _OrderItemRow extends StatelessWidget {
  final OrderItem item;

  /// Whether this item has been scanned (barcode confirmed).
  final bool isScanned;

  /// Whether scanning is available (order not yet collected).
  final bool canScan;

  /// Callback when the pharmacist taps the price (simulates barcode scan).
  final VoidCallback? onScan;

  const _OrderItemRow({
    required this.item,
    this.isScanned = false,
    this.canScan = false,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final isDiscount = item.total < 0;
    final qtyStr = item.quantity % 1 == 0
        ? item.quantity.toInt().toString()
        : item.quantity.toString().replaceAll('.', ',');
    // Код · виробник · термін із замовлення (ТЗ §4). Термін із замовлення
    // показуємо, лише якщо збагачення не дало точнішого терміну партії.
    final metaLine = isDiscount
        ? ''
        : [
            if (item.sku.isNotEmpty) 'Код ${item.sku}',
            if ((item.manufacturer ?? '').isNotEmpty) item.manufacturer!,
            if (item.expiryDate != null && item.enrichedExpiryDate == null)
              'до ${item.expiryDate}',
          ].join(' · ');

    // INVERTED: unscanned = blue (attention needed), scanned = green (done)
    final Color bgColor;
    final Color borderColor;
    if (isDiscount) {
      bgColor = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFDE68A);
    } else if (isScanned) {
      bgColor = const Color(0xFFF0FDF4);   // green — done
      borderColor = const Color(0xFFBBF7D0);
    } else {
      bgColor = const Color(0xFFEFF6FF);   // blue — needs scanning
      borderColor = const Color(0xFFBFDBFE);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Drug image thumbnail (or fallback icon) — tap opens popover
          Builder(
            builder: (thumbCtx) => GestureDetector(
              onTap: item.isEnriched
                  ? () => _showImagePopover(thumbCtx)
                  : null,
              child: MouseRegion(
                cursor: item.isEnriched
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDiscount
                        ? const Color(0xFFFEF3C7)
                        : isScanned
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDiscount
                          ? const Color(0xFFFDE68A)
                          : isScanned
                              ? const Color(0xFFBBF7D0)
                              : const Color(0xFFBFDBFE),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: item.enrichedImageUrl != null
                      ? Image.network(
                          item.enrichedImageUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 96,
                          errorBuilder: (_, __, ___) => _fallbackIcon(isDiscount, isScanned),
                        )
                      : _fallbackIcon(isDiscount, isScanned),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name, enriched info, and price × qty
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 420;
                final hasEnriched = item.enrichedStorageLocation != null ||
                    item.enrichedSeries != null ||
                    item.enrichedExpiryDate != null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wide mode: name + enriched info side by side
                    if (isWide && hasEnriched)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              item.name,
                              style: TextStyle(
                                color: isDiscount
                                    ? const Color(0xFFB45309)
                                    : isScanned
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFF1C1C2E),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (item.enrichedStorageLocation != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on_outlined,
                                          size: 13, color: Color(0xFF1E7DC8)),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          item.enrichedStorageLocation!,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF1C1C2E),
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                if (item.enrichedSeries != null ||
                                    item.enrichedExpiryDate != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (item.enrichedSeries != null) 'Серія: ${item.enrichedSeries}',
                                      if (item.enrichedExpiryDate != null) 'до ${item.enrichedExpiryDate}',
                                    ].join(' \u2022 '),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      // Narrow mode: original stacked layout
                      Text(
                        item.name,
                        style: TextStyle(
                          color: isDiscount
                              ? const Color(0xFFB45309)
                              : isScanned
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFF1C1C2E),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // ── Storage location ──
                      if (item.enrichedStorageLocation != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 11, color: Color(0xFF6B7280)),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                item.enrichedStorageLocation!,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // ── Series & expiry ──
                      if (item.enrichedSeries != null || item.enrichedExpiryDate != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          [
                            if (item.enrichedSeries != null) 'Серія: ${item.enrichedSeries}',
                            if (item.enrichedExpiryDate != null) 'до ${item.enrichedExpiryDate}',
                          ].join(' \u2022 '),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6B7280),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                    if (metaLine.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        metaLine,
                        style: const TextStyle(
                            fontSize: 10.5, color: Color(0xFF6B7280)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if ((item.refusalReason ?? '').isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        'Причина відмови: ${item.refusalReason}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      '${item.price.asMoney} ₴ × $qtyStr'
                      '${item.fraction != null ? ' · дріб ${item.fraction}' : ''}',
                      style: TextStyle(
                        color: isScanned
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFF6B7280),
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          // Total price — tappable to simulate scan
          GestureDetector(
            onTap: (canScan && !isScanned && !isDiscount) ? onScan : null,
            child: MouseRegion(
              cursor: (canScan && !isScanned && !isDiscount)
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: (canScan && !isScanned && !isDiscount)
                    ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: const Color(0xFF1E7DC8)
                                .withValues(alpha: 0.3),
                            style: BorderStyle.solid,
                          ),
                        ),
                      )
                    : null,
                child: Text(
                  '${item.total.asMoney} ₴',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: isDiscount
                        ? const Color(0xFFB45309)
                        : isScanned
                            ? const Color(0xFF15803D)
                            : const Color(0xFF1C1C2E),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackIcon(bool isDiscount, bool isScanned) {
    return Icon(
      isDiscount
          ? Icons.discount_outlined
          : isScanned
              ? Icons.check_box_rounded
              : Icons.medication_rounded,
      color: isDiscount
          ? const Color(0xFFB45309)
          : isScanned
              ? const Color(0xFF16A34A)
              : const Color(0xFF1E7DC8),
      size: 17,
    );
  }

  void _showImagePopover(BuildContext context) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset position = box.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    // Position popover to the right of the thumbnail; if it overflows, place to the left
    final popoverWidth = 320.0;
    final double left;
    if (position.dx + box.size.width + 8 + popoverWidth < screenSize.width) {
      left = position.dx + box.size.width + 8;
    } else {
      left = position.dx - popoverWidth - 8;
    }
    final top = (position.dy - 40).clamp(8.0, screenSize.height - 400);

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    width: popoverWidth,
                    constraints: const BoxConstraints(maxHeight: 380),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1C1C2E),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Flexible(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: item.enrichedImageUrl != null
                                ? Image.network(
                                    item.enrichedImageUrl!,
                                    fit: BoxFit.contain,
                                    cacheWidth: 512,
                                    errorBuilder: (_, __, ___) =>
                                        _noImagePlaceholder(),
                                  )
                                : _noImagePlaceholder(),
                          ),
                        ),
                        if (item.enrichedSeries != null ||
                            item.enrichedExpiryDate != null ||
                            item.enrichedStorageLocation != null) ...[
                          const SizedBox(height: 10),
                          if (item.enrichedStorageLocation != null)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.location_on_outlined,
                                    size: 14, color: Color(0xFF1E7DC8)),
                                const SizedBox(width: 4),
                                Text(
                                  item.enrichedStorageLocation!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF1C1C2E),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          if (item.enrichedSeries != null ||
                              item.enrichedExpiryDate != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (item.enrichedSeries != null) 'Серія: ${item.enrichedSeries}',
                                if (item.enrichedExpiryDate != null) 'до ${item.enrichedExpiryDate}',
                              ].join(' \u2022 '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _noImagePlaceholder() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 48, color: Color(0xFFD1D5DB)),
            SizedBox(height: 8),
            Text(
              'Зображення недоступне',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Merge icon — two intersecting circles (Mastercard-style)
// ─────────────────────────────────────────────────────────────────────────────

class _MergeIcon extends StatelessWidget {
  final double size;

  const _MergeIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(
          painter: _MergeIconPainter(color: Color(0xFF1C1C2E))),
    );
  }
}

class _MergeIconPainter extends CustomPainter {
  final Color color;
  const _MergeIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height * 0.38;
    final overlap = size.width * 0.15;
    final cy = size.height / 2;
    final cx = size.width / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.12;

    canvas.drawCircle(Offset(cx - overlap, cy), r, paint);
    canvas.drawCircle(Offset(cx + overlap, cy), r, paint);
  }

  @override
  bool shouldRepaint(covariant _MergeIconPainter old) => old.color != color;
}


