import 'package:flutter/foundation.dart';
import '../data/mock_drugs.dart';
import '../models/drug.dart';
import 'api_config.dart';
import 'cache_api_client.dart';

/// Результат резервування залишку (sgVRoznSetLock).
class StockLockResult {
  final bool ok;              // сервер відповів
  final double grantedQty;    // фактично зарезервована кількість
  final String? cause;        // причина обмеження (рецептурний, заблокований тощо)
  final String? causeTitle;   // текст обмеження для відображення

  const StockLockResult({
    required this.ok,
    required this.grantedQty,
    this.cause,
    this.causeTitle,
  });

  /// Чи резервування повне (запитана кількість = отримана).
  bool isFullyGranted(double requested) => ok && grantedQty >= requested;
}

/// Дані про партію товару на складі (з GetSKUprice).
class StockBatch {
  final String skod;
  final String status;
  final int qty;
  final double price;

  StockBatch({
    required this.skod,
    required this.status,
    required this.qty,
    required this.price,
  });

  factory StockBatch.fromJson(Map<String, dynamic> json) {
    return StockBatch(
      skod: json['skod']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      qty: int.tryParse(json['qty']?.toString() ?? '0') ?? 0,
      price: double.tryParse(
            json['price']?.toString().replaceAll(',', '.') ?? '0',
          ) ??
          0.0,
    );
  }
}

/// Елемент результату пошуку за назвою (з SearchByName).
class DrugSearchItem {
  final String ids;         // s-код (унікальний код приходу)
  final String ukod;        // u-код (код товару в цілому, для GetSKUdetail)
  final String name;        // назва (оригінальна, зазвичай рос.)
  final String? nameUkr;    // назва українською (з NameUkr)
  final String manufacturer;
  final String shelf;
  final int qty;
  final double qtyRaw;   // реальний залишок з дробовою частиною
  final double price;
  final String? expiryDate;  // термін придатності
  final String? comingPrice; // ціна приходу (для FarmaSell)
  final String? comingCode;  // код приходу (для FarmaSell)
  final int? bonus;          // бонус фармацевту
  final bool isOwnBrand;     // СТМ
  final String? category;    // категорія
  final String? dosageForm;  // лікарська форма

  DrugSearchItem({
    required this.ids,
    this.ukod = '',
    required this.name,
    this.nameUkr,
    required this.manufacturer,
    required this.shelf,
    required this.qty,
    this.qtyRaw = 0,
    required this.price,
    this.expiryDate,
    this.comingPrice,
    this.comingCode,
    this.bonus,
    this.isOwnBrand = false,
    this.category,
    this.dosageForm,
  });

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString();
    return (s != null && s.isNotEmpty) ? s : null;
  }

  factory DrugSearchItem.fromJson(Map<String, dynamic> json) {
    return DrugSearchItem(
      ids: json['ids']?.toString() ?? '',
      ukod: json['ukod']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      nameUkr: _nonEmpty(json['nameukr'] ?? json['NameUkr']),
      manufacturer: (json['manufacturer'] ?? json['manufacture'])?.toString() ?? '',
      shelf: json['shelf']?.toString() ?? '',
      qty: (double.tryParse(
                json['qty']?.toString().replaceAll(',', '.') ?? '0',
              ) ?? 0.0)
              .floor(),
      qtyRaw: double.tryParse(
                json['qty']?.toString().replaceAll(',', '.') ?? '0',
              ) ?? 0.0,
      price: double.tryParse(
            json['price']?.toString().replaceAll(',', '.') ?? '0',
          ) ??
          0.0,
      expiryDate: _nonEmpty(json['expiryDate']),
      comingPrice: _nonEmpty(json['comingPrice']),
      comingCode: _nonEmpty(json['comingCode']),
      bonus: int.tryParse(json['bonus']?.toString() ?? ''),
      isOwnBrand: json['isOwnBrand']?.toString() == '1',
      category: _nonEmpty(json['category']),
      dosageForm: _nonEmpty(json['dosageForm']),
    );
  }
}

