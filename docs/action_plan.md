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

### ✅ A4. Стан зміни: відновлення з ПРРО, безпечний авто-Z  *(2026-07-03, не закомічено)*
`ShiftService.ensureRestored()` (дедуп) на старті (main.dart) + await перед показом старту
зміни (pos_screen `_openPharmacistPicker`). `_restoreFromServer`: якщо xReport.shiftOpen і
зміна відкрита СЬОГОДНІ (за `shift_duration`) → `_state` відкрита (діалог старту не
показується, авто-Z не робиться, вихід пропонує Z); попередня доба → стан закритий (старт
зробить авто-Z). Той самий today/prev-day чек додано в auto-Z branch `startShift` (замість
довіри рядку помилки). Невідома тривалість → трактуємо як СЬОГОДНІ (безпечніше за авто-Z).
- Файли: `shift_service.dart` (_restoreFromServer/_estimateOpenedAt/_isSameDay + startShift),
  `main.dart` (ensureRestored у старт-блоці), `pos_screen.dart` (await ensureRestored).
- `flutter analyze` чисто; `flutter test` 73 passed.
- ✅ ПІДТВЕРДЖЕНО на живому ПРРО (2026-07-07): рестарт при відкритій зміні → `зміна відкрита=true`,
  діалог старту НЕ показується. `shift_state=true` (bool). Діагностику прибрано (коміт нижче).
- Розрізнення today/prev-day: `from_date` (буває null) ?? `shift_duration` (хвилини з відкриття —
  каса віддає це поле, 0 при щойно відкритій, росте з часом). Для сьогоднішньої → «сьогодні».
  Вчорашню (велика тривалість) → минула доба → авто-Z. Крайовий вчорашній кейс наживо НЕ
  перевіряли (важко відтворити), але сигнал коректний.

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

### ◐ B1. Sparta/ЛАЙК: чесний флоу або вимкнути
**Зроблено (креди):** `LoyaltyService` більше не на hardcoded demo — `SplConfig` тепер
перекривається живими per-аптека кредами з `GetSPLParam` (`SplConfig.applyFrom(SplParams)`,
`LoyaltyService._ensureConfig()` перед checkCard/sale). `SplParams.fromJson` парсить реальну
відповідь 1:1 (звірено). Це також покриває B6 для ЛАЙК (креди з сервера, не dart_define).
- Файли: `loyalty_service.dart` (SplConfig мутабельний + applyFrom + _ensureConfig).
- `flutter analyze` чисто; `flutter test` 73 passed.
- ⚠️ ТЕСТ: тепер checkCard/sale б'ють у ПРОД ЛАЙК (`loyalty.aptekanizkihcen.ua:4018`) з
  реальними posKey/apiToken. Перевірити на тестовій картці; бонуси реальні.
- **Лишається (order-флоу):** синхронний `tx/order` (pending) ДО грошей → ПРРО →
  `orderModify`(+лінк чека) → `orderStatusChange('D')`; відмова Спарти блокує лише бонусну
  частину. Зараз усе ще fire-and-forget `sale` (audit #5). `sparta_service.dart` (готовий
  order/modify/statusChange) ще не підключений. Файли: `pos_screen.dart` (_registerLoyaltySale).
- ⚠️ [БЕКЕНД]: дубль ключа `EdFarmasellL` у GetSPLParam (друге має бути `EdFarmasellP`?) — до B8.

### ✅ B2. CacheApiClient: retry тільки для читаючих сервісів  *(2026-07-03, не закомічено)*
Додано `_nonIdempotentServices = {SaveSumDay, SavesgVNakl, ZRep}`; на timeout/ClientException
ці сервіси НЕ ретраяться (одна спроба) — знято ризик подвійного внесення/накладної/Z.
503 (шлюз відхилив до обробки) лишається ретрайним для всіх. sgVRoznSetLock не включено:
воно ставить АБСОЛЮТНУ кількість → повтор ідемпотентний.
- Файли: `lib/services/cache_api_client.dart` (набір + guard `retryAmbiguous`).
- `flutter analyze` — чисто (5 передіснуючих лінтів, не від цієї зміни).

### ✅ B3. Екранування параметрів query string  *(2026-07-03, не закомічено)*
Мінімально-інвазивно: у ЗНАЧЕННЯХ екрануємо лише структурні символи `% & = #`
(`_encodeParamValue`), решту (пробіли/кирилиця/`*`/`,`/`+`) лишаємо — їх коректно
обробляє наступний Uri.parse. Ін'єкція через `&ServiceName=...` у пошуку/причині каси
закрита; `*`/`,` в u-кодах лишаються літеральними.
- Файли: `cache_api_client.dart` (_encodeParamValue + map).
- Перевірено ізольованим скриптом: (1) u-код `479*1*47*10**0,2*3*` літеральний;
  (2) injection `готівка&ServiceName=ZRep` → ServiceName НЕ підмінюється;
  (3) old vs new URL для кирилиці/u-коду/телефону/дробу — БАЙТ-У-БАЙТ однакові (0 регресу).
