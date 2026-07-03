# План дій за результатами аудиту (2026-07-03)

Джерело: архітектурний аудит + перф-аналіз (сесія 2026-07-03).
Статуси: ☐ не почато / ◐ в роботі / ✅ готово. Познач **[БЕКЕНД]** = потрібна Катя/Caché.

Пріоритет виконання: Етап 0 → C1 (quick win) → Етап 1 → Етап 2 → Етап 3.

---

## Етап 0 — Фіскальні блокери (до пілота на живій касі)

### ☐ A1. Ідемпотентність фіскалізації (дублікати чеків)
Таймаут ПРРО ≠ «не виконано»: після `TimeoutException` та перед flush кожного чека з черги —
верифікація через `xReport(include_checks)` за `local_number`; чек уже існує → не створювати вдруге.
- Файли: `lib/services/prro_service.dart:551`, `lib/services/prro_queue.dart:140`
- Критерій: штучний таймаут (обрив мережі після відправки) не породжує другий чек.

### ☐ A2. Чек ПРРО = сума, яку платить клієнт **[БЕКЕНД: формат]**
Products для ПРРО будувати з `GetSumSkid.goods` (мапінг за `skod` вже є в
`cart_price_service.dart:336`), знижки → `sum_discount`, бонусна частина → окремий payment
або знижка (узгодити з Катею/CashDesk). Cash withdrawal — вирішити: у чек чи окрема операція.
- Файли: `lib/widgets/cart_panel.dart:530-604, 612-707`
- Критерій: сума чека ПРРО == «До сплати» на екрані == гроші в касі; бонуси видно в чеку.

### ☐ A3. Фіксація продажу в Caché після фіскалізації + журнал відновлення **[БЕКЕНД: сервіс]**
1. Після успіху ПРРО → виклик Caché-сервісу фіксації (флаг + каса + фіскномер до накладної).
2. Write-ahead журнал продажу на диск: `started → fiscalized → fixed → done`; на старті
   додатку — відновлення незавершених.
3. `SavesgVNakl` впав → блокувати продаж (прибрати fallback `localNumber = timestamp`).
- Файли: `lib/widgets/cart_panel.dart:541-558`, новий `lib/services/sale_journal.dart`
- Критерій: kill процесу між фіскалізацією і onPay → після рестарту продаж добивається/видно в журналі.

### ☐ A4. Стан зміни: відновлення з ПРРО, безпечний авто-Z
На старті — `xReport().shiftOpen` → відновити `ShiftState`. Авто-Z лише якщо зміна відкрита
з попередньої доби (за датою відкриття), а не за `err.contains('вже відкрита')`.
- Файли: `lib/services/shift_service.dart:27, 70-78`, `lib/main.dart:46-59`
- Критерій: рестарт додатка посеред дня НЕ викликає Z і не пропонує повторне внесення.

### ☐ A5. Конфіг ПРРО з реєстру, прибрати тестовий ФН
`environment` + фіскальний номер з `ZSMU\Farm` (edVerMini/edPassMini/ekkIP...); fallback на
тестовий `numFiscal=4000952779` прибрати → якщо ФН не визначився, hard fail із повідомленням.
- Файли: `lib/services/prro_service.dart:30-58`, `lib/services/registry_config.dart`
- Критерій: жоден чек не може піти на тестовий ФН на бойовій касі.

### ☐ A6. Паролі фармацевтів не покидають сервер **[БЕКЕНД]**
`GetUsersRlz` → тільки імена (без `pswd`, бажано без ІПН). Перевірка пароля — тільки
`LoginRlz` на сервері. Клієнт: прибрати локальне порівняння.
- Файли: `lib/services/auth_service.dart:119-144`, `lib/widgets/pharmacist_picker_dialog.dart:83-99`
- Критерій: у трафіку/відповідях немає жодного пароля; невірний пароль відбиває сервер.

### ✅ A7. Викинути мокові знижки з бойових шляхів  *(2026-07-03, не закомічено)*
1. «Персональна знижка з останньої цифри телефону» — гейт `if (!ApiConfig.useMock)`:
   на live кнопка показує «Персональна знижка недоступна», нічого не рахує (cart + orders).