/// Результат пошуку товару (з GetSKU).
class DrugLookupResult {
  final bool found;
  final String? name;
  final String? nameUkr;
  final String? manufacturer;
  final String? shelf;
  final String? error;

  DrugLookupResult({
    required this.found,
    this.name,
    this.nameUkr,
    this.manufacturer,
    this.shelf,
    this.error,
  });
}

/// Результат запиту цін та залишків (з GetSKUprice).
class DrugPriceResult {
  final bool found;
  final String? name;
  final String? nameUkr;
  final String? manufacturer;
  final String? stelazh;
  final String? vitrina;
  final String? polka;
  final String? robot;
  final List<StockBatch> batches;
  final String? error;

  DrugPriceResult({
    required this.found,
    this.name,
    this.nameUkr,
    this.manufacturer,
    this.stelazh,
    this.vitrina,
    this.polka,
    this.robot,
    this.batches = const [],
    this.error,
  });

  /// Загальний залишок по всіх партіях.
  int get totalStock => batches.fold(0, (sum, b) => sum + b.qty);

  /// Роздрібна ціна (перша партія, або 0).
  double get retailPrice =>
      batches.isNotEmpty ? batches.first.price : 0.0;

  /// Чи є товар в наявності.
  bool get isAvailable => totalStock > 0;
}

/// Аналог товару від Caché (з GetAnalog).
class AnalogItem {
  final String ukod;          // u-код товару
  final String name;          // назва (оригінальна)
  final String? nameUkr;     // назва українською
  final String manufacturer;  // виробник
  final double price;         // ціна
  final int qty;              // залишок
  final int? bonus;           // бонус фармацевту
  final bool isAnalog;        // 1=аналог
  final bool isCtm;           // 1=СТМ (власна торгова марка)

  /// Назва для відображення: українська якщо є, інакше оригінальна.
  String get displayName => (nameUkr != null && nameUkr!.isNotEmpty) ? nameUkr! : name;

  const AnalogItem({
    required this.ukod,
    required this.name,
    this.nameUkr,
    required this.manufacturer,
    required this.price,
    required this.qty,
    this.bonus,
    this.isAnalog = false,
    this.isCtm = false,
  });

  factory AnalogItem.fromJson(Map<String, dynamic> json) {
    final bonusRaw = json['bonus']?.toString() ?? '';
    final bonusVal = int.tryParse(bonusRaw);
    return AnalogItem(
      ukod: json['UKod']?.toString() ?? json['ukod']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      nameUkr: (json['nameukr'] ?? json['NameUkr'])?.toString().isNotEmpty == true
          ? (json['nameukr'] ?? json['NameUkr']).toString()
          : null,
      manufacturer: json['proiz']?.toString() ?? json['manufacturer']?.toString() ?? '',
      price: double.tryParse(
            json['price']?.toString().replaceAll(',', '.') ?? '0',
          ) ?? 0.0,
      qty: (double.tryParse(
                json['kol']?.toString().replaceAll(',', '.') ?? json['qty']?.toString() ?? '0',
              ) ?? 0.0).floor(),
      bonus: (bonusVal != null && bonusVal > 0) ? bonusVal : null,
      isAnalog: json['analog']?.toString() == '1',
      isCtm: json['ctm']?.toString() == '1',
    );
  }
}

/// ЄДК-пропозиція заміни від Caché (з GetEdkOffers).
class EdkApiOffer {
  final String replacementId;      // с-код заміни
  final String replacementName;    // назва заміни
  final double replacementPrice;   // роздрібна ціна заміни
  final int replacementBonus;      // бонус за ЄДК-зв'язку
  final int pharmacistBonus;       // бонус фармацевту за продаж товару
  final String script;             // мовний модуль
  final String reason;             // причина ("Аналог", "Дефектура" тощо)

  const EdkApiOffer({
    required this.replacementId,
    required this.replacementName,
    required this.replacementPrice,
    required this.replacementBonus,
    required this.pharmacistBonus,
    required this.script,
    required this.reason,
  });

