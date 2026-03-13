import '../data/mock_drugs.dart';
import '../models/drug.dart';
import 'api_config.dart';
import 'cache_api_client.dart';

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
  final String ids;
  final String name;
  final String manufacturer;
  final String shelf;
  final int qty;
  final double price;

  DrugSearchItem({
    required this.ids,
    required this.name,
    required this.manufacturer,
    required this.shelf,
    required this.qty,
    required this.price,
  });

  factory DrugSearchItem.fromJson(Map<String, dynamic> json) {
    return DrugSearchItem(
      ids: json['ids']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      manufacturer: json['manufacturer']?.toString() ?? '',
      shelf: json['shelf']?.toString() ?? '',
      qty: (double.tryParse(
                json['qty']?.toString().replaceAll(',', '.') ?? '0',
              ) ?? 0.0)
              .round(),
      price: double.tryParse(
            json['price']?.toString().replaceAll(',', '.') ?? '0',
          ) ??
          0.0,
    );
  }
}

/// Результат пошуку товару (з GetSKU).
class DrugLookupResult {
  final bool found;
  final String? name;
  final String? manufacturer;
  final String? shelf;
  final String? error;

  DrugLookupResult({
    required this.found,
    this.name,
    this.manufacturer,
    this.shelf,
    this.error,
  });
}

/// Результат запиту цін та залишків (з GetSKUprice).
class DrugPriceResult {
  final bool found;
  final String? name;
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