2. Рука допомоги (3 місця): fake-fallback лише під `useMock`; на live без даних FarmaSell
   / при помилці API — снекбар «недоступна», знижка НЕ вигадується.
- Файли: `cart_panel.dart` (_fetchAvailableDiscount/_requestDiscount),
  `orders_panel.dart` (_fetchAvailableOrderDiscount/_requestOrderDiscount),
  `pos_screen.dart` (_requestHelpingHand/_fetchHelpingHandPrice + _showHelpingHandUnavailable),
  `drug_detail_panel.dart` (_checkDiscount, + імпорт api_config).
- `flutter analyze` — чисто (13 передіснуючих warnings, не від цієї зміни).
- ⚠️ ТЕСТ на live: кнопка «Знижка» → «недоступна»; Рука допомоги без FarmaSell → «недоступна»,
  ціна в чеку не змінюється.

### ☐ A8. Інтернет-замовлення: оплата без ПРРО — заблокувати
Мінімум: дизейбл кнопки «Провести оплату» в OrdersPanel до підключення фіскального конвеєра
(повне підключення — D1). `UpdateOrderStatus('apteka pay')` без чека не має бути можливим.
- Файли: `lib/widgets/orders_panel.dart:848-880`

---

## Quick win (можна взяти прямо зараз, ~півдня)

### ✅ C1. SKUdetail — тільки для вибраного товару  *(2026-07-03, не закомічено)*
Прибрано цикл fetch-для-всіх у `_searchByNameOnServer`; додано `_fetchSKUDetail(_selectedDrug!)`
у блок вибраного товару (раніше його тягнув лише цикл) + страховка в
`_setQuantity`/`_setFractionalQuantity` (метод дедуплікує через `_skuDetailFetched`).
Таблиця повністю обслуговується `SearchByNameSKU` (unitsPerPackage є з d4a5edc).
- Ефект: пошук ~32 запити → ~3; зникає голодування семафора.
- `flutter analyze` — чисто.
- ⚠️ ПОТРЕБУЄ РУЧНОГО ТЕСТУ: пошук → вибір рядка (деталь/аналоги/ЄДК підтягуються),
  додавання без вибору рядка (barcode у ПРРО-чеку є), F6/Ctrl+цифра (дільник), out-of-stock.
- FOLLOW-UP (bdcd681): серверна гілка пошуку не несла pharmacistBonus/isOwnBrand/
  dosageForm/category (їх backfill-ив SKUdetail на всіх рядках) → бонус/СТМ зникали
  з невибраних рядків. Тепер несемо прямо з SearchByNameSKU (як instant-кеш гілка).

---

## Етап 1 — Серйозні ризики

### ☐ B1. Sparta/ЛАЙК: чесний флоу або вимкнути
Рішення А (правильне): `SplParams` з `GetSPLParam` замість hardcoded demo URL; синхронний
`tx/order` (pending) ДО прийому грошей → ПРРО → `orderModify` (+лінк чека) →
`orderStatusChange('D')`; відмова Спарти блокує тільки бонусну частину.
Рішення Б (тимчасове): фіче-флаг off + сховати бонуси в UI.
- Файли: `lib/services/loyalty_service.dart:7`, `lib/services/sparta_service.dart` (не підключений!),
  `lib/screens/pos_screen.dart:2905-2973`

### ✅ B2. CacheApiClient: retry тільки для читаючих сервісів  *(2026-07-03, не закомічено)*
Додано `_nonIdempotentServices = {SaveSumDay, SavesgVNakl, ZRep}`; на timeout/ClientException
ці сервіси НЕ ретраяться (одна спроба) — знято ризик подвійного внесення/накладної/Z.
503 (шлюз відхилив до обробки) лишається ретрайним для всіх. sgVRoznSetLock не включено:
воно ставить АБСОЛЮТНУ кількість → повтор ідемпотентний.
- Файли: `lib/services/cache_api_client.dart` (набір + guard `retryAmbiguous`).
- `flutter analyze` — чисто (5 передіснуючих лінтів, не від цієї зміни).

