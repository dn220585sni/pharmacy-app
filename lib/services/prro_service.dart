import 'dart:async';
import '../models/money.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../utils/json_num.dart';
import 'fiscal_log.dart';

/// Середовище ПРРО.
///
/// В аптеці використовується SmartConnect — локальний offline-додаток
/// від CashDesk на ПК у БЦ-26 (10.15.30.61). Він сам тримає офлайн-чергу
/// і пушить чеки коли інтернет з'являється. Для розробки зручніше
/// використовувати хмарну пісочницю.
enum PrroEnvironment {
  /// Хмарна пісочниця податкової — для розробки.
  cloudTest('https://test.cashdesk.com.ua/api/v2'),

  /// Локальний SmartConnect, тестовий порт.
  smartConnectTest('http://10.15.30.61:8000/api/v2'),

  /// Локальний SmartConnect, прод порт.
  smartConnectProd('http://10.15.30.61:8001/api/v2');

  const PrroEnvironment(this.baseUrl);
  final String baseUrl;
}

/// Конфігурація ПРРО (CashDesk).
///
/// Compile-time дефолти — для розробки (cloud test). На касі значення
/// перевизначаються з реєстру `HKCU\Software\ZSMU\Farm` у
/// `RegistryConfig.load()` — ключі сумісні з cash_uft.dll
/// (специфікація Попова 2026-07-10).
class PrroConfig {
  /// Дефолтне середовище для розробки (коли реєстр не налаштований).
  static const environment = PrroEnvironment.cloudTest;

  /// Робочий URL ПРРО. Реєстр: `ekkIP` — локальний SmartConnect
  /// (offline-модуль на сервері аптеки, тримає чергу чеків без інтернету).
  static String baseUrl = environment.baseUrl;

  /// Online CashDesk. Реєстр: `ekkIPPort` — для звітів за період
  /// (їх немає в БД SmartConnect). Поки не використовується.
  static String? onlineBaseUrl;

  /// Облікові дані для отримання токена, коли bearer відсутній або
  /// прострочений. Реєстр: `edVerMini` (email) / `edPassMini` (password).
  /// Дефолти — з --dart-define-from-file=dart_define.json (gitignored).
  static String email = const String.fromEnvironment('PRRO_EMAIL');
  static String password = const String.fromEnvironment('PRRO_PASSWORD');

  /// Developer ID (обов'язковий заголовок) — ідентифікація наших чеків
  /// у моніторингу CashDesk по всіх юрособах.
  static const developerId = 'ANC';

  /// Фіскальний номер РРО. Реєстр: `ekkPort`.
  /// Дефолт 4000952779 — тестовий ФН (Дмитрій-тестировщик 2026-05-11),
  /// не пересікається з online-розничкою. Реальний номер також
  /// підтверджується з `opened_shift` після авторизації
  /// (див. [PrroService.activeFiscalNumber]).
  static int numFiscal = 4000952779;

  /// ФН прийшов з реєстру (бойова каса) — контроль, що чеки не йдуть
  /// на тестовий ФН (критерій A5).
  static bool fiscalFromRegistry = false;

  /// A5: дозволити фіскалізацію з compile-time дефолтом ФН у release.
  /// `--dart-define=PRRO_ALLOW_DEFAULT_FISCAL=true` — аварійний вимикач, якщо
  /// каса має працювати до налагодження реєстру. За замовчуванням вимкнено.
  static const allowDefaultFiscal =
      bool.fromEnvironment('PRRO_ALLOW_DEFAULT_FISCAL');

  /// A5: чи можна взагалі фіскалізувати цим ФН.
  ///
  /// `true` лише коли номер прийшов з реєстру каси (`ZSMU\Farm → ekkPort`).
  /// Інакше в бінарнику лишається дефолт [numFiscal] = ТЕСТОВИЙ ФН, і чеки
  /// бойової каси пішли б на нього — мовчки, з коректним «SALE OK» у лозі.
  /// Debug-збірка (розробка на cloud test) і явний [allowDefaultFiscal]
  /// дозволені.
  static bool get fiscalTrusted => fiscalTrustedWhen(
        fromRegistry: fiscalFromRegistry,
        allowDefault: allowDefaultFiscal,
        isDebugBuild: kDebugMode,
      );

  /// Правило [fiscalTrusted] у чистому вигляді — щоб таблицю рішень можна було
  /// покрити тестами (у `flutter test` `kDebugMode` завжди true).
  static bool fiscalTrustedWhen({
    required bool fromRegistry,
    required bool allowDefault,
    required bool isDebugBuild,
  }) =>
      fromRegistry || allowDefault || isDebugBuild;

  /// Готовий Bearer-токен з реєстру (`bearer`, з ОК ПРРО, живе ~365 днів).
  /// Використовується поки не прострочений; після ре-авторизації новий
  /// пишеться назад у реєстр через [persistBearerToRegistry].
  static String? registryBearer;

  /// Записати оновлений bearer назад у реєстр (ставить RegistryConfig,
  /// щоб уникнути циклічного імпорту). null — реєстр недоступний.
  static void Function(String bearer)? persistBearerToRegistry;

  /// Ширина рядка TXT-чека (`text_print`, друк на термопринтері).
  /// Реєстр: `ekkKolBukv`. Іде в `print_width`.
  static int printWidth = 40;

  /// Ширина рядка PDF-представлення (чеки, X/Z-звіти; зберігається в папці
  /// out на 7 днів для друку без інтернету). Реєстр: `ekkSpeed`. Іде в `pdf_width`.
  static int pdfWidth = 40;

  /// Друк чеків (поки не використовується — на майбутнє):
  /// коефіцієнт масштабу QR (`koef_scale`), фонт TXT-чека (`monofont`),
  /// номер принтера (`PRRO_index_printer`).
  static double qrScale = 0.75;
  static String monoFont = 'Arial';
  static int printerIndex = 1;

  /// Логіка формування чека (`chkSkidkaSumma`, `cbChKredit`) — читаємо,
  /// семантику уточнюємо в Попова.
  static String chkSkidkaSumma = '1';
  static String cbChKredit = '1';

  /// Ставки ПДВ для чеків (ліки / решта). null → `tax_prc` не шлеться =
  /// «Без ПДВ». НЕ хардкодимо 7/20: податкові групи — властивість реєстрації
  /// РРО в ДПС (тестовий 4000952779/АВІС-ФАРМА має лише «БЕЗ ПДВ», SmartConnect
  /// відхиляв 7% — «Податок "БЕЗ ПДВ" має бути 0%»). [БЕКЕНД]: уточнити в
  /// Попова, звідки cash_uft.dll бере групу/ставку товару для бойових РРО.
  static double? medicineTaxPrc;
  static double? generalTaxPrc;

  /// Хост хмарного кабінету (для read-only перегляду каси).
  static const cabinetHost = 'https://test.cashdesk.com.ua';

  /// ⚠️ Mock-режим: повертати синтетичний успіх замість реального API.
  /// `false` — реальна фіскалізація через cloud test API. Підтверджено
  /// 2026-05-12 на ФН 4000952779 (sale uuid=7ecd45bb…, ORDERNUM=IIh3g-eh-Ak).
  static const useMockSuccess = false;
}

/// Тип помилки ПРРО — щоб виклик міг розрізнити мережеву проблему
/// (відкласти у чергу) і логічну помилку (заблокувати продаж).
enum PrroErrorKind {
  /// Помилка мережі / SmartConnect не запущений / timeout — кандидат на чергу.
  connection,

  /// Логічна помилка від API (некоректні дані, відмова податкової тощо).
  logical,

  /// Помилка авторизації — токен невалідний.
  auth,
}


