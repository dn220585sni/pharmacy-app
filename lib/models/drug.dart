// ── Storage location ──────────────────────────────────────────────────────────

enum StorageLocationType { shelf, showcase, polka, robot }

class StorageLocation {
  final StorageLocationType type;
  final String code;
  final int qty;
  const StorageLocation({required this.type, required this.code, required this.qty});
}

// ── Usage status enum ─────────────────────────────────────────────────────────

enum UsageStatus { ok, caution, contraindicated, unknown }

// ── Drug availability status (for out-of-stock drugs) ─────────────────────────

enum DrugAvailabilityStatus {
  marketShortage,    // Відсутній на ринку
  quarantined,       // В карантині
  inTransit,         // В дорозі
  awaitingReceiving, // В аптеці, очікує приходування
  notOrdered,        // Не замовлений
}

// ── Per-drug usage profile (populated from mock; future: loaded from API) ─────

class DrugUsageInfo {
  final UsageStatus adults;
  final UsageStatus? children;     // null = "не досліджено"
  final String? childrenFromAge;   // e.g. "6" → displayed as "з 6 років"
  final UsageStatus nursing;
  final UsageStatus diabetics;
  final UsageStatus allergics;
  final UsageStatus pregnant;
  final String? pregnantNote;      // overrides standard text when set
  final UsageStatus drivers;

  const DrugUsageInfo({
    required this.adults,
    this.children,
    this.childrenFromAge,
    required this.nursing,
    required this.diabetics,
    required this.allergics,
    required this.pregnant,
    this.pregnantNote,
    required this.drivers,
  });
}

// ── Drug model ────────────────────────────────────────────────────────────────

class Drug {
  final String id;
  final String name;
  final String manufacturer;
  final String category;
  final double price;
  final int stock;
  final String unit;
  final bool requiresPrescription;
  final String? expiryDate; // "DD.MM.YYYY" (e.g. "01.08.2027")
  final int? pharmacistBonus; // null = no badge
  final bool isInTransit;
  final bool isOwnBrand;
  final String? analogueGroup; // drugs sharing the same non-null value are analogues

  // ── Detail panel fields ────────────────────────────────────────────────────
  final String? dosageForm;        // "Таблетки", "Капсули", "Сироп", "Розчин"
  final String? inn;               // МНН: "Ібупрофен", "Парацетамол"
  final String? dosage;            // "400 мг", "500 мг/5 мл"
  final String? storageConditions; // "При t° не вище 25°C..."
  final StorageLocationType? locationType; // стелаж або вітрина (legacy single)
  final String? locationCode;             // "C3/02", "А4/07" (legacy single)
  final List<StorageLocation>? storageLocations; // multi-location with quantities
  final DrugUsageInfo? usageInfo;
  final String? imageUrl;          // product photo; future: provided by API
  final int? unitsPerPackage;      // blisters/units per package (null = not splittable)
  final String? intakeWarning;     // e.g. "Вживайте тільки після їжі!" (from external service)

  // ── Product Browser fields (fetched from anc.ua API) ─────────────────────
  final String? productBrowserSlug; // e.g. "korvalol-krapli-oralni-flakon-25-ml-2321"
  final String? indications;       // показання: "ангіна, фарингіт, стоматит..."
  final String? instructionsUrl;   // URL to full drug instruction HTML
  final String? applicationMethod; // спосіб застосування: "Для порожнини рота"
  final String? countryOfOrigin;   // країна виробництва: "Франція"

  // ── Batch fields ─────────────────────────────────────────────────────────
  final String? series;        // e.g. "DN50825"
  final String? barcode;       // e.g. "712467853"

  // ── Availability (for out-of-stock drugs) ───────────────────────────────
  final DrugAvailabilityStatus? availabilityStatus;

  // ── Рука допомоги (social discount program) ────────────────────────────
  final bool hasHelpingHand;

  // ── Caché codes ──────────────────────────────────────────────────────
  final String? ukod;          // u-код товару (код довідника, напр. "762*1*47*6****")
  final String? skuCode;       // s-код або числовий код товару
  final String? comingPrice;   // ціна приходу товару
  final String? comingCode;    // код приходу товару