### ☐ B3. Екранування параметрів query string
Енкодити все, крім `*` і `,` (обмеження Caché CSP). Прибрати ін'єкцію через `&`/`=`/`#`
у пошуковому запиті/причині касової операції.
- Файли: `lib/services/cache_api_client.dart:125-131`

### ☐ B4. Файловий журнал фіскальних операцій + ретрай ZRep
Append-only лог (накладна/ПРРО/Sparta з номерами й статусами) замість debugPrint у нікуди.
ZRep — персистентний ретрай за зразком PrroQueue.
- Файли: `lib/services/shift_service.dart:110-121`, новий `lib/services/fiscal_log.dart`
- Частково перекривається A3 (журнал продажу) — робити разом.

### ☐ B5. Локи залишків: TTL + серіалізація **[БЕКЕНД: TTL]**
1. З'ясувати/додати серверний TTL на `sgVRoznSetLock` (осиротілі резерви після краху каси).
2. Клієнт: черга локів по товару — коалесціювати швидкі ±, слати тільки останнє значення.
   (Робити разом з C3 — оптимістичний кошик.)
- Файли: `lib/screens/pos_screen.dart:1904-1954, 2312-2378`

### ☐ B6. Секрети
1. Прибрати `cabinetUrl` (email+password у URL браузера) — `lib/services/prro_service.dart:862-868`.
2. Довгограюче **[БЕКЕНД]**: ПРРО/Skarb-креди роздавати сервером (шлях `GetSPLParam` уже є),
   з бінарника винести.

### ☐ B8. Рука допомоги: знижка не доходить до суми/сервера  *(знайдено на тесті 2026-07-03)*
Попап HH показує клієнтську `discountPrice` (FarmaSell), але кошик і «До сплати»
показують серверну ціну з `GetSumSkid`, який про HH нічого не знає → повна ціна.
При цьому фіскальний чек будується з `item.effectivePrice` (зі знижкою) → розсинхрон
у межах продажу: кошик/сума = повна, чек = зі знижкою. Це підпункт audit #2.
- Передіснуюче (не від A7). Файли: `cart_item_widget.dart:347`, `cart_price_service.dart:211`,
  `cart_panel.dart:625,632`, `pos_screen.dart` (_onHelpingHandAddToCart).
- Шлях №1 (правильний, **[БЕКЕНД]**): GetSumSkid має враховувати HH (FarmaSell→Caché або
  HH-параметр у GetSumSkid) → кошик/сума/чек збігаються самі.
- Шлях №2 (стоп-геп): для позицій з `discountPrice` показувати `item.total` і зменшувати
  `_displayCartTotal`/`finalTotal` на дельту — узгодити кошик+суму+чек локально.
- Рішення: у план + питання Каті (шлях №1). Стоп-геп — лише якщо HH треба на пілоті.

### ✅ B7. Періодичний flush черги ПРРО  *(2026-07-03, не закомічено)*
Таймер у PosScreen (60 с): при непорожній черзі — `PrroQueue.flush()`, потім оновлення
лічильника. Індикатор у TopBar «ПРРО: N у черзі» (amber), клік = ручний flush зараз.
Лічильник також оновлюється після оплати (продаж міг покласти offline-чек).
- Файли: `pos_screen.dart` (_initPrroQueueWatch/_tickPrroFlush/_flushPrroNow + dispose),
  `top_bar.dart` (pendingPrroCount + onPendingPrroTap).
- `flutter analyze` чисто; `flutter test` 73 passed.
- ⚠️ ТЕСТ: продаж при вимкненому ПРРО → чек у черзі, індикатор «ПРРО: 1 у черзі»;
  клік по індикатору / очікування 60 с з піднятим ПРРО → чек іде, лічильник спадає.

---

## Етап 2 — Продуктивність

### ☐ C2. Пріоритети в семафорі CacheApiClient
Два класи: інтерактивні (пошук, лок, GetSumSkid) обганяють фонові (SKUdetail, stop-price,
top-500). ~20 рядків у `_acquireSlot`.
- Файли: `lib/services/cache_api_client.dart:65-87`

### ☐ C3. Оптимістичний кошик
UI оновлюється одразу, лок — у фоні з відкатом при відмові. Разом з B5 (серіалізація).
- Файли: `lib/screens/pos_screen.dart:1956-2096, 2305-2378`