  factory EdkApiOffer.fromJson(Map<String, dynamic> json) {
    return EdkApiOffer(
      replacementId: json['replacementId']?.toString() ?? '',
      replacementName: json['replacementName']?.toString() ?? '',
      replacementPrice: double.tryParse(
            json['replacementPrice']?.toString().replaceAll(',', '.') ?? '0',
          ) ?? 0.0,
      replacementBonus: int.tryParse(json['replacementBonus']?.toString() ?? '') ?? 0,
      pharmacistBonus: int.tryParse(json['pharmacistBonus']?.toString() ?? '') ?? 0,
      script: json['script']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
    );
  }
}

/// Детальна інформація по товару (з GetSKUdetail).
class SKUDetailResult {
  final String? name;
  final String? manufacturer;
  final String? category;
  final String? inn;
  final String? dosageForm;
  final String? dosage;
  final bool requiresPrescription;
  final String? expiryDate;
  final int? unitsPerPackage;
  final bool variableDivisor;
  final int? pharmacistBonus;
  final String? barcode;
  final String? series;
  final String? storageConditions;
  final bool isOwnBrand;
  final String? analogueGroup;
  final String? imageUrl;
  final String? intakeWarning;
  final String? nameUkr;     // українська назва
  final String? skuCode;      // числовий код товару (ids з відповіді API)
  final String? comingPrice;  // ціна приходу (for FarmaSell Helping Hand)
  final String? comingCode;   // код приходу (for FarmaSell Helping Hand)

  SKUDetailResult({
    this.name,
    this.nameUkr,
    this.manufacturer,
    this.category,
    this.inn,
    this.dosageForm,
    this.dosage,
    this.requiresPrescription = false,
    this.expiryDate,
    this.unitsPerPackage,
    this.variableDivisor = false,
    this.pharmacistBonus,
    this.barcode,
    this.series,
    this.storageConditions,
    this.isOwnBrand = false,
    this.analogueGroup,
    this.imageUrl,
    this.intakeWarning,
    this.skuCode,
    this.comingPrice,
    this.comingCode,
  });

