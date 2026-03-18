# Pharmacy POS — План реінжинірингу

> **Дата створення:** 2026-03-14
> **Статус:** Очікує завершення UI нових модулів
> **Автор аудиту:** Claude (архітектурний аналіз кодової бази)
> **Цільова платформа:** Android (десктопне обладнання: монітор, клавіатура, миша, USB-сканер, USB/мережевий принтер)

---

## Зміст

1. [Контекст і поточний стан](#1-контекст-і-поточний-стан)
2. [Аудит: що виявлено](#2-аудит-що-виявлено)
3. [Послідовність: чому UI першим](#3-послідовність-чому-ui-першим)
4. [Правила для нових модулів](#4-правила-для-нових-модулів)
5. [Фаза 0: Інфраструктура](#5-фаза-0-інфраструктура)
6. [Фаза 1: Data Layer](#6-фаза-1-data-layer)
7. [Фаза 2: Інтеграція з реальним API](#7-фаза-2-інтеграція-з-реальним-api)
8. [Фаза 3: Payment Hardening](#8-фаза-3-payment-hardening)
9. [Фаза 4: Продуктивність](#9-фаза-4-продуктивність)
10. [Фаза 5: Хардинінг](#10-фаза-5-хардинінг)
11. [Залежності від бекенд-команди](#11-залежності-від-бекенд-команди)
12. [Зведена таблиця](#12-зведена-таблиця)
13. [Що свідомо НЕ включено](#13-що-свідомо-не-включено)
14. [Чеклист перед стартом](#14-чеклист-перед-стартом)

---

## 1. Контекст і поточний стан

### Що це

Десктопний POS-додаток для аптечної мережі. Flutter/Dart, Android OS на стаціонарних комп'ютерах з клавіатурою, мишею, USB-сканером штрихкодів, USB/мережевим принтером.

### Бекенд

Caché InterSystems (CSP REST). GET-only API. Windows-1251 кодування. Сервер: `10.90.77.66:57772`.

### Кодова база (станом на 2026-03-14)

```
Загалом:   20 479 рядків Dart, 55 файлів
Залежності: cupertino_icons, http (^1.2.0) — тільки 2 пакети
Тести:     <1% покриття (1 smoke-test, 1 ручний API-тест)

lib/
├── main.dart                          56 рядків
├── screens/
│   └── pos_screen.dart              1 819 рядків  ← головний екран
├── models/               9 файлів     491 рядок
├── services/              4 файли     682 рядки
├── mixins/                2 файли     122 рядки
├── utils/                 2 файли     111 рядків
├── data/                  7 файлів  2 871 рядок   ← mock-дані
└── widgets/              29 файлів 13 568 рядків   ← основний обсяг
```

Найбільші файли:

| Файл | Рядки | Роль |
|------|-------|------|
| orders_panel.dart | 2 040 | Інтернет-замовлення |
| pos_screen.dart | 1 819 | Головний POS-екран |
| expenses_panel.dart | 1 429 | Витрати / касові операції |
| mock_drugs.dart | 1 425 | Mock-дані препаратів |
| cart_panel.dart | 1 356 | Кошик + checkout |
| out_of_stock_panel.dart | 1 250 | Панель відсутнього товару |
| drug_detail_panel.dart | 1 185 | Деталі препарату |

### Що працює на mock-даних

- Пошук препаратів (fuzzy + серверний)
- Кошик з дробовими кількостями (блістери)
- ЄДК (фармацевтична заміна) — 11 хардкодів
- ТПК (турбота про клієнта) — 2 хардкоди
- Checkout flow (card / cash / mixed) — тільки UI
- Списання бонусів (ЛАЙК) — є реальний API-виклик
- Інтернет-замовлення — mock
- Касові витрати — mock
- Зміна фармацевта — є реальний API-виклик

### Що НЕ працює (UI-заглушки)

- Оплата не відправляється на сервер
- Фіскальний чек не генерується
- Продажі не логуються
- Кошик зникає при перезавантаженні
- EDK/ТПК не динамічні (хардкод)

---

## 2. Аудит: що виявлено

### Критичні проблеми

| # | Проблема | Де | Вплив |
|---|---------|-----|-------|
| 1 | **Оплата — UI-only.** `_processPayment()` очищає кошик і додає суму до `_totalEarned` в пам'яті. Жодного запису на сервер. | pos_screen.dart:1080 | Продажі не фіксуються |
| 2 | **Бонуси без атомарності.** `BonusService.writeOff()` виконується окремо від продажу. Якщо списання пройшло, а продаж ні — гроші втрачені. | cart_panel.dart:235 | Фінансові втрати |
| 3 | **Паролі plain-text.** AuthService передає пароль як GET-параметр без хешування. | auth_service.dart | Безпека |
| 4 | **Хардкод IP сервера.** `10.90.77.66:57772` в коді. Зміна = перезбірка. | api_config.dart:3 | DevOps |
| 5 | **0 retry при збої мережі.** Один таймаут 10с → мовчазна помилка. | cache_api_client.dart | Каса "зависає" |
| 6 | **<1% тестів.** Регресія при будь-якій зміні. | test/ | Якість |

### Архітектурні проблеми

| # | Проблема | Де | Вплив |
|---|---------|-----|-------|
| 7 | **CartItem мутабельний.** Поля `quantity`, `fractionalQty` змінюються напряму. Flutter може не побачити зміну. | models/cart_item.dart | Баги UI |
| 8 | **Немає fromJson/toJson.** Моделі не серіалізуються. Не можна зберегти кошик, не можна парсити реальне API. | models/*.dart | Блокер інтеграції |
| 9 | **Немає equality (== / hashCode).** Два однакових Drug — не рівні. Set/Map працюють некоректно. | models/*.dart | Баги логіки |
| 10 | **UI зав'язаний на mockDrugs.** 10+ місць в pos_screen.dart напряму імпортують mock-масив. | pos_screen.dart | Складна міграція |
| 11 | **Немає Repository pattern.** Сервіси викликаються напряму з UI. Немає абстракції між даними і відображенням. | screens/, widgets/ | Тісна зв'язаність |
| 12 | **Немає кешування.** Кожен пошук = запит на сервер. | services/ | Навантаження |
| 13 | **Немає логування.** Помилки ковтаються мовчки (`catch (_) { return []; }`). | services/*.dart | Неможливо дебажити |

### Що зроблено добре

- Keyboard UX (F2/F5/F10/Esc cascade, стрілки, Ctrl+digit) — повноцінний
- Win-1251 підтримка — ретельно реалізована
- Mock/live перемикач є (ApiConfig.useMock)
- Мixin pattern для shared логіки (CheckoutMixin, EdkStateMixin)
- Fuzzy search з толерантністю до помилок
- Рефакторинг Фаз 1–3 — чистий поділ на віджети

### Gap між mock і реальним API

Drug модель має ~29 полів. Реальне API повертає ~8:

| Є в API | Немає в API (mock-only) |
|---------|------------------------|
| name, manufacturer | dosageForm, inn, dosage |
| price, stock | storageConditions, usageInfo |
| shelf/location | imageUrl, intakeWarning |
| | pharmacistBonus, unitsPerPackage |
| | expiryDate, barcode, series |
| | analogueGroup, availabilityStatus |

**21 поле — mock-only.** Потрібно або розширювати серверні методи, або прийняти дефолтні значення.

---

## 3. Послідовність: чому UI першим

**Рішення:** спершу дороби UI нових модулів (соцпроекти, реімбурсація, повідомлення, аналітика), потім реінжиніринг.

**Причини:**

1. **Реімбурсація змінить payment flow.** Частину суми платить держава — це впливає на TransactionService, checkout_mixin, структуру транзакції. Якщо зробити реінжиніринг зараз, доведеться переробляти.

2. **Повідомлення можуть вимагати WebSocket / push.** Це інший тип з'єднання. Вплине на мережевий шар.

3. **Аналітика визначить що логувати.** Поки не зрозуміло які метрики — рано проектувати logger.

4. **Ти в потоці.** Зупинка на 6 тижнів реінжинірингу = втрата контексту.

---

## 4. Правила для нових модулів

> Ці правила забезпечать що нові модулі НЕ ускладнять майбутній реінжиніринг.

### 4.1 Структура файлів

```
lib/models/
├── social_project.dart          ← нова модель
├── reimbursement.dart           ← нова модель
└── notification_item.dart       ← нова модель

lib/data/
├── mock_social_projects.dart    ← mock-дані
├── mock_reimbursements.dart
└── mock_notifications.dart

lib/widgets/
├── social_projects_panel.dart   ← основний StatefulWidget
├── reimbursement_panel.dart
├── notifications_panel.dart
├── analytics_panel.dart
├── social/                      ← якщо > 500 рядків — виносити
│   ├── social_project_card.dart
│   └── social_discount_dialog.dart
└── reimbursement/
    └── reimbursement_calc_dialog.dart
```

### 4.2 Моделі — одразу правильно

```dart
class Reimbursement {
  final String id;
  final String programName;
  final double stateAmount;      // скільки платить держава
  final double patientAmount;    // скільки платить клієнт
  final String innCode;          // МНН препарату
  // ...
  const Reimbursement({required this.id, ...});
}
```

- Всі поля `final`
- Конструктор `const`
- Не додавати fromJson/toJson поки — це буде в реінжинірингу

### 4.3 Не лізь в pos_screen.dart більше ніж на ~20 рядків

Нові панелі додаються в `_buildRightPanel()` через існуючий `AnimatedSwitcher`:
- Один bool-прапорець (`_socialProjectsOpen`, `_reimbursementOpen`, etc.)
- Один case в AnimatedSwitcher
- Вся логіка — всередині нової панелі

### 4.4 Якщо модуль впливає на checkout — залиш TODO

```dart
// TODO: [REENGINEERING] реімбурсація впливає на розрахунок фінальної суми
// Потрібно: stateAmount вираховується з finalTotal, patientAmount — окремий рядок
// Див. docs/reengineering_plan.md, Фаза 3
```

Не рефактори checkout_mixin зараз. Запиши що саме зміниться.

### 4.5 Mock-дані — окремо, не змішувати з існуючими

Не додавай нові поля в `mockDrugs` або `mockOrders`. Нові модулі — нові mock-файли.

---

## 5. Фаза 0: Інфраструктура

> **Тривалість:** 4–5 днів
> **Залежності від бекенду:** немає
> **Ризик зламати існуючий UI:** нульовий

### 0.1 Конфігурація середовищ (0.5 дня)

**Проблема:** IP сервера і useMock — хардкод у коді.

**Рішення:**

```
lib/services/api_config.dart (переписати)
├── Environment enum: dev | staging | prod
├── Значення з --dart-define:
│   flutter run --dart-define=ENV=dev
│   flutter run --dart-define=ENV=prod
│   flutter run --dart-define=SERVER_URL=http://10.90.77.66:57772
├── Дефолти:
│   dev   → useMock=true,  url=localhost
│   staging → useMock=false, url=тестовий сервер
│   prod  → useMock=false, url=бойовий сервер
└── Таймаути: dev=3с, staging=6с, prod=6с
```

**Критерій приймання:** Один APK → три середовища через параметр збірки.

### 0.2 Логування (1 день)

**Проблема:** `catch (_) { return []; }` — помилки зникають безслідно.

**Рішення:**

```
lib/services/logger.dart (новий)
├── Рівні: debug, info, warning, error
├── Формат: [2026-03-14 09:15:32] [ERROR] [DrugService] Таймаут пошуку "парацетамол": 6с
├── Dev: console output (debugPrint)
├── Prod: файл + підготовка до Sentry/Crashlytics
└── Обгортка:
    try { ... }
    catch (e) {
      AppLogger.error('DrugService', 'searchByName failed', e);
      return [];
    }
```

**Де застосувати:** всі catch-блоки в services/ (4 файли, ~15 місць).

**Критерій приймання:** При збої API — в консолі видно ЩО впало, ЧОМУ, КОЛИ.

### 0.3 Мережева стійкість (1.5 дня)

**Проблема:** Таймаут 10с → тиша. Аптеки мають нестабільний VPN/Wi-Fi.

**Рішення:**

```
lib/services/resilient_api_client.dart (обгортка навколо CacheApiClient)
├── Retry: 3 спроби, exponential backoff (1с → 2с → 4с)
├── Circuit breaker:
│   ├── Після 5 помилок підряд → стан "offline"
│   ├── Показати banner "Немає зв'язку з сервером"
│   ├── Пінг кожні 10с
│   └── Автовідновлення при успішному пінгу
├── Таймаут: 6с (замість 10с)
├── Callback: onConnectionStatusChanged(bool isOnline)
│   └── UI підписується і показує/ховає offline-banner
└── Для критичних операцій (оплата, бонуси):
    ├── 5 спроб замість 3
    └── Більший таймаут: 10с
```

**Критерій приймання:** Відключити сервер → banner "Немає зв'язку", додаток не зависає. Увімкнути → автовідновлення за ≤15с.

### 0.4 Тести на гроші (1–1.5 дня)

**Проблема:** 0 тестів на фінансові розрахунки.

**Що тестуємо (мінімум 20 тестів):**

```
test/
├── models/
│   └── cart_item_test.dart
│       ├── total — ціна × кількість
│       ├── fractional total — (ціна / unitsPerPackage) × fractionalQty
│       ├── displayQty — "3/10" для дробового, "5" для цілого
│       └── edge cases — qty=0, fractionalQty=0, unitsPerPackage=null
│
├── mixins/
│   └── checkout_mixin_test.dart
│       ├── baseTotal — сума всіх CartItem.total
│       ├── personalDiscount — відсоток від baseTotal
│       ├── effectiveBonusAmount — не більше балансу, не більше залишку
│       ├── finalTotal — base − discount − bonus (ніколи < 0)
│       ├── change calculation — cash − finalTotal
│       └── edge cases — порожній кошик, нуль бонусів, mixed payment
│
├── services/
│   ├── drug_service_test.dart
│   │   ├── searchByName — парсинг відповіді, порожній результат
│   │   ├── getStockAndPrices — парсинг батчів, дробові ціни
│   │   └── edge cases — невалідний JSON, timeout, порожня відповідь
│   │
│   └── bonus_service_test.dart
│       ├── writeOff — успіх, помилка, timeout
│       └── cancelWriteOff — успіх, помилка
│
└── utils/
    └── fuzzy_search_test.dart
        ├── exact match — score = 1.0
        ├── 1-2 помилки — score > 0
        ├── повний mismatch — score = 0
        └── drugMatchScore — max(name, manufacturer)
```

**Критерій приймання:** `flutter test` — всі зелені. Покриття ≥ 80% на checkout_mixin і cart_item.

### 0.5 Android build verification (0.5 дня)

**Проблема:** Проект збирався як web. Android-папка існує, але не тестувалась.

**Дії:**
```
1. flutter build apk --debug
2. Встановити на цільову машину (Android OS + монітор + клавіатура)
3. Прогнати всі хоткеї: F2, F5, F10, Esc, Ctrl+digit, стрілки, Tab
4. Перевірити USB-сканер (емуляція клавіатури)
5. Зафіксувати будь-які відмінності keyCode
```

**Критерій приймання:** APK запускається, всі хоткеї працюють, сканер вводить штрихкод.

---

## 6. Фаза 1: Data Layer

> **Тривалість:** 6–7 днів
> **Залежності від бекенду:** немає
> **Ризик:** середній (торкається 10+ місць в UI), покривається тестами з Фази 0

### 1.1 Імутабельність CartItem (0.5 дня)

**Проблема:** `cartItem.quantity = 5` — пряма мутація. Flutter може не побачити зміну.

**Рішення:**

```dart
// БУЛО:
class CartItem {
  int quantity;          // мутабельне
  int? fractionalQty;    // мутабельне
}
// Використання: cartItem.quantity = newQty;

// СТАЛО:
class CartItem {
  final int quantity;          // final
  final int? fractionalQty;    // final

  CartItem copyWith({int? quantity, int? fractionalQty}) => CartItem(
    drug: drug,
    quantity: quantity ?? this.quantity,
    fractionalQty: fractionalQty,
  );
}
// Використання: cart[i] = cart[i].copyWith(quantity: newQty);
```

**Де міняти:** pos_screen.dart — всі місця де `cartItem.quantity = ...` або `cartItem.fractionalQty = ...`.

**Критерій приймання:** Код не компілюється якщо спробувати змінити поле напряму.

### 1.2 Серіалізація моделей (1.5 дня)

**Проблема:** Моделі не мають fromJson/toJson. Не можна парсити API, не можна зберегти кошик.

**Рішення:**

Додати `fromJson()`, `toJson()`, `operator==`, `hashCode` до:
- Drug
- CartItem
- InternetOrder + OrderItem
- CashExpense + ExpenseItem
- Нові моделі (SocialProject, Reimbursement, etc. — якщо вже створені)

**Підхід:** ручний fromJson/toJson (НЕ json_serializable). Причини:
- Проект невеликий (6–10 моделей)
- Codegen додає складність збірки
- Ручний парсинг — прозоріший для win-1251 відповідей Caché
- Легше дебажити

**Для equality:** підключити пакет `equatable` або написати вручну.

```dart
class Drug extends Equatable {
  // ...
  @override
  List<Object?> get props => [id, name, manufacturer, price, ...];
}
```

**Критерій приймання:** Тест `Drug.fromJson(drug.toJson()) == drug` проходить для всіх моделей.

### 1.3 Repository Pattern — ключова зміна (3 дні)

**Проблема:** `pos_screen.dart` напряму імпортує `mockDrugs` (10+ місць). Перехід на реальний API = міняти кожне місце.

**Рішення:**

```
lib/repositories/
├── drug_repository.dart (abstract interface)
│   ├── Future<List<Drug>> search(String query)
│   ├── Future<Drug?> getById(String id)
│   ├── Future<Drug?> getByBarcode(String barcode)
│   ├── Future<List<Drug>> getAnalogues(String analogueGroup)
│   └── Future<List<EdkOffer>> getEdkOffers(String drugId)
│
├── mock_drug_repository.dart
│   └── Використовує mockDrugs + fuzzySearch + хардкодовані EDK
│
├── api_drug_repository.dart (реалізується у Фазі 2)
│   └── DrugService + кеш + маплення → Drug
│
├── order_repository.dart (abstract)
│   ├── Future<List<InternetOrder>> getOrders({OrderStatus? status})
│   ├── Future<InternetOrder?> getById(String id)
│   └── Future<void> updateStatus(String id, OrderStatus status)
│
├── mock_order_repository.dart
│   └── Використовує mockOrders
│
├── expense_repository.dart (abstract)
│   ├── Future<List<CashExpense>> getExpenses({DateTimeRange? range})
│   └── Future<void> createExpense(CashExpense expense)
│
└── mock_expense_repository.dart
    └── Використовує mockExpenses
```

**Як це змінює UI (pos_screen.dart):**

```dart
// БУЛО:
import '../data/mock_drugs.dart';
List<Drug> _searchResults = mockDrugs;
for (final drug in mockDrugs) { score = drugMatchScore(query, drug); }

// СТАЛО:
final DrugRepository _drugRepo;  // інжектується через конструктор
List<Drug> _searchResults = [];   // або await _drugRepo.search('')
_searchResults = await _drugRepo.search(query);
```

**Важливо:** MockDrugRepository зберігає ПОВНІСТЮ поточну поведінку (fuzzy search, EDK хардкоди, фільтрація). Зміна ТІЛЬКИ в тому, звідки UI бере дані — через інтерфейс, а не напряму.

**Критерій приймання:** `mockDrugs` не імпортується жодним файлом у screens/ або widgets/. Все через repository.

### 1.4 Інжекція залежностей (0.5 дня)

Не потрібен Provider/Riverpod. Достатньо передати repository через конструктор:

```dart
// main.dart
final drugRepo = MockDrugRepository();  // або ApiDrugRepository()
runApp(PharmacyApp(drugRepository: drugRepo));

// pos_screen.dart
class PosScreen extends StatefulWidget {
  final DrugRepository drugRepository;
  // ...
}
```

Пізніше, якщо буде потреба в глобальному стані (auth session, поточний фармацевт) — додати `InheritedWidget` або мінімальний Provider. Але НЕ зараз.

### 1.5 Тести на repository (1 день)

```
test/repositories/
├── mock_drug_repository_test.dart
│   ├── search — fuzzy matching працює через repository
│   ├── getById — повертає правильний Drug
│   ├── getByBarcode — знаходить за штрихкодом
│   ├── getEdkOffers — повертає заміни для donor drug
│   └── getAnalogues — повертає аналоги з тієї ж групи
│
├── mock_order_repository_test.dart
│   ├── getOrders — фільтрація по статусу
│   └── updateStatus — статус змінюється
│
└── mock_expense_repository_test.dart
    └── getExpenses — фільтрація по даті
```

---

## 7. Фаза 2: Інтеграція з реальним API

> **Тривалість:** 8–10 днів
> **Залежності від бекенду:** ТАК (потрібні нові серверні методи)
> **Ризик:** високий — це основна інтеграційна робота

### 2.1 Узгодження API-контрактів з бекенд-командою (1 день)

**Таблиця: які серверні методи потрібні**

| Серверний метод | Що повертає | Пріоритет |
|---|---|---|
| Розширений `SearchByName` | + expiryDate, dosageForm, inn, barcode, unitsPerPackage, pharmacistBonus | 🔴 Блокер |
| `GetSKUdetail(id)` | Повні дані препарату (всі 29 полів Drug) | 🔴 Блокер |
| `ProcessSale(items, payment, bonus)` | transactionId, receiptNumber, success | 🔴 Блокер |
| `GetEdkOffers(drugId)` | [{replacementId, script, reason}] | 🟡 Бажано |
| `GetCartOffers()` / `GetTPK()` | [{drugId, reason, script, promoLabel}] | 🟡 Бажано |
| `GetOrders(dateRange, status)` | Реальні інтернет-замовлення | 🟡 Бажано |
| `GetExpenses(dateRange)` | Реальні касові операції | 🟡 Бажано |

**Якщо бекенд НЕ може дати поле** — визначити дефолтне значення:

```dart
// Приклад маплення з неповною відповіддю:
Drug.fromApiResponse(Map<String, dynamic> json) => Drug(
  id: json['ids'] ?? '',
  name: json['name'] ?? '',
  manufacturer: json['manufacturer'] ?? '',
  price: _parsePrice(json['price']),
  stock: json['qty'] ?? 0,
  // Відсутні поля — дефолти:
  dosageForm: json['dosageForm'] ?? '',           // порожнє
  pharmacistBonus: json['bonus'],                  // null = нема бонусу
  imageUrl: null,                                  // placeholder в UI
  expiryDate: json['expiryDate'],                  // null = не показувати
  unitsPerPackage: json['unitsPerPackage'],         // null = нема блістерів
);
```

### 2.2 ApiDrugRepository (3–4 дні)

```dart
class ApiDrugRepository implements DrugRepository {
  final ResilientApiClient _api;
  final LruCache<String, Drug> _cache;  // TTL 5 хвилин, max 500 записів

  @override
  Future<List<Drug>> search(String query) async {
    // 1. Перевірити кеш (якщо query вже шукали < 5 хв тому)
    // 2. DrugService.searchByName(query)
    // 3. Маплення DrugSearchItem → Drug (з дефолтами)
    // 4. Обмеження: max 50 результатів
    // 5. Зберегти в кеш
  }

  @override
  Future<Drug?> getById(String id) async {
    // 1. Кеш
    // 2. DrugService.getDetail(id) ← новий метод
    // 3. Повний маплення → Drug
  }

  @override
  Future<Drug?> getByBarcode(String barcode) async {
    // 1. DrugService.lookupByBarcode(barcode)
    // 2. getById(id) для повних даних
  }
}
```

**Стратегія завантаження (рекомендована):**
- `search()` → "легкі" Drug (~10 полів). Швидко.
- `getById()` → "повний" Drug (всі поля). Викликається при виборі рядка.
- UI показує часткові дані в таблиці, повні — в правій панелі.

### 2.3 EDK/ТПК через API або конфіг (1–2 дні)

**Якщо бекенд може:** `GetEdkOffers(drugId)` → динамічні заміни.

**Якщо бекенд НЕ може (реалістичніший варіант):**

```
assets/config/
├── edk_mapping.json       ← маппінг donor→replacement
└── tpk_offers.json        ← список рекомендацій

Оновлюється:
├── Вручну (фармацевт/менеджер)
├── Або з сервера при старті (GET /config/edk_mapping)
└── Зберігається локально (SharedPreferences)
```

### 2.4 ApiOrderRepository, ApiExpenseRepository (2 дні)

Аналогічно ApiDrugRepository — реалізація інтерфейсів з Фази 1, але з реальними API-викликами.

### 2.5 Інтеграційні тести (2 дні)

```
test/integration/
├── api_drug_repository_test.dart
│   ├── Мокнутий HTTP → правильне маплення
│   ├── Помилка сервера → порожній результат + лог
│   └── Таймаут → retry → результат або помилка
│
├── search_flow_test.dart
│   └── Введення запиту → debounce → API → список результатів
│
├── barcode_flow_test.dart
│   └── Сканування → lookup → додавання в кошик
│
└── checkout_flow_test.dart
    └── Кошик → оплата → транзакція → очищення
```

---

## 8. Фаза 3: Payment Hardening

> **Тривалість:** 5–6 днів
> **Залежності від бекенду:** ТАК (ProcessSale метод)
> **Ризик:** найвищий — це гроші

### 3.1 TransactionService (2 дні)

```
lib/services/transaction_service.dart (новий)
├── submitSale(SaleTransaction) → SaleResult
│   ├── SaleTransaction:
│   │   ├── items: List<SaleItem> (drugId, name, qty, unitPrice, total)
│   │   ├── paymentMethod: PaymentMethod (card / cash / mixed)
│   │   ├── cashAmount: double?
│   │   ├── cardAmount: double?
│   │   ├── bonusDiscount: double
│   │   ├── personalDiscount: double
│   │   ├── reimbursementAmount: double?   ← для нового модуля
│   │   ├── loyaltyPhone: String?
│   │   ├── pharmacistId: String
│   │   └── timestamp: DateTime
│   │
│   └── SaleResult:
│       ├── success: bool
│       ├── transactionId: String
│       ├── receiptNumber: String
│       └── error: String?
│
├── voidSale(transactionId) → VoidResult
└── getSaleHistory(DateTimeRange) → List<SaleTransaction>
```

**Потоковий процес оплати (новий):**

```
1. Згенерувати transactionId (UUID) на клієнті
2. Якщо є бонуси → BonusService.writeOff(clientCode, amount, transactionId)
3. TransactionService.submitSale(sale)
4. Якщо п.3 успіх → показати "Оплата пройшла", очистити кошик
5. Якщо п.3 падає → BonusService.cancelWriteOff(transactionId)
6. Якщо п.5 теж падає → зберегти в локальну чергу pending_cancellations
7. При наступному онлайн → обробити чергу
```

### 3.2 Атомарність бонуси + продаж (2 дні)

**Ідеальний варіант (якщо бекенд може):**
Один серверний метод `ProcessSale` який робить і списання бонусів, і реєстрацію продажу атомарно.

**Реалістичний варіант (якщо бекенд не змінити):**
Saga pattern на клієнті (описаний вище: writeOff → submitSale → cancelWriteOff при помилці).

```
lib/services/payment_saga.dart (новий)
├── execute(SaleTransaction, BonusInfo?) → SaleResult
├── Внутрішня логіка:
│   ├── Step 1: writeOff (compensatable)
│   ├── Step 2: submitSale
│   └── Compensate: cancelWriteOff при помилці Step 2
└── Pending queue для невдалих компенсацій
```

### 3.3 Фіскальний інтерфейс (0.5 дня)

```dart
// lib/services/fiscal_printer.dart
abstract class FiscalPrinter {
  Future<PrintResult> printReceipt(SaleTransaction sale, SaleResult result);
  Future<bool> isAvailable();
}

// lib/services/stub_fiscal_printer.dart
class StubFiscalPrinter implements FiscalPrinter {
  @override
  Future<PrintResult> printReceipt(...) async {
    AppLogger.info('FiscalPrinter', 'Receipt #${result.receiptNumber} (stub)');
    return PrintResult.success();
  }
}
```

**Реальна реалізація** (ESC/POS, Datecs, Maria, etc.) — окреме завдання з хардвер-командою.

### 3.4 Персистентність кошика (0.5 дня)

```
lib/services/cart_persistence.dart (новий)
├── saveCart(List<CartItem>) → SharedPreferences (JSON)
├── loadCart() → List<CartItem>
├── clearSavedCart()
└── Auto-save при кожній зміні кошика (debounced 500ms)
```

**Критерій приймання:** Додати 3 препарати → закрити APK → відкрити → кошик на місці.

### 3.5 Тести на payment (1 день)

```
test/services/
├── transaction_service_test.dart
│   ├── submitSale — успіх, помилка сервера, таймаут
│   └── voidSale — успіх, не знайдено
│
├── payment_saga_test.dart
│   ├── Успішний flow: writeOff + submitSale
│   ├── submitSale падає → cancelWriteOff виконується
│   ├── Обидва падають → pending queue
│   └── Без бонусів → тільки submitSale
│
└── cart_persistence_test.dart
    ├── save → load → рівні списки
    └── clearSavedCart → load → порожній
```

---

## 9. Фаза 4: Продуктивність

> **Тривалість:** 2–3 дні
> **Залежності від бекенду:** немає
> **Ризик:** низький

### 4.1 Дебаунс пошуку (0.5 дня)

```dart
// Зараз: fuzzy search O(n·m) на КОЖЕН символ
// При 5000+ SKU — помітне гальмування

// Рішення:
class _Debouncer {
  Timer? _timer;
  void run(VoidCallback action, {Duration delay = const Duration(milliseconds: 150)}) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }
}

// Використання:
onChanged: (q) => _searchDebouncer.run(() => _performSearch(q));
```

### 4.2 Ліміт результатів (0.5 дня)

```dart
// В DrugRepository.search():
final results = await _searchDrugs(query);
return results.take(50).toList();

// При скролі до кінця — можна довантажити наступні 50
// Але для POS це рідко потрібно: фармацевт бачить потрібний препарат в перших 10-20
```

### 4.3 Точкові оптимізації rebuilds (1–2 дні)

**НЕ міграція на Provider.** Натомість:

```dart
// 1. const для статичних частин
const _TableHeader();  // Шапка таблиці НІКОЛИ не змінюється

// 2. RepaintBoundary навколо дорогих зон
RepaintBoundary(
  child: ListView.builder(...)  // Таблиця препаратів
)

// 3. ValueListenableBuilder для точкових оновлень
// (тільки якщо профілювання покаже проблему)
ValueListenableBuilder<Drug?>(
  valueListenable: _selectedDrugNotifier,
  builder: (_, drug, __) => DrugDetailPanel(drug: drug),
)
```

**Обов'язково:** зняти профіль DevTools ДО і ПІСЛЯ оптимізацій. Не оптимізувати наосліп.

**Критерій приймання:** Зміна qty одного товару в кошику НЕ перемальовує таблицю (видно в DevTools).

---

## 10. Фаза 5: Хардинінг

> **Тривалість:** 3–4 дні
> **Залежності від бекенду:** мінімальні
> **Ризик:** низький

### 5.1 Валідація моделей (0.5 дня)

```dart
class Drug {
  Drug({required this.id, required this.price, required this.stock, ...})
    : assert(id.isNotEmpty, 'Drug ID cannot be empty'),
      assert(price >= 0, 'Price cannot be negative'),
      assert(stock >= 0, 'Stock cannot be negative');
}
```

### 5.2 Безпека аутентифікації (1 день)

```
Варіант А (мінімальний):
├── Пароль → SHA-256 хеш на клієнті перед відправкою
├── Сервер порівнює хеші
└── Хеш не логувати

Варіант Б (рекомендований):
├── Login → сервер видає session token (UUID)
├── Token зберігається в flutter_secure_storage (Android Keystore)
├── Кожен запит додає token як параметр
├── TTL: 8 годин (= зміна фармацевта)
└── Протухання → екран логіну
```

### 5.3 Витяг констант (1 день)

```
lib/theme/
├── app_colors.dart
│   ├── const kPrimaryBlue = Color(0xFF1E7DC8);
│   ├── const kAccentPurple = Color(0xFF8B5CF6);
│   ├── const kBackgroundGray = Color(0xFFF4F5F8);
│   └── ... (всі кольори з кодової бази)
│
├── app_sizes.dart
│   ├── const kColBadge = 44.0;
│   ├── const kColStock = 52.0;
│   └── ... (всі column widths, paddings)
│
└── app_durations.dart
    ├── const kAnimFast = Duration(milliseconds: 200);
    ├── const kAnimMedium = Duration(milliseconds: 300);
    ├── const kSearchDebounce = Duration(milliseconds: 150);
    └── const kServerDebounce = Duration(milliseconds: 400);
```

### 5.4 Фінальні тести (1–1.5 дня)

Доповнити тестову базу до **≥60% покриття на бізнес-логіку**:

```
test/
├── models/          — fromJson, toJson, equality, validation, edge cases
├── repositories/    — mock та api (з мокнутим HTTP)
├── services/        — парсинг, retry, error handling
├── mixins/          — checkout calculation, EDK state
└── integration/     — пошук→кошик→оплата (end-to-end з mock repo)
```

### 5.5 Механізм оновлень APK (0.5 дня)

```
Варіанти:
├── MDM (якщо є) — централізоване оновлення через консоль
├── In-app update — перевірка версії при старті, завантаження APK з внутрішнього сервера
└── Ручне оновлення — надіслати APK на пристрій

Мінімально:
├── lib/services/update_checker.dart
│   ├── checkForUpdate() → {available: bool, url: String, version: String}
│   └── Показати діалог "Доступна нова версія X.Y.Z. Оновити?"
└── Версія показується в TopBar (вже є badge фармацевта, додати версію)
```

---

## 11. Залежності від бекенд-команди

Фази 0 і 1 **не залежать від бекенду** — починаємо негайно.

Фази 2 і 3 **заблоковані** без серверних методів. Узгодити їх ПАРАЛЕЛЬНО з Фазами 0–1.

| Серверний метод | Блокує фазу | Пріоритет | Коментар |
|---|---|---|---|
| Розширення `SearchByName` (додаткові поля) | Фаза 2.2 | 🔴 Блокер | Без цього — часткові дані в таблиці |
| `GetSKUdetail(id)` | Фаза 2.2 | 🔴 Блокер | Без цього — порожня права панель |
| `ProcessSale(items, payment, bonus)` | Фаза 3.1 | 🔴 Блокер | Без цього — оплата не фіксується |
| `GetEdkOffers(drugId)` | Фаза 2.3 | 🟡 Бажано | Альтернатива: JSON-конфіг |
| `GetTPKOffers()` | Фаза 2.3 | 🟡 Бажано | Альтернатива: JSON-конфіг |
| `GetOrders(dateRange, status)` | Фаза 2.4 | 🟡 Бажано | Може бути пізніше |
| `GetExpenses(dateRange)` | Фаза 2.4 | 🟡 Бажано | Може бути пізніше |
| Реімбурсація API (формат залежить від нового модуля) | Фаза 3.1 | 🟠 Після UI | Визначиться після UI реімбурсації |

---

## 12. Зведена таблиця

| Фаза | Тижні | Зусилля | Що отримуємо | Залежність від бекенду |
|------|-------|---------|-------------|---|
| **0. Інфраструктура** | 1 | 4–5 днів | Конфіги, логи, retry, тести на гроші, Android build | Ні |
| **1. Data Layer** | 2–3 | 6–7 днів | Repository pattern, імутабельність, серіалізація, DI | Ні |
| **2. API інтеграція** | 4–6 | 8–10 днів | Реальні дані, кеш, маплення, EDK/ТПК | **ТАК** |
| **3. Payment** | 7–8 | 5–6 днів | Атомарна оплата, транзакції, персистентність, фіскальний інтерфейс | **ТАК** |
| **4. Performance** | 9 | 2–3 дні | Debounce, ліміти, RepaintBoundary | Ні |
| **5. Хардинінг** | 10 | 3–4 дні | Валідація, безпека, константи, тести ≥60%, оновлення APK | Мінімально |
| | | **~30–35 днів** | **Production-ready POS** | |

### Графік (Gantt)

```
Тиждень:  1     2     3     4     5     6     7     8     9     10
          ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
Фаза 0:   ████▌                                                    Інфраструктура
Фаза 1:         ██████████▌                                        Data Layer
Фаза 2:                     █████████████████▌                     API інтеграція
Фаза 3:                                       ██████████▌          Payment
Фаза 4:                                                 ████▌     Performance
Фаза 5:                                                     █████ Хардинінг

Бекенд:   ◇─────────────────◇ Узгодження API     ◇ Готові методи
          ↑ Паралельно з Ф0-1                      ↑ Блокер для Ф2-3
```

---

## 13. Що свідомо НЕ включено

| Пункт | Причина |
|---|---|
| **Міграція на Provider / Riverpod** | Ризик регресії непропорційний. `ValueListenableBuilder` + `RepaintBoundary` вирішують 80% проблеми за 10% зусиль. Повна міграція — окремий проект, якщо setState стане реальним bottleneck |
| **Accessibility (Semantics, screen readers)** | Внутрішній інструмент для фармацевтів. Не використовують screen reader на касі |
| **i18n / локалізація** | Аптечна мережа працює українською. Друга мова не потрібна |
| **go_router / deep links** | SPA на одному екрані. Esc cascade замінює browser back |
| **Серверна пагінація** | Ліміт 50 на клієнті достатній. Фармацевт не скролить далі 20-го рядка |
| **Повне Clean Architecture (domain layer, use cases)** | Over-engineering для POS з 6 моделями. Repository + Services достатньо |

---

## 14. Чеклист перед стартом

Перед початком реінжинірингу перевірити:

- [ ] **UI нових модулів завершено:** соціальні проекти, реімбурсація, повідомлення, аналітика
- [ ] **Моделі нових модулів** створені з `const` + `final` (як описано в розділі 4)
- [ ] **TODO-маркери** залишені в місцях де нові модулі впливають на checkout/payment
- [ ] **Mock-дані нових модулів** — в окремих файлах (не змішані з існуючими)
- [ ] **Бекенд-команда** отримала список необхідних серверних методів (розділ 11)
- [ ] **Цільове Android-обладнання** доступне для тестування (монітор + клавіатура + сканер + принтер)
- [ ] **Git branch** для реінжинірингу створено (`feature/reengineering-v1`)

Коли все ✓ — починаємо з Фази 0.