- `flutter analyze` чисто (5 передіснуючих лінтів).
- ⚠️ ТЕСТ на касі: звичайний пошук (кирилиця, багатослівний), лукап по u-коду/штрихкоду,
  причина касової операції — усе працює як раніше.

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

### ✅ B9. Сканування — AnalizBarCode (Задача 27)  *(2026-07-03, не закомічено→в master)*
Серверний диспетчер скана підключено до UI.
- **Сервіс:** `DrugService.analizBarCode(barcode, {form})` + `BarCodeAnalysis` + `BarCodeForm`.
- **Захоплення:** скан = Tab (маркер) + символи, БЕЗ Enter → флаш по таймауту бездіяльності
  120 мс (`_handleGlobalKey`/`_beginScanCapture`/`_flushScan`).
- **Диспатч (`_onScan`):** товар (SKod)→GetSKUprice→показати+додати 1 у кошик (вибиття);
  SpartaCard→`_identifyByLoyaltyCard` (checkCard+IdentSPL, підставляє телефон з `mobile`,
  показує бонуси, нарахування як у телефонному флоу); noscan/помилка→снекбар.
- **NameForm:** `SumSdach` коли кошик непорожній і відкритий, інакше основна форма; `SPLIdent`
  не шлемо (окремої форми нема).
- `flutter analyze` чисто; `flutter test` 73 passed.
- ✅ ПІДТВЕРДЖЕНО через F4 (2026-07-07): `]E04823002228281` → SKod/UKod резолвляться → товар
  у кошику. Ключове: **потрібен AIM-префікс символіки** (`]E0` для EAN-13; `]F0` — внутрішній
  стікер). Реальний сканер його додає сам; наш захват передає як є. Ціну/залишок беремо по
  ЧИСТОМУ штрихкоду через GetSKUprice (SKod там не приймається).
- F4 = ручний скан через AnalizBarCode (ввід не лише цифри); SouponCRM (друкарська помилка
  сервера) читаємо як CouponCRM. Тимчасовий діагностичний діалог прибрано.
- ⚠️ ЛИШИЛОСЬ: перевірити реальним сканером, що він шле `]E0`-стиль префікси (налаштування
  сканера); скан картки ЛАЙК (потрібен тестовий номер картки від Каті).

### ✅ B11. Дублювання Z-звіту при закритті зміни (audit #6)  *(2026-07-07, знайдено Катею)*
Каса 1334 (наш апарат) робила **3× «Вынос. Z-отчет»** на одне закриття (18:19/22/25),
старий роздріб (1336) — один. Причина: `closeShift()` неідемпотентний + кнопка «Закрити
зміну» після закриття знову вмикалась (касир клікав повторно). Кожен `ZRep` створює запис.
- Фікс: `closeShift()` — гард `!state.isOpen` + `_closing` (паралель кнопка/вихід);
  дашборд — кнопка блокується й показує «Зміну закрито» після закриття.
- Файли: `shift_service.dart` (closeShift), `shift_dashboard.dart` (_buildCloseShiftButton).
- `flutter analyze` чисто; `flutter test` 73 passed.
- ⚠️ ТЕСТ: закрити зміну → кнопка блокується; повторний клік/вихід НЕ дає другого
  «Вынос. Z-отчет» у касовій дисципліні.

### 🔖 B10. Спец-картки й купони скану  *(відкладено; купони додано в модель 2026-07-07)*
AnalizBarCode повертає `SpecCard`/`PresentCard`/`CityCard` (картки) та `CouponSPL`/`CouponCRM`
(купони Спарти/CRM — Катя додала пізніше). Розпізнаються, у моделі `BarCodeAnalysis` є, але
флоу застосування нема — зараз снекбар-заглушки в `_onScan`. Повернутись, коли буде поведінка.

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

### ✅ C5. cacheWidth для Image.network (9 місць)  *(2026-07-03, не закомічено)*
Додано `cacheWidth` ≈ 2× дисплейного розміру: cart_panel 64, cart_offer_card 128,
order_edk_card 96, orders_panel 96/512, edk_panel 256, out_of_stock_panel 256/256,
drug_detail_panel 256. Повнорозмірні картинки з anc.ua більше не декодуються в повну
роздільність заради превʼю — менше CPU й памʼяті в image cache.
- `flutter analyze` чисто; `flutter test` 73 passed.

### ☐ C6. Великі відповіді — поза UI-ізолятом
JSON-фікси + парсинг GetTopDrugs/GetOrders через `compute()`. Втрачає сенс після D6
(фікс JSON на сервері) — оцінити черговість.
- Файли: `lib/services/cache_api_client.dart:160-206`

### ✅ C7. Дрібне  *(2026-07-03, не закомічено)*
- `SpartaService`: один статичний keep-alive `http.Client` замість створення+закриття
  на кожен виклик (зайвий TCP+TLS handshake). Прибрано `client.close()` у `_post`.
- `flutter analyze` чисто; `flutter test` 73 passed.

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