  factory SKUDetailResult.fromJson(Map<String, dynamic> json) {
    final unitsRaw = json['unitsPerPackage']?.toString() ?? '';
    final units = int.tryParse(unitsRaw);
    final bonusRaw = json['pharmacistBonus']?.toString() ?? '';
    final bonus = int.tryParse(bonusRaw);

    return SKUDetailResult(
      name: _nonEmpty(json['name']),
      nameUkr: _nonEmpty(json['nameukr'] ?? json['NameUkr']),
      manufacturer: _nonEmpty(json['manufacturer']),
      category: _nonEmpty(json['category']),
      inn: _nonEmpty(json['inn']),
      dosageForm: _nonEmpty(json['dosageForm']),
      dosage: _nonEmpty(json['dosage']),
      requiresPrescription: json['requiresPrescription']?.toString() == '1',
      expiryDate: _nonEmpty(json['expiryDate']),
      unitsPerPackage: (units != null && units > 0) ? units : null,
      variableDivisor: json['varDel']?.toString() == '1',
      pharmacistBonus: (bonus != null && bonus > 0) ? bonus : null,
      barcode: _nonEmpty(json['barcode']),
      series: _nonEmpty(json['series']),

      storageConditions: _nonEmpty(json['storageConditions']),
      isOwnBrand: json['isOwnBrand']?.toString() == '1',
      analogueGroup: _nonEmpty(json['analogueGroup']),
      imageUrl: _nonEmpty(json['imageUrl']),
      intakeWarning: _nonEmpty(json['intakeWarning']),
      skuCode: _nonEmpty(json['ids']),
      comingPrice: _nonEmpty(json['comingPrice']),
      comingCode: _nonEmpty(json['comingCode']),
    );
  }

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString();
    return (s != null && s.isNotEmpty) ? s : null;
  }

  // ── Parse intakeWarning → DrugUsageInfo ──────────────────────────────────
  //
  // Format from Caché:
  //   "Можна:1:Дорослим_Тільки при...:2:Дітям_Не можна:3:Вагітним_..."
  // Each segment: "Text:signType:Category_"
  // signType: 1=ok, 2=caution, 3=contraindicated
  //
  // Category keywords → DrugUsageInfo fields:
  //   Дорослим→adults, Дітям→children, Вагітним→pregnant,
  //   Годуючим→nursing, Алергікам→allergics, Водіям→drivers,
  //   Діабетикам→diabetics

  DrugUsageInfo? toUsageInfo() {
    if (intakeWarning == null || intakeWarning!.isEmpty) return null;

    // Split by underscore to get segments per category
    final segments = intakeWarning!.split('_');
    final Map<String, _IntakeEntry> entries = {};

    for (final seg in segments) {
      if (seg.trim().isEmpty) continue;
      // Each segment has parts separated by colons
      // Pattern: ...text:signType:CategoryName  (last two colon-parts are signType + category)
      final parts = seg.split(':');
      if (parts.length < 2) continue;

      // Last part is category name, second-to-last is signType
      final category = parts.last.trim();
      final signTypeStr = parts[parts.length - 2].trim();
      final signType = int.tryParse(signTypeStr);
      // Everything before signType:category is the description text
      final text = parts.sublist(0, parts.length - 2).join(':').trim();

      if (category.isNotEmpty && signType != null) {
        entries[category] = _IntakeEntry(signType: signType, text: text);
      }
    }

    if (entries.isEmpty) return null;

    // Parse children age from text like "Тільки при наявності..." or "З 6 років"
    String? childrenAge;
    final childEntry = entries['Дітям'];
    if (childEntry != null && childEntry.signType == 2) {
      final match = RegExp(r'(\d[,.\d]*)').firstMatch(childEntry.text);
      if (match != null) {
        childrenAge = match.group(1)?.replaceAll(',', '.');
      }
    }

    // Pregnant note for caution cases with extended text
    String? pregnantNote;
    final pregEntry = entries['Вагітним'];
    if (pregEntry != null && pregEntry.signType == 2 && pregEntry.text.length > 15) {
      pregnantNote = pregEntry.text;
    }

    return DrugUsageInfo(
      adults: _signTypeToStatus(entries['Дорослим']?.signType),
      children: entries.containsKey('Дітям')
          ? _signTypeToStatus(childEntry?.signType)
          : null,
      childrenFromAge: childrenAge,
      nursing: _signTypeToStatus(entries['Годуючим']?.signType),
      diabetics: _signTypeToStatus(entries['Діабетикам']?.signType),
      allergics: _signTypeToStatus(entries['Алергікам']?.signType),
      pregnant: _signTypeToStatus(pregEntry?.signType),
      pregnantNote: pregnantNote,
      drivers: _signTypeToStatus(entries['Водіям']?.signType),
    );
  }

  static UsageStatus _signTypeToStatus(int? signType) {
    switch (signType) {
      case 1:
        return UsageStatus.ok;
      case 2:
        return UsageStatus.caution;
      case 3:
        return UsageStatus.contraindicated;
      default:
        return UsageStatus.unknown;
    }
  }
}

class _IntakeEntry {
  final int signType;
  final String text;
  const _IntakeEntry({required this.signType, required this.text});
}

/// Сервіс для роботи з довідником препаратів.
///
/// Працює в двох режимах:
/// - **Mock** (ApiConfig.useMock = true): локальні дані з mock_drugs.dart
/// - **Live** (ApiConfig.useMock = false): HTTP-запити до Caché CSP
class DrugService {
  static final _api = CacheApiClient();

  // ---------------------------------------------------------------------------
  // Пошук по штрихкоду
  // ---------------------------------------------------------------------------