### ☐ C4. Батч стоп-цін **[БЕКЕНД]** + дебаунс rebuild-ів
`GetStopPriceUKod` для списку ukod-ів одним запитом (500 → 5-10). Клієнт: onBatch-setState
дебаунсити (1 rebuild / 250 мс), те саме для навали SKUdetail-відповідей.
- Файли: `lib/services/stop_price_service.dart:79-94`, `lib/screens/pos_screen.dart:2430-2444`

### ☐ C5. cacheWidth для Image.network (9 місць)
Повнорозмірні картинки з anc.ua декодяться для превʼю 32–120 px. Додати `cacheWidth:` ≈ 2×
розміру віджета: out_of_stock_panel (×2), edk_panel, order_edk_card, orders_panel (×2),
drug_detail_panel, cart_panel, cart_offer_card.

### ☐ C6. Великі відповіді — поза UI-ізолятом
JSON-фікси + парсинг GetTopDrugs/GetOrders через `compute()`. Втрачає сенс після D6
(фікс JSON на сервері) — оцінити черговість.
- Файли: `lib/services/cache_api_client.dart:160-206`

### ☐ C7. Дрібне
- `SpartaService`: один статичний `http.Client` замість створення на кожен виклик
  (`lib/services/sparta_service.dart:62`).

---

## Етап 3 — Техборг / якість / тираж

### ☐ D1. Спільний фіскальний конвеєр
Винести `_sendFiscalReceipt` + накладну + журнал у `SaleService`; підключити CartPanel і
OrdersPanel (розблокує A8 повністю). Прибрати дубль checkout-логіки.

### ☐ D2. Тести на місця «баг = гроші»
- CacheApiClient: усі JSON-фікси + балансувальник дужок (у т.ч. дужки в назвах товарів)
- PrroQueue: серіалізація/flush/поведінка при connection vs logical
- GetSumSkid: мапінг за skod, розбіжність server/local
- ShiftService: логіка авто-Z
- `_buildPrroProducts`/`_buildPrroPayments`: cost == price×amount, блістери

### ☐ D3. Per-аптека конфіг з реєстру/сервера
`pharmacyGlobId`, `cityId`, координати, `hasRobot` — з `ZSMU\Farm` або Caché
(`lib/services/api_config.dart:24-33`). Без цього тираж на другу аптеку неможливий.

### ☐ D4. Підсумки зміни з xReport
`ShiftState.cashInBox/cashlessTotal/checksCount` наповнювати з `PrroService.xReport()`
замість нулів (`lib/services/shift_service.dart:25`).

### ☐ D5. Реліз-процес
Автоінкремент build number; канарейкова аптека; чек-лист фіскальних сценаріїв перед
розкаткою (продаж готівка/картка/бонуси/дріб, повернення, Z, offline-черга, рестарт посеред дня).

### ☐ D6. JSON лагодити на сервері **[БЕКЕНД]**
Передати Каті список битих сервісів: GetUsers (пропущений `}`), GetOrders (кома),
GetStopPriceUKod (зайва лапка), GetSPLParam (лапка ключа), незакриті `]}`.
Після фіксу — зняти клієнтські патчі (`cache_api_client.dart:168-202`), лишити лог-детектор.

---

## Залежності від бекенду (список для Каті, за пріоритетом)

1. **A6**: GetUsersRlz без паролів; перевірка пароля в LoginRlz.
2. **A3**: сервіс пост-фіскалізаційної фіксації (накладна + фіскномер + каса).
3. **A2**: формат передачі знижок/бонусів у чек (узгодження, можливо без змін Caché).
4. **B5**: TTL/авто-зняття осиротілих `sgVRoznSetLock`.
5. **C4**: батч-варіант GetStopPriceUKod (список ukod-ів).
6. **B8**: чи має GetSumSkid враховувати знижку «Рука допомоги» (FarmaSell→Caché).
7. **D6**: виправлення битого JSON у 5 сервісах.
7. (з аудиту, довгограюче) **B6**: роздача ПРРО/Skarb-кредів сервером.
