// Test Product Browser API — drug safety tags
// Run: dart run tool/test_product_browser.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

const baseUrl = 'https://anc.ua/productbrowser/v2/ua/products';

Future<void> main() async {
  const slug = 'geksasprey-sprey-oromukozniy-750-mg-flakon-30-g-10498';

  print('Fetching: $baseUrl/$slug?city=5\n');

  final resp = await http.get(
    Uri.parse('$baseUrl/$slug?city=5'),
    headers: {'Accept': 'application/json'},
  ).timeout(const Duration(seconds: 10));

  if (resp.statusCode != 200) {
    print('ERROR: HTTP ${resp.statusCode}');
    return;
  }

  final json = jsonDecode(resp.body) as Map<String, dynamic>;

  print('id:   ${json['id']}');
  print('name: ${json['name']}');
  print('link: ${json['link']}');
  print('price: ${json['price']}');
  print('is_medication: ${json['is_medication']}');
  print('');

  final tags = json['tags'] as List? ?? [];
  print('=== ALL TAGS (${tags.length}) ===');
  for (final tag in tags) {
    final name = tag['name'];
    final value = tag['value'];
    final jsonName = tag['json_name'];
    final signType = tag['sign_type'];
    final label = signType != null
        ? '[sign_type=$signType]'
        : '[info]';
    print('  $label $jsonName: $name = $value');
  }

  print('\n=== SAFETY TAGS ONLY ===');
  for (final tag in tags) {
    if (tag['sign_type'] != null) {
      final st = tag['sign_type'] as int;
      final status = st == 1 ? '✅ можна' : st == 2 ? '⚠️ з обережністю' : '❌ не можна';
      print('  ${tag['json_name'].toString().padRight(18)} → $status (${tag['value']})');
    }
  }

  // Test transliteration
  print('\n=== SLUG BUILDER TEST ===');
  const testName = 'Гексаспрей спрей оромукозний 750 мг флакон 30 г';
  const testId = '10498';
  final generatedSlug = _buildSlug(testName, testId);
  print('Input:    "$testName" + "$testId"');
  print('Expected: $slug');
  print('Got:      $generatedSlug');
  print('Match:    ${generatedSlug == slug ? "✅ YES" : "❌ NO"}');
}

String _buildSlug(String name, String articleId) {
  final transliterated = _transliterate(name.toLowerCase());
  final slug = transliterated
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return '$slug-$articleId';
}

String _transliterate(String text) {
  const map = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'ґ': 'g',
    'д': 'd', 'е': 'e', 'є': 'ye', 'ж': 'zh', 'з': 'z',
    'и': 'i', 'і': 'i', 'ї': 'yi', 'й': 'y', 'к': 'k',
    'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p',
    'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f',
    'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
    'ь': '', 'ю': 'yu', 'я': 'ya', 'ъ': '',
    'э': 'e', 'ы': 'y', 'ё': 'yo',
  };
  final buf = StringBuffer();
  for (final ch in text.split('')) {
    buf.write(map[ch] ?? ch);
  }
  return buf.toString();
}