  /// Знайти препарат за штрихкодом.
  ///
  /// Caché: `GET ?ServiceName=GetSKU&barcode={barcode}`
  /// Повертає: Name, Proiz, Shelf
  static Future<DrugLookupResult> lookupByBarcode(String barcode) async {
    if (ApiConfig.useMock) return _mockLookupByBarcode(barcode);

    final response = await _api.call('GetSKU', params: {
      'barcode': barcode,
      'ids': '',
      'user': '',
    });

    if (!response.isOk) {
      return DrugLookupResult(found: false, error: response.result);
    }

    return DrugLookupResult(
      found: true,
      name: response.data['Name']?.toString(),
      nameUkr: response.data['NameUkr']?.toString(),
      manufacturer: response.data['Proiz']?.toString(),
      shelf: response.data['Shelf']?.toString(),
    );
  }

  /// Знайти препарат за внутрішнім кодом (ids).
  ///
  /// Caché: `GET ?ServiceName=GetSKU&ids={ids}`
  static Future<DrugLookupResult> lookupByIds(String ids) async {
    if (ApiConfig.useMock) return _mockLookupByIds(ids);

    final response = await _api.call('GetSKU', params: {
      'ids': ids,
      'barcode': '',
      'user': '',
    });

    if (!response.isOk) {
      return DrugLookupResult(found: false, error: response.result);
    }

    return DrugLookupResult(
      found: true,
      name: response.data['Name']?.toString(),
      nameUkr: response.data['NameUkr']?.toString(),
      manufacturer: response.data['Proiz']?.toString(),
      shelf: response.data['Shelf']?.toString(),
    );
  }

  // ---------------------------------------------------------------------------
  // Ціни та залишки
  // ---------------------------------------------------------------------------

  /// Отримати ціни та залишки по партіях.
  ///
  /// Caché: `GET ?ServiceName=GetSKUprice&sku={sku}[&barcode={barcode}]`
  /// Повертає: Name, Proiz, stelazh, vitrina, polka, robot, prices[]
  ///
  /// Якщо передати [barcode], сервер спочатку спробує знайти по sku,
  /// а потім по штрихкоду (фолбек).
  static Future<DrugPriceResult> getStockAndPrices(
    String sku, {
    String? barcode,
  }) async {
    if (ApiConfig.useMock) return _mockGetStockAndPrices(sku);

    final response = await _api.call('GetSKUprice', params: {
      'sku': sku,
      if (barcode != null) 'barcode': barcode,
    });

    if (!response.isOk) {
      return DrugPriceResult(found: false, error: response.result);
    }

    final pricesJson = response.data['prices'];
    final batches = <StockBatch>[];
    if (pricesJson is List) {
      for (final p in pricesJson) {
        if (p is Map<String, dynamic>) {
          batches.add(StockBatch.fromJson(p));
        }
      }
    }

    return DrugPriceResult(
      found: true,
      name: response.data['Name']?.toString(),
      nameUkr: response.data['NameUkr']?.toString(),
      manufacturer: response.data['Proiz']?.toString(),
      stelazh: response.data['stelazh']?.toString(),
      vitrina: response.data['vitrina']?.toString(),
      polka: response.data['polka']?.toString(),
      robot: response.data['robot']?.toString(),
      batches: batches,
    );
  }

  // ---------------------------------------------------------------------------
  // Пошук препаратів за назвою
  // ---------------------------------------------------------------------------