/// Результат Z-звіту за період: або сам звіт, або причина, чому його немає.
///
/// Раніше метод повертав просто `null`, і фармацевт бачив вигадане «ПРРО зараз
/// недоступний» — навіть коли ПРРО відповів і чітко назвав причину
/// («Присутні невигружені чеки за вказаний період», 04.09.2026). З таким
/// формулюванням людина принаймні знає, кому дзвонити.
class PrroPeriodResult {
  final PrroXReport? report;

  /// Готовий до показу рядок або `null`, якщо все добре.
  final String? issue;

  const PrroPeriodResult.ok(PrroXReport this.report) : issue = null;
  const PrroPeriodResult.failed(String this.issue) : report = null;

  bool get isOk => report != null;
}

/// Результат операції ПРРО.
class PrroResult {
  final bool success;
  final String? checkId;      // UUID чеку (uuid)
  final String? orderNum;     // Номер чеку (ORDERNUM)
  final String? orderDate;    // Дата чеку (ORDERDATE)
  final String? orderTime;    // Час чеку (ORDERTIME)
  final String? qrData;       // URL для QR-коду
  final String? qrBase64;     // QR-код як base64 PNG
  final String? textPrint;    // Текстове представлення чеку (base64)
  final String? pdfBase64;    // PDF чеку (base64)
  final String? link;         // Посилання на чек на сайті
  final bool isOffline;       // Ознака офлайн чеку
  /// Гроші в касі — присутнє у відповіді Z-звіту (`cash_in_box`). На момент Z =
  /// готівка в касі по ФН.
  ///
  /// ⚠️ Це НЕ розмінна монета. Андрій Попов, 31.08: «якщо не буде проведено
  /// винос грошей, то це внос вранці залишку + реалізація за поточну зміну».
  /// Виміряно й на нашій касі — пропозиція росла рівно на готівкову виручку.
  final double? cashInBox;

  final String? error;
  final PrroErrorKind? errorKind;

  /// Чек НЕ створювався цим викликом, а знайдений у зміні за `local_number`
  /// після обриву зв'язку (A1, ідемпотентність). Успіх, але без QR/PDF/лінка —
  /// X-звіт віддає лише номер, час і суму.
  final bool recovered;

  const PrroResult({
    required this.success,
    this.checkId,
    this.orderNum,
    this.orderDate,
    this.orderTime,
    this.qrData,
    this.qrBase64,
    this.textPrint,
    this.pdfBase64,
    this.link,
    this.isOffline = false,
    this.cashInBox,
    this.error,
    this.errorKind,
    this.recovered = false,
  });

  const PrroResult.failure({
    required String this.error,
    required PrroErrorKind this.errorKind,
  })  : success = false,
        checkId = null,
        orderNum = null,
        orderDate = null,
        orderTime = null,
        qrData = null,
        qrBase64 = null,
        textPrint = null,
        pdfBase64 = null,
        link = null,
        isOffline = false,
        cashInBox = null,
        recovered = false;
}

/// Товар для фіскального чеку.
class PrroProduct {
  final String name;
  final double amount;
  final double price;
  final double cost;          // amount * price (з урахуванням знижки)
  final String? code;         // внутрішній код товару
  final String? barcode;      // штрихкод
  /// Податкова група. Поле опціональне — без нього ПРРО рахує податок з [taxPrc].
  /// УВАГА: формат значення НЕ зрозумілий з документації; cloud test API
  /// відхиляє літери 'А'/'В'/'Б'/'B'/'A' з помилкою "invalid". Поки
  /// безпечніше залишати null.
  final String? letters;

  /// Ставка податку. null → поле `tax_prc` НЕ шлеться = «Без ПДВ».
  /// Податкові групи — властивість реєстрації конкретного РРО в ДПС:
  /// тестовий 4000952779 (АВІС-ФАРМА) має ЛИШЕ «БЕЗ ПДВ», SmartConnect
  /// відхиляв хардкод 7% («Податок "БЕЗ ПДВ" має бути 0%»). Ставки для
  /// бойових РРО — з [PrroConfig.medicineTaxPrc]/[PrroConfig.generalTaxPrc].
  final double? taxPrc;
  final String unitName;      // одиниця виміру
  final String? unitCode;     // код одиниці виміру (КСПОВО)
  final double? discount;     // сума знижки

  const PrroProduct({
    required this.name,
    required this.amount,
    required this.price,
    required this.cost,
    this.code,
    this.barcode,
    this.letters,
    this.taxPrc,
    this.unitName = 'штука',
    this.unitCode = '2009',
    this.discount,
  });

  /// Створити з ознакою "лікарський засіб". Автоматично проставляє ставку.
  factory PrroProduct.classified({
    required String name,
    required double amount,
    required double price,
    required double cost,
    required bool isMedicine,
    String? code,
    String? barcode,
    String unitName = 'штука',
    String? unitCode = '2009',
    double? discount,
  }) {
    return PrroProduct(
      name: name,
      amount: amount,
      price: price,
      cost: cost,
      code: code,
      barcode: barcode,
      taxPrc: isMedicine
          ? PrroConfig.medicineTaxPrc
          : PrroConfig.generalTaxPrc,
      unitName: unitName,
      unitCode: unitCode,
      discount: discount,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'price': price,
    'cost': cost,
    if (code != null) 'code': code,
    if (barcode != null) 'bar_code': barcode,
    if (letters != null) 'letters': letters,
    if (taxPrc != null) 'tax_prc': taxPrc,
    'unit_name': unitName,
    if (unitCode != null) 'unit_code': unitCode,
    if (discount != null && discount! > 0) 'sum_discount': discount,
  };
}

/// Оплата для фіскального чеку.
class PrroPayment {
  final int code;             // 0 = готівка, 1 = картка
  final String name;
  final double sum;
  final double sumProvided;   // скільки надав клієнт
  final double sumRemains;    // здача

  const PrroPayment({
    required this.code,
    required this.name,
    required this.sum,
    required this.sumProvided,
    this.sumRemains = 0,
  });

  /// Готівка.
  factory PrroPayment.cash({
    required double sum,
    double? provided,
  }) {
    final p = provided ?? sum;
    return PrroPayment(
      code: 0,
      name: 'ГОТІВКА',
      sum: sum,
      sumProvided: p,
      sumRemains: (p - sum).clamp(0, double.infinity),
    );
  }

  /// Картка.
  factory PrroPayment.card({required double sum}) {
    return PrroPayment(
      code: 1,
      name: 'КАРТКА',
      sum: sum,
      sumProvided: sum,
      sumRemains: 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'sum': sum,
    'sum_provided': sumProvided,
    'sum_remains': sumRemains,
  };
}

/// ⚠️ Числа з ПРРО читаються ТІЛЬКИ через `flexDouble`/`flexInt`
/// (`utils/json_num.dart`): каса віддає `local_number` у `checks_list` РЯДКОМ
/// (`"2900661785"`), хоч `sum` там числом. Жорсткий каст `as num?` кидав
/// `type 'String' is not a subtype of type 'num?'` і валив розбір УСЬОГО
/// X-звіту — разом зі звіркою дублікатів A1, яка через це мовчки не працювала
/// (спіймано на касі 1334, 2026-08-26).
///
/// Чек у списку зміни (елемент `checks_list` з X-звіту).
class PrroShiftCheck {
  final String type;          // "Z_SALE", "Z_RETURN" тощо
  final String orderNum;      // фіскальний номер
  final String? datetime;     // "DD.MM.YYYY HH:MM:SS"
  final int? localNumber;     // наш номер з Caché
  final double sum;

  const PrroShiftCheck({
    required this.type,
    required this.orderNum,
    required this.sum,
    this.datetime,
    this.localNumber,
  });