  const Drug({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.category,
    required this.price,
    required this.stock,
    required this.unit,
    this.requiresPrescription = false,
    this.expiryDate,
    this.pharmacistBonus,
    this.isInTransit = false,
    this.isOwnBrand = false,
    this.analogueGroup,
    this.dosageForm,
    this.inn,
    this.dosage,
    this.storageConditions,
    this.locationType,
    this.locationCode,
    this.storageLocations,
    this.usageInfo,
    this.imageUrl,
    this.unitsPerPackage,
    this.intakeWarning,
    this.productBrowserSlug,
    this.indications,
    this.instructionsUrl,
    this.applicationMethod,
    this.countryOfOrigin,
    this.series,
    this.barcode,
    this.availabilityStatus,
    this.hasHelpingHand = false,
    this.ukod,
    this.skuCode,
    this.comingPrice,
    this.comingCode,
  });

  bool get isOutOfStock => stock == 0;

  /// Чи можна продати товар поблістерно.
  /// true тільки якщо в упаковці більше 1 блістера/одиниці.
  bool get canSplitByBlister => unitsPerPackage != null && unitsPerPackage! > 1;

  /// Parse expiryDate in "DD.MM.YYYY" format to DateTime.
  /// Returns null if format is invalid.
  DateTime? get parsedExpiry {
    if (expiryDate == null) return null;
    final parts = expiryDate!.split('.');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  bool get isExpired {
    final expiry = parsedExpiry;
    if (expiry == null) return false;
    return expiry.isBefore(DateTime.now());
  }

  Drug copyWithStorage({
    StorageLocationType? locationType,
    String? locationCode,
    List<StorageLocation>? storageLocations,
  }) {
    return Drug(
      id: id,
      name: name,
      manufacturer: manufacturer,
      category: category,
      price: price,
      stock: stock,
      unit: unit,
      requiresPrescription: requiresPrescription,
      expiryDate: expiryDate,
      pharmacistBonus: pharmacistBonus,
      isInTransit: isInTransit,
      isOwnBrand: isOwnBrand,
      analogueGroup: analogueGroup,
      dosageForm: dosageForm,
      inn: inn,
      dosage: dosage,
      storageConditions: storageConditions,
      locationType: locationType ?? this.locationType,
      locationCode: locationCode ?? this.locationCode,
      storageLocations: storageLocations ?? this.storageLocations,
      usageInfo: usageInfo,
      imageUrl: imageUrl,
      unitsPerPackage: unitsPerPackage,
      intakeWarning: intakeWarning,
      productBrowserSlug: productBrowserSlug,
      indications: indications,
      instructionsUrl: instructionsUrl,
      applicationMethod: applicationMethod,
      countryOfOrigin: countryOfOrigin,
      series: series,

      barcode: barcode,
      availabilityStatus: availabilityStatus,
      hasHelpingHand: hasHelpingHand,
      ukod: ukod,
      skuCode: skuCode,
      comingPrice: comingPrice,
      comingCode: comingCode,
    );
  }

  /// Create copy with Product Browser API data.
  Drug copyWithProductBrowser({
    DrugUsageInfo? usageInfo,
    String? imageUrl,
    String? indications,
    String? instructionsUrl,
    String? applicationMethod,
    String? countryOfOrigin,
  }) {
    return Drug(
      id: id,
      name: name,
      manufacturer: manufacturer,
      category: category,
      price: price,
      stock: stock,
      unit: unit,
      requiresPrescription: requiresPrescription,
      expiryDate: expiryDate,
      pharmacistBonus: pharmacistBonus,
      isInTransit: isInTransit,
      isOwnBrand: isOwnBrand,
      analogueGroup: analogueGroup,
      dosageForm: dosageForm,
      inn: inn,
      dosage: dosage,
      storageConditions: storageConditions,
      locationType: locationType,
      locationCode: locationCode,
      storageLocations: storageLocations,
      usageInfo: usageInfo ?? this.usageInfo,
      imageUrl: imageUrl ?? this.imageUrl,
      unitsPerPackage: unitsPerPackage,
      intakeWarning: intakeWarning,
      productBrowserSlug: productBrowserSlug,
      indications: indications ?? this.indications,
      instructionsUrl: instructionsUrl ?? this.instructionsUrl,
      applicationMethod: applicationMethod ?? this.applicationMethod,
      countryOfOrigin: countryOfOrigin ?? this.countryOfOrigin,
      series: series,

      barcode: barcode,
      availabilityStatus: availabilityStatus,
      hasHelpingHand: hasHelpingHand,
      ukod: ukod,
      skuCode: skuCode,
      comingPrice: comingPrice,
      comingCode: comingCode,
    );
  }

  /// Create copy enriched with data from GetSKUdetail API.
  Drug copyWithSKUDetail({
    String? inn,
    String? dosageForm,
    String? dosage,
    String? manufacturer,
    String? category,
    String? expiryDate,
    int? unitsPerPackage,
    int? pharmacistBonus,
    String? barcode,
    String? series,
    String? storageConditions,
    bool? requiresPrescription,
    bool? isOwnBrand,
    String? analogueGroup,
    String? imageUrl,
    String? intakeWarning,
    String? skuCode,
    String? comingPrice,
    String? comingCode,
  }) {
    // hasHelpingHand = true if server provides comingPrice + comingCode
    final hh = (comingPrice ?? this.comingPrice) != null &&
        (comingCode ?? this.comingCode) != null;

    return Drug(
      id: id,
      name: name,
      manufacturer: (manufacturer != null && this.manufacturer.isEmpty)
          ? manufacturer
          : this.manufacturer,
      category: (category != null && this.category.isEmpty)
          ? category
          : this.category,
      price: price,
      stock: stock,
      unit: unit,
      requiresPrescription: requiresPrescription ?? this.requiresPrescription,
      expiryDate: expiryDate ?? this.expiryDate,
      pharmacistBonus: pharmacistBonus ?? this.pharmacistBonus,
      isInTransit: isInTransit,
      isOwnBrand: isOwnBrand ?? this.isOwnBrand,
      analogueGroup: analogueGroup ?? this.analogueGroup,
      dosageForm: dosageForm ?? this.dosageForm,
      inn: inn ?? this.inn,
      dosage: dosage ?? this.dosage,
      storageConditions: storageConditions ?? this.storageConditions,
      locationType: locationType,
      locationCode: locationCode,
      storageLocations: storageLocations,
      usageInfo: usageInfo,
      imageUrl: imageUrl ?? this.imageUrl,
      unitsPerPackage: unitsPerPackage ?? this.unitsPerPackage,
      intakeWarning: intakeWarning ?? this.intakeWarning,
      productBrowserSlug: productBrowserSlug,
      indications: indications,
      instructionsUrl: instructionsUrl,
      applicationMethod: applicationMethod,
      countryOfOrigin: countryOfOrigin,
      series: series ?? this.series,
      barcode: barcode ?? this.barcode,
      availabilityStatus: availabilityStatus,
      hasHelpingHand: hh || hasHelpingHand,
      ukod: ukod,
      skuCode: skuCode ?? this.skuCode,
      comingPrice: comingPrice ?? this.comingPrice,
      comingCode: comingCode ?? this.comingCode,
    );
  }

  bool get isExpiringSoon {
    if (isExpired) return false;
    final expiry = parsedExpiry;
    if (expiry == null) return false;
    final threeMonthsFromNow = DateTime.now().add(const Duration(days: 91));
    return expiry.isBefore(threeMonthsFromNow);
  }

  /// Short display format for table: "MM.YY" (e.g. "08.27")
  String? get expiryShort {
    if (expiryDate == null) return null;
    final parts = expiryDate!.split('.');
    if (parts.length != 3) return expiryDate;
    final month = parts[1];
    final year = parts[2].length == 4 ? parts[2].substring(2) : parts[2];
    return '$month.$year';
  }
}
