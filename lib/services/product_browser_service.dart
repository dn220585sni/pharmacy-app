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

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final result = ProductBrowserResult.fromJson(json);
      _cache[slug] = result;
      return result;
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