  factory PrroShiftCheck.fromJson(Map<String, dynamic> json) => PrroShiftCheck(
        // ⚠️ Ключ саме `type_`, з підкресленням — так віддає CashDesk
        // (payload від Андрія Попова, 01.09). Ми читали `type`, і поле було
        // ЗАВЖДИ порожнім. Наслідок був не косметичний: у `matchCheck` умова
        // `type.contains('RETURN') != isReturn` для повернень завжди давала
        // `continue`, тобто звірка дублів A1 для ПОВЕРНЕНЬ не працювала
        // взагалі. `type` лишаємо запасним варіантом.
        type: (json['type_'] ?? json['type'])?.toString() ?? '',
        orderNum: json['order_num']?.toString() ?? '',
        datetime: json['datetime']?.toString(),
        localNumber: flexInt(json['local_number']),
        sum: flexDouble(json['sum']) ?? 0,
      );
}

/// Результат X-звіту (поточний стан зміни без закриття).
class PrroXReport {
  final bool shiftOpen;
  final int? shiftDurationMinutes;

  /// Час відкриття зміни — з `from_date` (shift_duration каса віддає 0, тож
  /// саме це поле використовуємо для розрізнення сьогодні/вчора).
  final DateTime? openedAt;
  final double cashInBox;

  /// Готівка на початок зміни (розмінна монета/службове внесення) — з CashDesk
  /// `cash_in_box_start`. Саме звідси має братись пропонована сума внесення.
  final double cashInBoxStart;

  /// Сума службових внесень за зміну — CashDesk `service_input`.
  final double serviceInput;

  /// Службова видача (інкасація). У звичайному Z-звіті цього поля НЕМАЄ
  /// (перевірено 31.08 і 01.09), а Z ЗА ПЕРІОД його віддає — саме за ним
  /// видно, чи робили інкасацію.
  final double serviceOutput;

  final int ordersCount;
  final double ordersSum;
  final List<PrroShiftCheck> checks;
  final String? pdfBase64;
  final String? textPrint;

  const PrroXReport({
    required this.shiftOpen,
    required this.cashInBox,
    required this.ordersCount,
    required this.ordersSum,
    required this.checks,
    this.cashInBoxStart = 0,
    this.serviceInput = 0,
    this.serviceOutput = 0,
    this.shiftDurationMinutes,
    this.openedAt,
    this.pdfBase64,
    this.textPrint,
  });

  /// Терпиме до формату: bool `true`, `1`, `"1"`, `"true"` → true.
  static bool _truthy(dynamic v) =>
      v == true ||
      v == 1 ||
      (v is String && (v == '1' || v.toLowerCase() == 'true'));

  /// Терпимий парсер дати: ISO або `DD.MM.YYYY[ HH:MM[:SS]]`. null якщо не вийшло.
  static DateTime? parseDate(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (iso != null) return iso;
    final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?')
        .firstMatch(s);
    if (m != null) {
      return DateTime(
        int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!),
        int.parse(m[4] ?? '0'), int.parse(m[5] ?? '0'), int.parse(m[6] ?? '0'),
      );
    }
    return null;
  }

  factory PrroXReport.fromJson(Map<String, dynamic> json) {
    final real = json['real'] as Map<String, dynamic>? ?? const {};
    final list = (json['checks_list'] as List?) ?? const [];
    return PrroXReport(
      shiftOpen: _truthy(json['shift_state']),
      // Числа — через терпимі парсери: каса подекуди віддає їх рядками, а один
      // жорсткий каст валить розбір усієї відповіді (див. utils/json_num.dart).
      cashInBox: flexDouble(json['cash_in_box']) ?? 0,
      cashInBoxStart: flexDouble(json['cash_in_box_start']) ?? 0,
      serviceInput: flexDouble(json['service_input']) ?? 0,
      serviceOutput: flexDouble(json['service_output']) ?? 0,
      shiftDurationMinutes: flexInt(json['shift_duration']),
      // Час відкриття: SmartConnect (прод) віддає його в OPEN_SESSION_TIME
      // (from_date порожній, shift_duration відсутній); cloud-test — у from_date.
      openedAt: parseDate(json['OPEN_SESSION_TIME']) ?? parseDate(json['from_date']),
      ordersCount: flexInt(real['orders_count']) ?? 0,
      ordersSum: flexDouble(real['sum']) ?? 0,
      checks: list
          .whereType<Map<String, dynamic>>()
          .map(PrroShiftCheck.fromJson)
          .toList(growable: false),
      pdfBase64: json['pdf']?.toString(),
      textPrint: json['text_print']?.toString(),
    );
  }
}

/// Сервіс ПРРО (програмний реєстратор розрахункових операцій).
///
/// API: CashDesk (cashdesk.com.ua)
/// Документація: https://documenter.getpostman.com/view/12128952/TVRj5U1d
class PrroService {
  static final _client = http.Client();
  static String? _token;
  static DateTime? _tokenExpiresAt;
  /// Активний фіскальний номер — ЗАВЖДИ з конфігу (реєстр `ekkPort` / дефолт).
  /// НЕ брати з `opened_shift` відповіді authenticate: обліковка бачить кілька
  /// РРО, і там приходить ФН каси з відкритою зміною БУДЬ-ЯКОЇ з них (на
  /// SmartConnect прилетів чужий 4000952775 → OPEN_SHIFT падав). На cloud test
  /// збігалось випадково, тому баг був невидимий.
  static int get activeFiscalNumber => PrroConfig.numFiscal;

  /// A5-гард: не дати створити фіскальний документ, коли ФН не з реєстру.
  ///
  /// Повертає `null`, якщо все гаразд; інакше — готову відмову. Тип помилки
  /// СВІДОМО `logical`, а не `connection`: чек має заблокувати продаж, а не
  /// лягти в offline-чергу й піти на тестовий ФН пізніше.
  ///
  /// Z-звіт навмисно НЕ гардимо: якщо зміна вже відкрита, її треба мати чим
  /// закрити, а Z нових грошових документів не створює.
  static PrroResult? _guardFiscalNumber(String operation) {
    if (PrroConfig.fiscalTrusted) return null;
    const msg = 'Фіскальний номер не налаштований у реєстрі каси '
        '(ZSMU\\Farm → ekkPort). Операцію заблоковано, щоб чек не пішов на '
        'тестовий ФН. Зверніться до адміністратора.';
    FiscalLog.log('A5 БЛОКУВАННЯ [$operation]: ФН не з реєстру, '
        'у бінарнику дефолт ${PrroConfig.numFiscal} — операцію відхилено');
    return const PrroResult.failure(
      error: msg,
      errorKind: PrroErrorKind.logical,
    );
  }

  static Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'developer-id': PrroConfig.developerId,
        // ignore: use_null_aware_elements
        if (_token != null) 'Authorization': _token!,
      };

  // ---------------------------------------------------------------------------
  // Token cache (file-based persistence через path_provider)
  // ---------------------------------------------------------------------------

  static const _tokenFileName = 'prro_token.json';

