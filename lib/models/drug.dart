// ── Storage location ──────────────────────────────────────────────────────────

enum StorageLocationType { shelf, showcase }

// ── Usage status enum ─────────────────────────────────────────────────────────

enum UsageStatus { ok, caution, contraindicated, unknown }

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
  final String? expiryDate; // "MM/YY"
  final int? pharmacistBonus; // null = no badge
  final bool isInTransit;
  final bool isOwnBrand;
  final String? analogueGroup; // drugs sharing the same non-null value are analogues

  // ── Detail panel fields ────────────────────────────────────────────────────
  final String? dosageForm;        // "Таблетки", "Капсули", "Сироп", "Розчин"
  final String? inn;               // МНН: "Ібупрофен", "Парацетамол"
  final String? dosage;            // "400 мг", "500 мг/5 мл"
  final String? storageConditions; // "При t° не вище 25°C..."
  final StorageLocationType? locationType; // стелаж або вітрина
  final String? locationCode;             // "C3/02", "А4/07"
  final DrugUsageInfo? usageInfo;
  final String? imageUrl;          // product photo; future: provided by API
  final int? unitsPerPackage;      // blisters/units per package (null = not splittable)
  final String? intakeWarning;     // e.g. "Вживайте тільки після їжі!" (from external service)

  // ── Batch / serialisation fields ──────────────────────────────────────────
  final String? series;        // e.g. "036"
  final String? serialNumber;  // e.g. "1234734678"
  final String? barcode;       // e.g. "712467853"

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
    this.usageInfo,
    this.imageUrl,
    this.unitsPerPackage,
    this.intakeWarning,
    this.series,
    this.serialNumber,
    this.barcode,
  });

  bool get isExpired {
    if (expiryDate == null) return false;
    final parts = expiryDate!.split('/');
    if (parts.length != 2) return false;
    final month = int.tryParse(parts[0]);
    final year = int.tryParse(parts[1]);
    if (month == null || year == null) return false;
    final fullYear = 2000 + year;
    final now = DateTime.now();
    return DateTime(fullYear, month + 1).isBefore(DateTime(now.year, now.month, 1));
  }

  bool get isExpiringSoon {
    if (expiryDate == null || isExpired) return false;
    final parts = expiryDate!.split('/');
    if (parts.length != 2) return false;
    final month = int.tryParse(parts[0]);
    final year = int.tryParse(parts[1]);
    if (month == null || year == null) return false;
    final fullYear = 2000 + year;
    final expiry = DateTime(fullYear, month + 1);
    final threeMonthsFromNow = DateTime.now().add(const Duration(days: 91));
    return expiry.isBefore(threeMonthsFromNow);
  }
}