  /// Результат пошуку за назвою.
  ///
  /// Caché: `GET ?ServiceName=SearchByName&name={name}`
  /// Повертає: items[] з {ids, name, manufacturer, shelf, qty, price}
  static Future<List<DrugSearchItem>> searchByName(String name) async {
    if (ApiConfig.useMock) return [];

    try {
      final response = await _api.call('SearchByNameSKU', params: {
        'name': name,
      });

      if (!response.isOk) return [];

      final itemsJson = response.data['items'];
      if (itemsJson is! List) return [];

      return itemsJson
          .whereType<Map<String, dynamic>>()
          .map((j) => DrugSearchItem.fromJson(j))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Search by u-codes (includes out-of-stock items).
  /// Used in parallel with [searchByName] to show zero-stock drugs.
  static Future<List<DrugSearchItem>> searchByNameUcodes(String name) async {
    if (ApiConfig.useMock) return [];

    try {
      final response = await _api.call('SearchByName', params: {
        'name': name,
      });

      if (!response.isOk) return [];

      final itemsJson = response.data['items'];
      if (itemsJson is! List) return [];

      return itemsJson
          .whereType<Map<String, dynamic>>()
          .map((j) => DrugSearchItem.fromJson(j))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Залишок по коду довідника
  // ---------------------------------------------------------------------------

  /// Отримати залишок по коду довідника.
  ///
  /// Caché: `GET ?ServiceName=GetOstatokForKodSP&...`
  static Future<int> getStockByCode(String kodSP) async {
    if (ApiConfig.useMock) return _mockGetStock(kodSP);

    final response = await _api.call('GetOstatokForKodSP', params: {
      'IDS': kodSP,
    });

    if (!response.isOk) return 0;

    return int.tryParse(response.data['Result']?.toString() ?? '0') ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Деталі товару (GetSKUdetail)
  // ---------------------------------------------------------------------------

  /// Отримати детальну інформацію по товару.
  ///
  /// Caché: `GET ?ServiceName=GetSKUdetail&ids={ids}`
  /// Повертає: name, manufacturer, category, inn, dosageForm, dosage,
  /// requiresPrescription, expiryDate, unitsPerPackage, pharmacistBonus,
  /// barcode, series, storageConditions, isOwnBrand,
  /// analogueGroup, imageUrl, intakeWarning
  static Future<SKUDetailResult?> fetchSKUDetail(String ids) async {
    if (ApiConfig.useMock) return null;

    try {
      final response = await _api.call('GetSKUdetail', params: {
        'ids': ids,
      });

      if (!response.isOk) {
        debugPrint('GetSKUdetail FAIL ids=$ids: result="${response.result}" data=${response.data}');
        return null;
      }

      return SKUDetailResult.fromJson(response.data);
    } catch (e) {
      debugPrint('GetSKUdetail ERROR ids=$ids: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ЄДК (GetEdkOffers) — пропозиції заміни від Caché
  // ---------------------------------------------------------------------------

  /// Отримати ЄДК-пропозиції для товару.
  ///
  /// [ids] — внутрішній ID товару (короткий числовий код з GetSKUdetail.ids,
  /// НЕ s-код з SearchByNameSKU).
  ///
  /// Caché: `GET ?ServiceName=GetEdkOffers&ids={ids}`
  /// Response: `{"Status":"OK","offers":[{"replacementId":"...","replacementName":"...","replacementPrice":"...","replacementBonus":"...","script":"...","reason":"..."}]}`
  static Future<List<EdkApiOffer>> fetchEdkOffers(String ids) async {
    if (ApiConfig.useMock || ids.isEmpty) return [];

    try {
      final response = await _api.call('GetEdkOffers', params: {
        'ids': ids,
      });

      if (!response.isOk) {
        debugPrint('GetEdkOffers FAIL ids=$ids: ${response.result}');
        return [];
      }

      final offersJson = response.data['offers'] as List<dynamic>?;
      if (offersJson == null || offersJson.isEmpty) return [];

      return offersJson
          .map((e) => EdkApiOffer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('GetEdkOffers ERROR ids=$ids: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Аналоги товару (GetAnalog)
  // ---------------------------------------------------------------------------

  /// Отримати аналоги товару з Caché.
  ///
  /// [skod] — с-код товару (Drug.skuCode / DrugSearchItem.ids)
  ///
  /// Caché: `GET ?ServiceName=GetAnalog&SKod={skod}`
  /// Response: `{"Status":"OK","Analogs":[{"UKod":"...","name":"...","proiz":"...","price":"...","kol":"...","bonus":"...","analog":1,"ctm":0}]}`
  static Future<List<AnalogItem>> fetchAnalogs(String skod) async {
    if (ApiConfig.useMock || skod.isEmpty) return [];

    try {
      final response = await _api.call('GetAnalog', params: {
        'SKod': skod,
      });

      if (!response.isOk) {
        debugPrint('GetAnalog FAIL SKod=$skod: ${response.result}');
        return [];
      }

      final analogsJson = (response.data['Analogs']
          ?? response.data['analogs']) as List<dynamic>?;
      if (analogsJson == null || analogsJson.isEmpty) return [];

      return analogsJson
          .whereType<Map<String, dynamic>>()
          .map((j) => AnalogItem.fromJson(j))
          .toList();
    } catch (e) {
      debugPrint('GetAnalog ERROR SKod=$skod: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Блокування залишку (sgVRoznSetLock)
  // ---------------------------------------------------------------------------

  /// Зарезервувати/зняти резервування залишку товару на складі.
  ///
  /// Caché записує резервування в локальну базу — інші каси бачать
  /// зменшений доступний залишок. При qty=0 резервування знімається.
  ///
  /// Сервер завжди повертає Status=OK (якщо запит коректний), але в полі
  /// qty — фактично зарезервована кількість. Якщо запитали 3, а доступно
  /// лише 0.5 — повернеться qty=0.5.
  ///
  /// [skod] — с-код товару (оригінальний ids з SearchByNameSKU)
  /// [qty] — кількість для резервування (десятковий дріб, 0 = зняти).
  ///         Наприклад: 1.5 = 1 упаковка + половина (блістер).
  ///
  /// Повертає [StockLockResult] з фактичною зарезервованою кількістю.
  ///
  /// Caché: `GET ?ServiceName=sgVRoznSetLock&SKod={skod}&qty={qty}`
  /// Response: `{"Status":"OK","SKod":"...","qty":N,"cause":"...","causeTitle":"...","causeHelsi":"...","kolPos":N,"sumTov":N}`
  /// Формат `qty` для sgVRoznSetLock: ціле → без дробу; дробове → до 6 знаків
  /// без хвостових нулів (щоб дріб точно відповідав дільнику упаковки).
  static String _formatLockQty(double qty) {
    if (qty == qty.roundToDouble()) return qty.toInt().toString();
    var s = qty.toStringAsFixed(6);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  static Future<StockLockResult> setStockLock(String skod, double qty) async {
    if (ApiConfig.useMock || skod.isEmpty) {
      return StockLockResult(ok: true, grantedQty: qty);
    }

    try {
      // Передаємо десятковий дріб з крапкою (URL-параметр).
      // Дробова частка = k/дільник_упаковки. Сервер звіряє дріб із дільником,
      // тож 2 знаків мало: 1 блістер 30-упаковки = 1/30 = 0.0333…, а "0.03"
      // дільнику не відповідає (granted=0 → «зарезервовано»). Даємо більше
      // точності й прибираємо хвостові нулі (0.250000 → 0.25; 0.033333 лишається).
      final qtyStr = _formatLockQty(qty);
      final response = await _api.call('sgVRoznSetLock', params: {
        'SKod': skod,
        'qty': qtyStr,
      });

      if (!response.isOk) {
        debugPrint('sgVRoznSetLock FAIL SKod=$skod qty=$qty: ${response.result}');
        return StockLockResult(ok: false, grantedQty: 0);
      }

      final grantedQty = double.tryParse(
            response.data['qty']?.toString().replaceAll(',', '.') ?? '0',
          ) ?? 0.0;
      final cause = response.data['cause']?.toString() ?? '';
      final causeTitle = response.data['causeTitle']?.toString() ?? '';

      debugPrint('sgVRoznSetLock OK SKod=$skod requested=$qty granted=$grantedQty'
          '${cause.isNotEmpty ? ' cause=$cause' : ''}');

      return StockLockResult(
        ok: true,
        grantedQty: grantedQty,
        cause: cause.isNotEmpty ? cause : null,
        causeTitle: causeTitle.isNotEmpty ? causeTitle : null,
      );
    } catch (e) {
      debugPrint('sgVRoznSetLock ERROR SKod=$skod qty=$qty: $e');
      return StockLockResult(ok: false, grantedQty: 0);
    }
  }

  // ---------------------------------------------------------------------------
  // Топ-препарати для кешу (GetTopDrugs)
  // ---------------------------------------------------------------------------

  /// Завантажити топ популярних препаратів для локального кешу.
  ///
  /// Викликається один раз при старті зміни. Результати використовуються
  /// для миттєвого пошуку без звернення до сервера.
  ///
  /// Caché: `GET ?ServiceName=GetTopDrugs`
  static Future<List<DrugSearchItem>> fetchTopDrugs() async {
    if (ApiConfig.useMock) return [];

    try {
      final response = await _api.call('GetTopDrugs');

      debugPrint('GetTopDrugs RAW: status=${response.isOk}, '
          'keys=${response.data.keys.toList()}');

      if (!response.isOk) {
        debugPrint('GetTopDrugs FAIL: ${response.result}');
        return [];
      }

      // Try common array keys
      final itemsJson = (response.data['items']
          ?? response.data['Items']
          ?? response.data['drugs']
          ?? response.data['Drugs']) as List<dynamic>?;

      if (itemsJson == null || itemsJson.isEmpty) {
        debugPrint('GetTopDrugs: no items array found');
        // Maybe the items are at root level?
        if (response.data.containsKey('ids') || response.data.containsKey('name')) {
          debugPrint('GetTopDrugs: single item at root?');
        }
        return [];
      }

      debugPrint('GetTopDrugs: found ${itemsJson.length} items, '
          'first keys=${itemsJson.first is Map ? (itemsJson.first as Map).keys.toList() : "not a map"}');

      return itemsJson
          .whereType<Map<String, dynamic>>()
          .map((j) => DrugSearchItem.fromJson(j))
          .toList();
    } catch (e) {
      debugPrint('GetTopDrugs ERROR: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Mock реалізації (для розробки без сервера)
  // ---------------------------------------------------------------------------

  static Future<DrugLookupResult> _mockLookupByBarcode(String barcode) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final drug = mockDrugs.cast<Drug?>().firstWhere(
          (d) => d!.barcode == barcode,
          orElse: () => null,
        );
    if (drug == null) {
      return DrugLookupResult(found: false, error: 'товар не найден');
    }
    return DrugLookupResult(
      found: true,
      name: drug.name,
      manufacturer: drug.manufacturer,
      shelf: drug.locationCode,
    );
  }

  static Future<DrugLookupResult> _mockLookupByIds(String ids) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final drug = mockDrugs.cast<Drug?>().firstWhere(
          (d) => d!.id == ids,
          orElse: () => null,
        );
    if (drug == null) {
      return DrugLookupResult(found: false, error: 'товар не найден');
    }
    return DrugLookupResult(
      found: true,
      name: drug.name,
      manufacturer: drug.manufacturer,
      shelf: drug.locationCode,
    );
  }

  static Future<DrugPriceResult> _mockGetStockAndPrices(String sku) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final drug = mockDrugs.cast<Drug?>().firstWhere(
          (d) => d!.id == sku,
          orElse: () => null,
        );
    if (drug == null) {
      return DrugPriceResult(found: false, error: 'товар не найден');
    }
    return DrugPriceResult(
      found: true,
      name: drug.name,
      manufacturer: drug.manufacturer,
      stelazh: drug.locationCode,
      vitrina: '',
      polka: '',
      robot: '',
      batches: [
        StockBatch(
          skod: '${drug.id}01',
          status: '',
          qty: drug.stock,
          price: drug.price,
        ),
      ],
    );
  }

  static Future<int> _mockGetStock(String kodSP) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final drug = mockDrugs.cast<Drug?>().firstWhere(
          (d) => d!.id == kodSP,
          orElse: () => null,
        );
    return drug?.stock ?? 0;
  }
}