  static Future<File?> _tokenFile() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_tokenFileName');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persistToken() async {
    final file = await _tokenFile();
    if (file == null || _token == null) return;
    try {
      await file.writeAsString(jsonEncode({
        'token': _token,
        'expires_at': _tokenExpiresAt?.toIso8601String(),
        'fiscal': PrroConfig.numFiscal,
        'base_url': PrroConfig.baseUrl,
      }));
    } catch (e) {
      debugPrint('PRRO token persist FAIL: $e');
    }
  }

  /// Завантажити кешований токен. Викликати при старті.
  static Future<void> loadCachedToken() async {
    final file = await _tokenFile();
    if (file == null || !await file.exists()) return;
    try {
      final json = jsonDecode(await file.readAsString())
          as Map<String, dynamic>;
      // Інвалідувати кеш якщо змінили середовище/URL або фіскальний номер.
      if (json['base_url'] != PrroConfig.baseUrl) {
        debugPrint('PRRO token cache MISS: base_url mismatch');
        return;
      }
      final cachedFiscal = (json['fiscal'] as num?)?.toInt();
      if (cachedFiscal != PrroConfig.numFiscal) {
        debugPrint('PRRO token cache MISS: fiscal mismatch '
            '(cached=$cachedFiscal, config=${PrroConfig.numFiscal})');
        return;
      }
      final expiresStr = json['expires_at']?.toString();
      final expires = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
      if (expires != null && expires.isBefore(DateTime.now())) return;
      _token = json['token']?.toString();
      _tokenExpiresAt = expires;
      debugPrint('PRRO token cache HIT: fiscal=$cachedFiscal expires=$expires');
    } catch (e) {
      debugPrint('PRRO token cache FAIL: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Авторизація
  // ---------------------------------------------------------------------------

  /// Авторизуватися в ПРРО. Отримує Bearer token + opened_shift.
  ///
  /// УВАГА (Попов): у SmartConnect `/authenticate` має НАЙНИЖЧИЙ пріоритет —
  /// у рознині великий шанс таймауту. Тому основний шлях — bearer з реєстру
  /// (див. [_ensureAuth]); сюди потрапляємо лише коли він відсутній/прострочений.
  /// Таймаут 60 с (більше за 30 с cash_uft.dll — саме через низький пріоритет).
  static Future<bool> authenticate() async {
    try {
      final response = await _client.post(
        Uri.parse('${PrroConfig.baseUrl}/authenticate'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'developer-id': PrroConfig.developerId,
        },
        body: jsonEncode({
          'email': PrroConfig.email,
          'password': PrroConfig.password,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        debugPrint('PRRO auth FAIL: HTTP ${response.statusCode}');
        return false;
      }

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      _token = json['token']?.toString();
      _tokenExpiresAt = _parseExpiresAt(json['token_expires_at']?.toString());
      // `opened_shift` НЕ використовуємо як активний ФН (чужий РРО тієї ж
      // обліковки; див. activeFiscalNumber) — лише в лог для діагностики.
      debugPrint('PRRO auth OK: opened_shift=${json['opened_shift']} '
          '(активний ФН=${PrroConfig.numFiscal}) expires=$_tokenExpiresAt');
      if (_token != null) {
        await _persistToken();
        // Оновлений токен — назад у реєстр (`bearer`), як робить cash_uft.dll:
        // з ним працюють і наступні запуски, і legacy-модуль.
        final t = _token!;
        PrroConfig.persistBearerToRegistry
            ?.call(t.startsWith('Bearer') ? t : 'Bearer $t');
      }
      return _token != null;
    } catch (e) {
      debugPrint('PRRO auth ERROR: $e');
      return false;
    }
  }

  /// "06.05.2027 09:16" → DateTime
  static DateTime? _parseExpiresAt(String? s) {
    if (s == null) return null;
    final parts = s.split(' ');
    if (parts.length != 2) return null;
    final d = parts[0].split('.');
    final t = parts[1].split(':');
    if (d.length != 3 || t.length < 2) return null;
    return DateTime.tryParse(
      '${d[2]}-${d[1].padLeft(2, '0')}-${d[0].padLeft(2, '0')}'
      'T${t[0].padLeft(2, '0')}:${t[1].padLeft(2, '0')}:00',
    );
  }

  /// `exp` з payload JWT (unix seconds) → DateTime. null — не розпарсилось.
  static DateTime? _jwtExpiry(String bearer) {
    try {
      final parts = bearer.replaceFirst('Bearer ', '').trim().split('.');
      if (parts.length < 2) return null;
      final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
      final exp = (payload['exp'] as num?)?.toDouble();
      if (exp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch((exp * 1000).round());
    } catch (_) {
      return null;
    }
  }

  static bool _registryBearerTried = false;

  /// Гарантувати, що токен валідний. Пріоритет: чинний токен → bearer з
  /// реєстру (`ZSMU\Farm\bearer`, живе ~365 днів) → authenticate
  /// (edVerMini/edPassMini), новий токен пишеться назад у реєстр.
  static Future<bool> _ensureAuth() async {
    if (_token != null &&
        (_tokenExpiresAt == null ||
            _tokenExpiresAt!.isAfter(DateTime.now().add(const Duration(minutes: 5))))) {
      return true;
    }
    if (!_registryBearerTried) {
      _registryBearerTried = true;
      final b = PrroConfig.registryBearer;
      if (b != null) {
        final exp = _jwtExpiry(b);
        if (exp != null &&
            exp.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
          _token = b;
          _tokenExpiresAt = exp;
          debugPrint('PRRO: bearer з реєстру, діє до $exp');
          return true;
        }
        debugPrint('PRRO: bearer з реєстру прострочений/битий (exp=$exp) — '
            'authenticate');
      }
    }
    final ok = await authenticate();
    if (!ok) FiscalLog.log('ПРРО: authenticate НЕ вдалась');
    return ok;
  }

  // ---------------------------------------------------------------------------
  // Чек продажу
  // ---------------------------------------------------------------------------

  /// Створити фіскальний чек продажу.
  ///
  /// [products] — список товарів
  /// [payments] — список оплат (готівка/картка)
  /// [totalSum] — загальна сума чеку
  /// [localNumber] — внутрішній номер чеку з Caché (Compass).
  ///   TODO: коли буде реалізовано sgVRoznSale — підмінити timestamp-заглушку
  ///   на реальний номер з відповіді Caché.
  static Future<PrroResult> createSaleReceipt({
    required List<PrroProduct> products,
    required List<PrroPayment> payments,
    required double totalSum,
    double roundSum = 0,
    int? localNumber,
  }) async {
    if (PrroConfig.useMockSuccess) {
      return _mockSaleSuccess(
        products: products,
        payments: payments,
        totalSum: totalSum,
        localNumber: localNumber,
      );
    }

    final blocked = _guardFiscalNumber('SALE');
    if (blocked != null) return blocked;

    if (!await _ensureAuth()) {
      return const PrroResult.failure(
        error: 'Помилка авторизації ПРРО',
        errorKind: PrroErrorKind.auth,
      );
    }

    try {
      final body = <String, dynamic>{
        'num_fiscal': activeFiscalNumber,
        'action_type': 'Z_SALE',
        // Готівка округлюється до 10 коп (НБУ): total_sum = ОКРУГЛЕНА сума,
        // round_sum = різниця з сумою позицій. SmartConnect звіряє сам і
        // відхиляє чек, якщо total_sum не збігається з очікуваним округленням.
        'total_sum': totalSum,
        'round_rule': 10,
        'round_sum': roundSum,
        'products': products.map((p) => p.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'no_pdf': false, // PDF чека для архіву receipts/
        'no_qr': false,
        'no_text_print': false,
        // ignore: use_null_aware_elements
        if (localNumber != null) 'local_number': localNumber,
      };

      debugPrint('PRRO sale: ${products.length} products, total=$totalSum, '
          'localNumber=$localNumber');

      final response = await _client.post(
        Uri.parse('${PrroConfig.baseUrl}/check/sale'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = PrroResult(
          success: true,
          checkId: json['uuid']?.toString(),
          orderNum: json['ORDERNUM']?.toString() ?? json['order_num']?.toString(),
          orderDate: json['ORDERDATE']?.toString(),
          orderTime: json['ORDERTIME']?.toString(),
          qrData: json['qr_data']?.toString(),
          qrBase64: json['qr']?.toString(),
          textPrint: json['text_print']?.toString(),
          pdfBase64: json['pdf']?.toString(),
          link: json['link']?.toString(),
          isOffline: json['is_offline'] == true,
        );
        debugPrint('PRRO sale OK: orderNum=${result.orderNum} '
            'checkId=${result.checkId} link=${result.link} '
            'offline=${result.isOffline}');
        return result;
      } else {
        final error = json['message']?.toString() ??
            'Помилка ПРРО (${response.statusCode})';
        debugPrint('PRRO sale FAIL: $error data=$json');
        // 401 → токен прострочений, треба повторно авторизуватись.
        return PrroResult.failure(
          error: error,
          errorKind: response.statusCode == 401
              ? PrroErrorKind.auth
              : PrroErrorKind.logical,
        );
      }
    } on TimeoutException {
      debugPrint('PRRO sale TIMEOUT');
      // A1: таймаут ≠ «чек не створено» — спершу перевіряємо зміну.
      return _recoverFromConnectionError(
        localNumber: localNumber,
        isReturn: false,
        failure: const PrroResult.failure(
          error: 'Таймаут з\'єднання з ПРРО',
          errorKind: PrroErrorKind.connection,
        ),
      );
    } on SocketException catch (e) {
      debugPrint('PRRO sale SOCKET: $e');
      return _recoverFromConnectionError(
        localNumber: localNumber,
        isReturn: false,
        failure: const PrroResult.failure(
          error: 'Немає з\'єднання з ПРРО',
          errorKind: PrroErrorKind.connection,
        ),
      );
    } catch (e) {
      debugPrint('PRRO sale ERROR: $e');
      return PrroResult.failure(
        error: 'Помилка ПРРО: $e',
        errorKind: PrroErrorKind.logical,
      );
    }
  }

  /// Створити фіскальний чек із ГОТОВИХ products/payments від `GetDataRRO`
  /// (сирий проброс). Caché уже проставив tax_prc/letters/cost/sum_discount і
  /// округлив payments.sum → БЕЗ `round_rule`/`round_sum` і без клієнтських
  /// розрахунків. [totalSum] = Σ payments[].sum.
  static Future<PrroResult> createSaleReceiptRaw({
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> payments,
    required double totalSum,
    int? localNumber,
    bool isReturn = false,
    String? comment,
  }) async {
    final blocked = _guardFiscalNumber(isReturn ? 'RETURN(raw)' : 'SALE(raw)');
    if (blocked != null) return blocked;

    if (!await _ensureAuth()) {
      return const PrroResult.failure(
        error: 'Помилка авторизації ПРРО',
        errorKind: PrroErrorKind.auth,
      );
    }
    try {
      final body = <String, dynamic>{
        'num_fiscal': activeFiscalNumber,
        'action_type': isReturn ? 'Z_RETURN' : 'Z_SALE',
        'total_sum': totalSum,
        'products': products,
        'payments': payments,
        'no_pdf': false, // PDF чека для архіву receipts/
        'no_qr': false,
        'no_text_print': false,
        // Коментар (блок «ПРОГРАМА ЛОЯЛЬНОСТI») друкується в чеку. ⚠️ Назва
        // поля НЕ підтверджена (пробуємо `footer`) — звірити з Андрієм на тесті.
        if (comment != null && comment.isNotEmpty) 'footer': comment,
        // ignore: use_null_aware_elements
        if (localNumber != null) 'local_number': localNumber,
      };
      debugPrint('PRRO sale(raw): ${products.length} products, total=$totalSum, '
          'localNumber=$localNumber');

      final response = await _client.post(
        Uri.parse('${PrroConfig.baseUrl}/check/sale'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final respBody = utf8.decode(response.bodyBytes);
      // На помилку — лог request (products із letters/tax_prc) + відповідь,
      // щоб діагностувати податкові групи (base64 qr/pdf в успіху не логуємо).
      if (response.statusCode != 200 && response.statusCode != 201) {
        FiscalLog.log('check/sale FAIL ${response.statusCode}\n'
            'products=${jsonEncode(products)}\nresp=$respBody');
      }
      final decoded = jsonDecode(respBody);
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = PrroResult(
          success: true,
          checkId: json['uuid']?.toString(),
          orderNum: json['ORDERNUM']?.toString() ?? json['order_num']?.toString(),
          orderDate: json['ORDERDATE']?.toString(),
          orderTime: json['ORDERTIME']?.toString(),
          qrData: json['qr_data']?.toString(),
          qrBase64: json['qr']?.toString(),
          textPrint: json['text_print']?.toString(),
          pdfBase64: json['pdf']?.toString(),
          link: json['link']?.toString(),
          isOffline: json['is_offline'] == true,
        );
        debugPrint('PRRO sale(raw) OK: orderNum=${result.orderNum} '
            'link=${result.link} offline=${result.isOffline}');
        return result;
      }
      final error = json['message']?.toString() ??
          'Помилка ПРРО (${response.statusCode})';
      debugPrint('PRRO sale(raw) FAIL: $error data=$json');
      return PrroResult.failure(
        error: error,
        errorKind: response.statusCode == 401
            ? PrroErrorKind.auth
            : PrroErrorKind.logical,
      );
    } on TimeoutException {
      // A1: чек міг зареєструватись уже після нашого таймауту.
      return _recoverFromConnectionError(
        localNumber: localNumber,
        isReturn: isReturn,
        failure: const PrroResult.failure(
          error: 'Таймаут з\'єднання з ПРРО',
          errorKind: PrroErrorKind.connection,
        ),
      );
    } on SocketException {
      return _recoverFromConnectionError(
        localNumber: localNumber,
        isReturn: isReturn,
        failure: const PrroResult.failure(
          error: 'Немає з\'єднання з ПРРО',
          errorKind: PrroErrorKind.connection,
        ),
      );
    } catch (e) {
      debugPrint('PRRO sale(raw) ERROR: $e');
      return PrroResult.failure(
        error: 'Помилка ПРРО: $e',
        errorKind: PrroErrorKind.logical,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Чек повернення
  // ---------------------------------------------------------------------------

  /// Створити фіскальний чек повернення.
  static Future<PrroResult> createReturnReceipt({
    required List<PrroProduct> products,
    required List<PrroPayment> payments,
    required double totalSum,
    int? localNumber,
  }) async {
    if (PrroConfig.useMockSuccess) {
      return _mockSaleSuccess(
        products: products,
        payments: payments,
        totalSum: totalSum,
        localNumber: localNumber,
        isReturn: true,
      );
    }

    final blocked = _guardFiscalNumber('RETURN');
    if (blocked != null) return blocked;

    if (!await _ensureAuth()) {
      return const PrroResult.failure(
        error: 'Помилка авторизації ПРРО',
        errorKind: PrroErrorKind.auth,
      );
    }

    try {
      final body = <String, dynamic>{
        'num_fiscal': activeFiscalNumber,
        'action_type': 'Z_RETURN',
        'total_sum': totalSum,
        'products': products.map((p) => p.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'no_pdf': false, // PDF чека для архіву receipts/
        'no_qr': false,
        'no_text_print': false,
        // ignore: use_null_aware_elements
        if (localNumber != null) 'local_number': localNumber,
      };

      final response = await _client.post(
        Uri.parse('${PrroConfig.baseUrl}/check/sale'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        final checkId = json['uuid']?.toString() ?? json['id']?.toString();
        debugPrint('PRRO return OK: checkId=$checkId');
        return PrroResult(success: true, checkId: checkId);
      } else {
        final error = json['message']?.toString() ?? 'Помилка ПРРО';
        return PrroResult.failure(
          error: error,
          errorKind: response.statusCode == 401
              ? PrroErrorKind.auth
              : PrroErrorKind.logical,
        );
      }
    } on TimeoutException {
      // A1: повернення теж не можна проводити двічі.
      return _recoverFromConnectionError(
        localNumber: localNumber,
        isReturn: true,
        failure: const PrroResult.failure(
          error: 'Таймаут з\'єднання з ПРРО',
          errorKind: PrroErrorKind.connection,
        ),
      );
    } on SocketException {
      return _recoverFromConnectionError(
        localNumber: localNumber,
        isReturn: true,
        failure: const PrroResult.failure(
          error: 'Немає з\'єднання з ПРРО',
          errorKind: PrroErrorKind.connection,
        ),
      );
    } catch (e) {
      debugPrint('PRRO return ERROR: $e');
      return PrroResult.failure(
        error: 'Помилка ПРРО: $e',
        errorKind: PrroErrorKind.logical,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Z-звіт за період
  // ---------------------------------------------------------------------------

  static String _dmy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Z-звіт ЗА ПЕРІОД — `POST /shift/zReport/period` (Андрій Попов, 03.09).
  ///
  /// Читаючий запит: це дані вже зареєстрованих у податковій Z-звітів, тож
  /// безпечний і повторюваний. Дає те, чого X-звіт не вміє — він бачить лише
  /// ПОТОЧНУ зміну:
  ///   • `cash_in_box` — кінцевий залишок у касі на кінець періоду;
  ///   • `service_input`/`service_output` — внесення й видача (інкасація);
  ///   • `checks_list` — усі фіскальні операції періоду, у порядку реєстрації.
  ///
  /// Дві умови від Андрія: потрібен інтернет (запит іде в особистий кабінет)
  /// і сам Z має встигнути зареєструватися, а не чекати в черзі за офлайн-
  /// чеками. Тому це збагачення, а не залежність: виклик може повернути `null`,
  /// і кожен виклик має мати запасний шлях.
  static Future<PrroPeriodResult> zReportPeriod({
    required DateTime from,
    required DateTime to,
    bool includeChecks = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!await _ensureAuth()) {
      return const PrroPeriodResult.failed('ПРРО не авторизований');
    }
    try {
      // developer-id — ЛИШЕ в заголовках (`_headers`). Дублювання в тілі
      // SmartConnect відхиляє з HTTP 400, на цьому вже горів xReport.
      final body = {
        'num_fiscal': activeFiscalNumber.toString(),
        'print_width': PrroConfig.printWidth,
        'pdf_width': PrroConfig.pdfWidth,
        'from': _dmy(from),
        'to': _dmy(to),
        'include_checks': includeChecks,
      };
      final response = await _client
          .post(
            Uri.parse('${PrroConfig.baseUrl}/shift/zReport/period'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        final text = utf8.decode(response.bodyBytes);
        FiscalLog.log('zReport/period FAIL: HTTP ${response.statusCode} '
            '${text.substring(0, text.length.clamp(0, 120))}');
        return PrroPeriodResult.failed(explainPrroBody(text));
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const PrroPeriodResult.failed('ПРРО повернув несподівану відповідь');
      }
      final report = PrroXReport.fromJson(decoded);
      FiscalLog.log('zReport/period ${_dmy(from)}–${_dmy(to)}: '
          'кінцевий залишок ${report.cashInBox}, '
          'внесення ${report.serviceInput}, видача ${report.serviceOutput}'
          '${includeChecks ? ", операцій ${report.checks.length}" : ""}');
      return PrroPeriodResult.ok(report);
    } on TimeoutException {
      FiscalLog.log('zReport/period: таймаут');
      return const PrroPeriodResult.failed('ПРРО не відповів вчасно');
    } catch (e) {
      FiscalLog.log('zReport/period ERROR: $e');
      return const PrroPeriodResult.failed('Немає звʼязку з ПРРО');
    }
  }

  /// Витягти людську причину з тіла помилки SmartConnect.
  ///
  /// Формат — `{"message":"…","type":"WARNING"}`; саме так 04.09.2026 прийшло
  /// «Присутні невигружені чеки за вказаний період». Якщо тіло не таке —
  /// віддаємо його вкорочене: будь-який текст від ПРРО кориснішій за наше
  /// припущення про недоступність.
  @visibleForTesting
  static String explainPrroBody(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final msg = j['message']?.toString().trim() ?? '';
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {
      // Не JSON — нижче віддамо як є.
    }
    final t = body.trim();
    if (t.isEmpty) return 'ПРРО відповів помилкою без пояснення';
    return t.length <= 160 ? t : '${t.substring(0, 160)}…';
  }

  // ---------------------------------------------------------------------------
  // X-звіт
  // ---------------------------------------------------------------------------

  /// X-звіт: поточний стан зміни без закриття.
  /// [includeChecks] — включати список чеків зміни.
  /// [timeout] — 30 с як у cash_uft.dll; коротший беруть перевірки дублікатів
  /// (A1), де касир уже й так відчекав таймаут продажу.
  static Future<PrroXReport?> xReport({
    bool includeChecks = true,
    int? printWidth,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!await _ensureAuth()) return null;

    try {
      // developer-id — ЛИШЕ в заголовках (_headers). Дублювання його ще й у
      // тілі → SmartConnect відхиляє з HTTP 400 «Присутній дублікат поля
      // developer-id» (через це xReport завжди падав: готівка в касі = 0,
      // Z-діалог при виході не показувався, стан зміни не відновлювався).
      final body = {
        'num_fiscal': activeFiscalNumber.toString(),
        'print_width': printWidth ?? PrroConfig.printWidth,
        'pdf_width': printWidth ?? PrroConfig.pdfWidth,
        'include_checks': includeChecks,
      };

      // 30 с як у cash_uft.dll: реєстрація в податковій з АЦСК займає до 27 с,
      // і черга SmartConnect може тримати навіть читаючі запити.
      final response = await _client.post(
        Uri.parse('${PrroConfig.baseUrl}/shift/xReport'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(timeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        FiscalLog.log('xReport FAIL: HTTP ${response.statusCode} '
            '${utf8.decode(response.bodyBytes).substring(0,
                utf8.decode(response.bodyBytes).length.clamp(0, 120))}');
        return null;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final report = PrroXReport.fromJson(decoded);
      // Діагностика A1: скільки чеків зміни несуть `local_number` — саме за ним
      // відсікаються дублікати. Спрацьовує лише на шляхах A1 (перевірка після
      // обриву / flush черги), тому лог не засмічує. ✅ Підтверджено на касі
      // 1334 (2026-08-26): для Z_SALE каса повертає САМЕ наш номер (= NumNakl);
      // службові операції несуть власний лічильник каси (ми там номер не шлемо).
      if (includeChecks) {
        final withLocal =
            report.checks.where((c) => c.localNumber != null).length;
        FiscalLog.log('A1 діагностика: чеків у зміні=${report.checks.length}, '
            'з них з local_number=$withLocal');
      }
      debugPrint('PRRO xReport: shiftOpen=${report.shiftOpen} '
          'cashInBox=${report.cashInBox} cashInBoxStart=${report.cashInBoxStart} '
          'serviceInput=${report.serviceInput} openedAt=${report.openedAt}');
      return report;
    } catch (e) {
      FiscalLog.log('xReport ERROR: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // A1. Ідемпотентність: чи чек уже зареєстрований
  // ---------------------------------------------------------------------------

  /// Знайти в списку чеків зміни наш чек за `local_number`.
  ///
  /// Чистий матчер (без мережі) — винесений окремо, щоб покривався тестами.
  /// [isReturn] відсікає протилежний тип: продаж і повернення можуть нести той
  /// самий `local_number` накладної.
  static PrroShiftCheck? matchCheck(
    List<PrroShiftCheck> checks, {
    required int localNumber,
    bool isReturn = false,
  }) {
    for (final c in checks) {
      if (c.localNumber != localNumber) continue;
      if (c.type.toUpperCase().contains('RETURN') != isReturn) continue;
      return c;
    }
    return null;
  }

  /// Чи зареєстрований уже чек із таким [localNumber] у ПОТОЧНІЙ зміні.
  ///
  /// A1: таймаут ≠ «чек не створено» — SmartConnect міг прийняти його вже після
  /// того, як ми відвалились. Перед будь-якою повторною відправкою звіряємо
  /// `checks_list` X-звіту за нашим `local_number` (= NumNakl накладної).
  ///
  /// `null` = «не знайдено АБО не змогли перевірити» — свідомо не розрізняємо:
  /// обидва випадки ведуть до звичайного шляху (черга / повтор). Знайдений чек
  /// означає, що повтор робити НЕ можна.
  ///
  /// [attempts] > 1 має сенс одразу після таймауту: чек міг ще дореєстровуватись.
  /// ⚠️ Бачить лише поточну зміну: якщо між обривом і перевіркою пройшов Z-звіт,
  /// чек уже не в списку.
  static Future<PrroShiftCheck?> findRegisteredCheck({
    required int localNumber,
    bool isReturn = false,
    int attempts = 2,
    Duration retryDelay = const Duration(seconds: 3),
  }) async {
    for (var i = 0; i < attempts; i++) {
      if (i > 0) await Future.delayed(retryDelay);
      final report = await xReport(
        includeChecks: true,
        timeout: const Duration(seconds: 15),
      );
      // Зв'язку немає — нічого не стверджуємо, пробуємо ще раз.
      if (report == null) continue;

      final hit = matchCheck(report.checks,
          localNumber: localNumber, isReturn: isReturn);
      if (hit != null) return hit;

      // Каса взагалі не віддає local_number → звірка неможлива в принципі,
      // повторний запит нічого не змінить. Сигнал у лог, щоб побачити це на
      // касі, а не гадати, чому дублікати не відсікаються.
      if (report.checks.isNotEmpty &&
          report.checks.every((c) => c.localNumber == null)) {
        FiscalLog.log('⚠️ A1: xReport не віддає local_number '
            '(${report.checks.length} чеків у зміні) — перевірка дублікатів '
            'НЕМОЖЛИВА, чек піде звичайним шляхом');
        return null;
      }
    }
    return null;
  }

  /// Обробити обрив зв'язку: спершу перевірити, чи чек усе-таки зареєстровано.
  ///
  /// Знайшли → віддаємо УСПІХ із номером чека (`recovered: true`, без QR/PDF —
  /// X-звіт їх не містить). Не знайшли → вихідна помилка, далі як раніше
  /// (черга ПРРО).
  static Future<PrroResult> _recoverFromConnectionError({
    required int? localNumber,
    required bool isReturn,
    required PrroResult failure,
  }) async {
    if (localNumber == null) return failure;
    final hit = await findRegisteredCheck(
      localNumber: localNumber,
      isReturn: isReturn,
    );
    if (hit == null) return failure;

    FiscalLog.log('A1 ДУБЛЬ ВІДСІЧЕНО: чек local_number=$localNumber уже '
        'зареєстрований (№${hit.orderNum}, ${hit.datetime ?? "час невідомий"}, '
        'сума ${hit.sum}) — повторна фіскалізація НЕ виконується');

    final parts = (hit.datetime ?? '').split(' ');
    return PrroResult(
      success: true,
      orderNum: hit.orderNum,
      orderDate: parts.first.isNotEmpty ? parts.first : null,
      orderTime: parts.length > 1 ? parts[1] : null,
      recovered: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Z-звіт (закриття зміни)
  // ---------------------------------------------------------------------------

  /// Відкрити робочу зміну. Endpoint `POST /shift` з `action_type: OPEN_SHIFT`.
  static Future<PrroResult> openShift() async {
    // Зміну на чужому (тестовому) ФН відкривати не можна — з неї потім піде
    // весь день продажів.
    final blocked = _guardFiscalNumber('OPEN_SHIFT');
    if (blocked != null) return blocked;

    if (!await _ensureAuth()) {
      FiscalLog.log('OPEN_SHIFT: авторизація ПРРО не пройшла '
          '(ФН=$activeFiscalNumber, ${PrroConfig.baseUrl})');
      return const PrroResult.failure(
        error: 'Помилка авторизації ПРРО',
        errorKind: PrroErrorKind.auth,
      );
    }
    try {
      final body = {
        'action_type': 'OPEN_SHIFT',
        'num_fiscal': activeFiscalNumber,
      };
      final response = await _client
          .post(
            Uri.parse('${PrroConfig.baseUrl}/shift'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        FiscalLog.log('OPEN_SHIFT OK (ФН=$activeFiscalNumber)');
        return PrroResult(
          success: true,
          checkId: json['uuid']?.toString(),
          textPrint: json['text_print']?.toString(),
        );
      }
      // Причина відмови має бути видима в release (журнал), інакше на касі
      // видно лише «Не вдалося відкрити зміну» без жодної діагностики.
      final msg = json['message']?.toString() ?? 'Помилка відкриття зміни';
      FiscalLog.log('OPEN_SHIFT FAIL HTTP ${response.statusCode} '
          '(ФН=$activeFiscalNumber): $msg');
      return PrroResult.failure(
        error: msg,
        errorKind: PrroErrorKind.logical,
      );
    } on TimeoutException {
      FiscalLog.log('OPEN_SHIFT TIMEOUT (30с, ФН=$activeFiscalNumber)');
      return const PrroResult.failure(
        error: 'Таймаут відкриття зміни',
        errorKind: PrroErrorKind.connection,
      );
    } on SocketException catch (e) {
      FiscalLog.log('OPEN_SHIFT НЕМАЄ ЗВʼЯЗКУ з ${PrroConfig.baseUrl}: $e');
      return const PrroResult.failure(
        error: 'Немає з\'єднання з ПРРО',
        errorKind: PrroErrorKind.connection,
      );
    } catch (e) {
      debugPrint('PRRO openShift ERROR: $e');
      FiscalLog.log('OPEN_SHIFT ERROR: $e');
      return PrroResult.failure(
        error: 'Помилка відкриття зміни: $e',
        errorKind: PrroErrorKind.logical,
      );
    }
  }

  /// Службове внесення ([isInput] = true) / службова видача готівки.
  /// Endpoint `POST /check/service`, `action_type: SERVICE_INPUT|SERVICE_OUTPUT`
  /// (док. CashDesk). Саме ця операція наповнює `cash_in_box` у CashDesk —
  /// без неї розмінна монета/інкасація не видні в X/Z-звітах.
  static Future<PrroResult> serviceCash({
    required bool isInput,
    required double sum,
  }) async {
    final blocked =
        _guardFiscalNumber(isInput ? 'SERVICE_INPUT' : 'SERVICE_OUTPUT');
    if (blocked != null) return blocked;

    if (!await _ensureAuth()) {
      return const PrroResult.failure(
        error: 'Помилка авторизації ПРРО',
        errorKind: PrroErrorKind.auth,
      );
    }
    try {
      final body = {
        'action_type': isInput ? 'SERVICE_INPUT' : 'SERVICE_OUTPUT',
        'num_fiscal': activeFiscalNumber,
        'type': 0,
        'name': 'ГОТІВКА',
        'sum': sum,
        'no_pdf': false, // PDF чека для архіву receipts/
      };
      final response = await _client
          .post(
            Uri.parse('${PrroConfig.baseUrl}/check/service'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('PRRO serviceCash ${isInput ? 'INPUT' : 'OUTPUT'} $sum OK '
            '(uuid=${json['uuid']})');
        return PrroResult(success: true, checkId: json['uuid']?.toString());
      }
      return PrroResult.failure(
        error: json['message']?.toString() ?? 'Помилка службової операції',
        errorKind: response.statusCode == 401
            ? PrroErrorKind.auth
            : PrroErrorKind.logical,
      );
    } on TimeoutException {
      return const PrroResult.failure(
        error: 'Таймаут службової операції ПРРО',
        errorKind: PrroErrorKind.connection,
      );
    } on SocketException {
      return const PrroResult.failure(
        error: 'Немає з\'єднання з ПРРО',
        errorKind: PrroErrorKind.connection,
      );
    } catch (e) {
      debugPrint('PRRO serviceCash ERROR: $e');
      return PrroResult.failure(
        error: 'Помилка службової операції: $e',
        errorKind: PrroErrorKind.logical,
      );
    }
  }

  /// Z-звіт — закрити поточну зміну.
  /// Endpoint `POST /shift` з `action_type: Z_REPORT` (док. CashDesk).
  /// УВАГА: `/shift/xReport` — це X-звіт (НЕ закриває зміну), не плутати.
  static Future<PrroResult> zReport({int? printWidth}) async {
    if (!await _ensureAuth()) {
      return const PrroResult.failure(
        error: 'Помилка авторизації ПРРО',
        errorKind: PrroErrorKind.auth,
      );
    }

    try {
      final body = {
        'action_type': 'Z_REPORT',
        'num_fiscal': activeFiscalNumber,
        'print_width': printWidth ?? PrroConfig.printWidth,
        'pdf_width': printWidth ?? PrroConfig.pdfWidth,
      };

      final response = await _client.post(
        Uri.parse('${PrroConfig.baseUrl}/shift'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      if (response.statusCode == 200 || response.statusCode == 201) {
        return PrroResult(
          success: true,
          checkId: json['uuid']?.toString(),
          textPrint: json['text_print']?.toString(),
          pdfBase64: json['pdf']?.toString(),
          // Через flexDouble, а не жорсткий каст: каса подекуди віддає числа
          // рядками, і тоді `as num?` мовчки давав null — той самий клас бага,
          // що колись зламав розбір `local_number` у X-звіті.
          cashInBox: flexDouble(json['cash_in_box']),
        );
      } else {
        return PrroResult.failure(
          error: json['message']?.toString() ?? 'Помилка Z-звіту',
          errorKind: PrroErrorKind.logical,
        );
      }
    } on TimeoutException {
      return const PrroResult.failure(
        error: 'Таймаут Z-звіту',
        errorKind: PrroErrorKind.connection,
      );
    } on SocketException {
      return const PrroResult.failure(
        error: 'Немає з\'єднання з ПРРО',
        errorKind: PrroErrorKind.connection,
      );
    } catch (e) {
      debugPrint('PRRO zReport ERROR: $e');
      return PrroResult.failure(
        error: 'Помилка Z-звіту: $e',
        errorKind: PrroErrorKind.logical,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Отримання чеку
  // ---------------------------------------------------------------------------

  /// Отримати текстове представлення чеку.
  static Future<String?> getReceiptText(String checkId) async {
    try {
      final url = '${PrroConfig.baseUrl}'
          '/checks/$checkId/text?print_width=48';
      final response = await _client.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return utf8.decode(response.bodyBytes);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Отримати QR-код чеку як URL.
  static Future<String?> getReceiptQr(String checkId) async {
    try {
      final url = '${PrroConfig.baseUrl}'
          '/checks/$checkId/qr?ascii=1';
      final response = await _client.get(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return utf8.decode(response.bodyBytes);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Cabinet URL (read-only перегляд каси)
  // ---------------------------------------------------------------------------

  /// URL для відкриття поточної зміни в браузері без повторної авторизації.
  /// Email/password передаються у URL-safe base64.
  static String cabinetUrl({int? fiscalNumber}) {
    String b64(String s) => base64Url.encode(utf8.encode(s));
    return '${PrroConfig.cabinetHost}/authenticate'
        '?num_fiscal=${fiscalNumber ?? activeFiscalNumber}'
        '&email=${b64(PrroConfig.email)}'
        '&password=${b64(PrroConfig.password)}';
  }

  // ---------------------------------------------------------------------------
  // Mock success (для перевірки UI коли реальний ПРРО заблокований)
  // ---------------------------------------------------------------------------

  static PrroResult _mockSaleSuccess({
    required List<PrroProduct> products,
    required List<PrroPayment> payments,
    required double totalSum,
    int? localNumber,
    bool isReturn = false,
  }) {
    final now = DateTime.now();
    final orderNum = 'MOCK-${now.millisecondsSinceEpoch.toRadixString(36)}';
    final uuid = '${now.microsecondsSinceEpoch.toRadixString(16)}-mock';
    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final yyyy = now.year.toString();
    final hh = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');

    final lines = <String>[
      _center('ТЕСТОВИЙ ЧЕК (MOCK)'),
      _center('Аптека «Арніка»'),
      _center('м. Київ, вул. Тестова 1'),
      '',
      'ФН ПРРО:    ${PrroService.activeFiscalNumber}',
      'ID:         $uuid',
      'Дата/час:   $dd.$mm.$yyyy $hh:$mi:$ss',
      if (localNumber != null) 'Лок. номер: $localNumber',
      _hr(),
      isReturn ? _center('ПОВЕРНЕННЯ') : _center('ПРОДАЖ'),
      _hr(),
      ...products.expand(_formatProductLines),
      _hr(),
      _kv('РАЗОМ', _money(totalSum)),
      ...payments.map((p) => _kv(p.name, _money(p.sum))),
      _hr(),
      _center('Дякуємо за покупку!'),
      _center('Це не фіскальний документ'),
    ];
    final text = lines.join('\n');
    final textBase64 = base64Encode(utf8.encode(text));

    debugPrint('PRRO MOCK sale: orderNum=$orderNum total=$totalSum '
        '${isReturn ? "(return)" : "(sale)"}');

    return PrroResult(
      success: true,
      checkId: uuid,
      orderNum: orderNum,
      orderDate: '$dd.$mm.$yyyy',
      orderTime: '$hh:$mi:$ss',
      qrBase64: _mockQrPng,
      qrData: 'https://cabinet.tax.gov.ua/cashregs/check?id=$uuid',
      textPrint: textBase64,
      link: 'https://cabinet.tax.gov.ua/cashregs/check?id=$uuid',
      isOffline: false,
    );
  }

  static String _hr([int width = 40]) => '-' * width;

  static String _center(String s, [int width = 40]) {
    if (s.length >= width) return s;
    final pad = (width - s.length) ~/ 2;
    return ' ' * pad + s;
  }

  static String _kv(String k, String v, [int width = 40]) {
    final spaces = width - k.length - v.length;
    return spaces > 0 ? '$k${' ' * spaces}$v' : '$k $v';
  }

  static String _money(double v) =>
      v.asMoney;

  static List<String> _formatProductLines(PrroProduct p) {
    final qty = p.amount == p.amount.floorToDouble()
        ? p.amount.toInt().toString()
        : p.amount.toStringAsFixed(3);
    return [
      p.name.length > 40 ? p.name.substring(0, 40) : p.name,
      _kv('  $qty x ${_money(p.price)}', _money(p.cost)),
    ];
  }

  /// Мінімальний валідний 1×1 PNG (білий піксель) — placeholder для QR у mock-режимі.
  static const _mockQrPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=';
}
