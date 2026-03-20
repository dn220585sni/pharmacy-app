import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/drug.dart';

/// Product Browser API (anc.ua) — drug safety tags & product info.
///
/// Endpoint: GET https://anc.ua/productbrowser/v2/ua/products/{slug}?city=5
/// Returns tags with sign_type: 1=можна, 2=з обережністю, 3=не можна
class ProductBrowserService {
  static const _baseUrl = 'https://anc.ua/productbrowser/v2/ua/products';
  static const _defaultCity = 5;
  static const _timeout = Duration(seconds: 8);
  static final _client = http.Client();

  /// In-memory cache: slug → ProductBrowserResult
  static final _cache = <String, ProductBrowserResult>{};

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch product info by full slug (e.g. "geksasprey-sprey-oromukozniy-750-mg-flakon-30-g-10498").
  static Future<ProductBrowserResult?> fetchBySlug(String slug) async {
    if (slug.isEmpty) return null;
    if (_cache.containsKey(slug)) return _cache[slug];

    try {
      final url = Uri.parse('$_baseUrl/$slug?city=$_defaultCity');
      final response = await _client.get(url, headers: {
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final result = ProductBrowserResult.fromJson(json);
      _cache[slug] = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Fetch Ukrainian indications from full_description HTML.
  /// Extracts text between <h2>Показання</h2> and the next <h2>.
  static Future<String?> fetchIndicationsUa(String fullDescriptionUrl) async {
    if (fullDescriptionUrl.isEmpty) return null;
    try {
      final response = await _client
          .get(Uri.parse(fullDescriptionUrl))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;

      final html = utf8.decode(response.bodyBytes);
      // Find "Показання" / "Показання до застосування" section
      final headerPattern = RegExp(
        r'<h2>\s*Показання[^<]*</h2>(.*?)(?=<h2>)',
        dotAll: true,
        caseSensitive: false,
      );
      final match = headerPattern.firstMatch(html);
      if (match == null) return null;

      // Strip HTML tags, decode entities, trim
      var text = match.group(1) ?? '';
      text = text
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// Try to fetch product by constructing slug from drug name + article ID.
  ///
  /// [name] — Ukrainian drug name (e.g. "Гексаспрей спрей оромукозний 750 мг флакон 30 г")
  /// [articleId] — anc.ua product ID (e.g. "10498")
  static Future<ProductBrowserResult?> fetchByNameAndId(
    String name,
    String articleId,
  ) async {
    final slug = buildSlug(name, articleId);
    return fetchBySlug(slug);
  }

  /// Search for a product via search API and fetch full details.
  ///
  /// Search API returns slug + picture + instructions in one call,
  /// then fetches full product detail (with tags) by slug.
  /// Tries drug name first (most relevant), falls back to article ID.
  static Future<ProductBrowserResult?> searchAndFetch({
    String? articleId,
    String? name,
  }) async {
    // Try name search first (more specific for matching exact product)
    if (name != null && name.isNotEmpty) {
      final slug = await _searchSlug(name);
      if (slug != null) return fetchBySlug(slug);
    }
    // Fall back to article ID search
    if (articleId != null && articleId.isNotEmpty) {
      final slug = await _searchSlug(articleId);
      if (slug != null) return fetchBySlug(slug);
    }
    return null;
  }

  /// Search products by query string. Returns lightweight search results.
  ///
  /// Use this for analogue search (by INN/active substance name).
  /// Returns up to [limit] results.
  static Future<List<ProductSearchResult>> searchProducts(
    String query, {
    int limit = 20,
  }) async {
    if (query.isEmpty) return [];
    try {
      final url = Uri.parse(
        'https://anc.ua/productbrowser/v2/ua/search/products'
        '?q=${Uri.encodeComponent(query)}&city=$_defaultCity',
      );
      final response = await _client.get(url, headers: {
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode != 200) return [];

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      final products = json['products'] as List? ?? [];

      return products
          .take(limit)
          .map((p) =>
              ProductSearchResult.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Search endpoint → return slug of first matching product.
  static Future<String?> _searchSlug(String query) async {
    try {
      final url = Uri.parse(
        'https://anc.ua/productbrowser/v2/ua/search/products'
        '?q=${Uri.encodeComponent(query)}&city=$_defaultCity',
      );
      final response = await _client.get(url, headers: {
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      final products = json['products'] as List?;
      if (products == null || products.isEmpty) return null;

      final first = products.first as Map<String, dynamic>;
      return first['link']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Clear cache (e.g. on app restart or memory pressure).
  static void clearCache() => _cache.clear();

  // ─────────────────────────────────────────────────────────────────────────
  // Slug builder (Ukrainian transliteration)
  // ─────────────────────────────────────────────────────────────────────────

  /// Build URL slug from Ukrainian drug name + article ID.
  ///
  /// "Гексаспрей спрей оромукозний 750 мг флакон 30 г" + "10498"
  /// → "geksasprey-sprey-oromukozniy-750-mg-flakon-30-g-10498"
  static String buildSlug(String name, String articleId) {
    final transliterated = _transliterate(name.toLowerCase());
    // Replace non-alphanumeric with hyphens, collapse multiple hyphens
    final slug = transliterated
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), ''); // trim leading/trailing hyphens
    return '$slug-$articleId';
  }

  /// Ukrainian → Latin transliteration (simplified, matching anc.ua patterns).
  static String _transliterate(String text) {
    const map = {
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'ґ': 'g',
      'д': 'd', 'е': 'e', 'є': 'ye', 'ж': 'zh', 'з': 'z',
      'и': 'i', 'і': 'i', 'ї': 'yi', 'й': 'y', 'к': 'k',
      'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p',
      'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f',
      'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
      'ь': '', 'ю': 'yu', 'я': 'ya', 'ъ': '',
      // Russian letters (some drug names may be in Russian)
      'э': 'e', 'ы': 'y', 'ё': 'yo',
    };

    final buf = StringBuffer();
    for (final ch in text.split('')) {
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Convert tags → DrugUsageInfo
  // ─────────────────────────────────────────────────────────────────────────

  /// Parse sign_type to UsageStatus.
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

// ═══════════════════════════════════════════════════════════════════════════
// Result model
// ═══════════════════════════════════════════════════════════════════════════

class ProductBrowserResult {
  final String id;
  final String name;
  final String slug;
  final double? price;
  final String? producer;
  final String? description;
  final String? information; // показання
  final String? instructionsUrl;
  final String? fullDescriptionUrl;
  final List<String> pictures;
  final List<ProductTag> tags;
  final bool isMedication;
  final bool requiresPrescription;

  const ProductBrowserResult({
    required this.id,
    required this.name,
    required this.slug,
    this.price,
    this.producer,
    this.description,
    this.information,
    this.instructionsUrl,
    this.fullDescriptionUrl,
    this.pictures = const [],
    this.tags = const [],
    this.isMedication = false,
    this.requiresPrescription = false,
  });

  factory ProductBrowserResult.fromJson(Map<String, dynamic> json) {
    final tagsList = (json['tags'] as List? ?? [])
        .map((t) => ProductTag.fromJson(t as Map<String, dynamic>))
        .toList();

    // Check prescription tag
    final prescriptionTag = tagsList
        .where((t) => t.jsonName == 'prescription')
        .firstOrNull;
    final needsRx = prescriptionTag != null &&
        prescriptionTag.signType != 1; // 1 = "Без рецепта" (можна)

    return ProductBrowserResult(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      slug: json['link']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble(),
      producer: (json['producer'] as Map?)?['name']?.toString(),
      description: json['description']?.toString(),
      information: json['information']?.toString(),
      instructionsUrl: json['instructions']?.toString(),
      fullDescriptionUrl: json['full_description']?.toString(),
      pictures: (json['pictures'] as List? ?? [])
          .map((p) => p.toString())
          .toList(),
      tags: tagsList,
      isMedication: json['is_medication'] == true,
      requiresPrescription: needsRx,
    );
  }

  /// Convert safety tags to DrugUsageInfo.
  DrugUsageInfo? toUsageInfo() {
    final safetyTags = {
      for (final t in tags)
        if (t.signType != null) t.jsonName: t,
    };

    // Need at least one safety tag to build usage info
    if (safetyTags.isEmpty) return null;

    final childrenTag = safetyTags['children'];
    String? childrenAge;
    if (childrenTag != null && childrenTag.signType == 2) {
      // Extract age from value like "З 2,5 років" or "З 6 років"
      final match = RegExp(r'(\d[,\d]*)').firstMatch(childrenTag.value);
      if (match != null) {
        childrenAge = match.group(1)?.replaceAll(',', '.');
      }
    }

    final pregnantTag = safetyTags['pregnant'];
    String? pregnantNote;
    // If pregnant value contains more than simple "Не можна"/"Можна", save as note
    if (pregnantTag != null &&
        pregnantTag.value.length > 15 &&
        pregnantTag.signType == 2) {
      pregnantNote = pregnantTag.value;
    }

    return DrugUsageInfo(
      adults: ProductBrowserService._signTypeToStatus(
          safetyTags['adults']?.signType),
      children: safetyTags.containsKey('children')
          ? ProductBrowserService._signTypeToStatus(childrenTag?.signType)
          : null,
      childrenFromAge: childrenAge,
      nursing: ProductBrowserService._signTypeToStatus(
          safetyTags['feeding']?.signType),
      diabetics: ProductBrowserService._signTypeToStatus(
          safetyTags['diabetics']?.signType),
      allergics: ProductBrowserService._signTypeToStatus(
          safetyTags['allergyAffected']?.signType),
      pregnant: ProductBrowserService._signTypeToStatus(
          pregnantTag?.signType),
      pregnantNote: pregnantNote,
      drivers: ProductBrowserService._signTypeToStatus(
          safetyTags['drivers']?.signType),
    );
  }

  /// Get product image URL (first available, with .jpg extension).
  /// API returns URLs without extension — append .jpg for Google Storage.
  String? get imageUrl {
    if (pictures.isEmpty) return null;
    final url = pictures.first;
    // Already has extension → use as-is
    if (url.contains(RegExp(r'\.\w{3,4}$'))) return url;
    // Append .jpg for Google Storage URLs
    return '$url.jpg';
  }

  /// Get application method from tags (e.g. "Для порожнини рота").
  String? get applicationMethod {
    final tag = tags.where((t) => t.jsonName == 'usageName').firstOrNull;
    return tag?.value;
  }

  /// Get country of origin from tags (e.g. "Франція").
  String? get countryOfOrigin {
    final tag = tags
        .where((t) => t.jsonName == 'cosmetic_ManufCountry')
        .firstOrNull;
    return tag?.value;
  }

  /// Get dosage form from tags (e.g. "Спреї", "Таблетки").
  String? get dosageForm {
    final tag = tags.where((t) => t.jsonName == 'name').firstOrNull;
    return tag?.value;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tag model
// ═══════════════════════════════════════════════════════════════════════════

class ProductTag {
  final String name;      // "Дорослим", "Дітям", "Вагітним"
  final String value;     // "Можна", "З обережністю", "Не можна"
  final String jsonName;  // "adults", "children", "pregnant"
  final int? signType;    // 1=можна, 2=з обережністю, 3=не можна, null=info

  const ProductTag({
    required this.name,
    required this.value,
    required this.jsonName,
    this.signType,
  });

  factory ProductTag.fromJson(Map<String, dynamic> json) {
    return ProductTag(
      name: json['name']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      jsonName: json['json_name']?.toString() ?? '',
      signType: json['sign_type'] as int?,
    );
  }

  bool get isSafetyTag => signType != null;
}

// ═══════════════════════════════════════════════════════════════════════════
// Lightweight search result (from /v2/ua/search/products)
// ═══════════════════════════════════════════════════════════════════════════

class ProductSearchResult {
  final String id;         // article code, e.g. "2321"
  final String link;       // slug, e.g. "korvalol-krapli-oralni-flakon-25-ml-2321"
  final String name;       // "Корвалол краплі оральні флакон 25 мл"
  final double price;
  final String? picture;   // product image URL
  final String? producer;  // manufacturer name
  final String? instructions; // instruction URL
  final bool hasAnalogs;
  final bool prescriptionOnly;
  final List<String> categories;

  const ProductSearchResult({
    required this.id,
    required this.link,
    required this.name,
    required this.price,
    this.picture,
    this.producer,
    this.instructions,
    this.hasAnalogs = false,
    this.prescriptionOnly = false,
    this.categories = const [],
  });

  factory ProductSearchResult.fromJson(Map<String, dynamic> json) {
    final cats = (json['categories'] as List? ?? [])
        .map((c) => (c as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    // Picture URL: append .jpg if no extension
    String? pic = json['picture']?.toString();
    if (pic != null && !pic.contains(RegExp(r'\.\w{3,4}$'))) {
      pic = '$pic.jpg';
    }

    return ProductSearchResult(
      id: json['id']?.toString() ?? '',
      link: json['link']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      picture: pic,
      producer: (json['producer'] as Map?)?['name']?.toString(),
      instructions: json['instructions']?.toString(),
      hasAnalogs: json['hasAnalogs'] == true,
      prescriptionOnly: json['prescription_only'] == true,
      categories: cats,
    );
  }

  /// Get image URL (with .jpg extension fix).
  String? get imageUrl => picture;
}
