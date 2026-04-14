import 'dart:math';
import '../models/drug.dart';

/// Levenshtein edit distance between two strings.
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Use two-row DP to save memory.
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);

  for (int i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (int j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = min(
        min(curr[j - 1] + 1, prev[j] + 1), // insert / delete
        prev[j - 1] + cost, // substitute
      );
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// Max allowed edit distance based on query length.
int _maxDistance(int queryLen) => queryLen <= 4 ? 1 : 2;

/// Normalize Russian↔Ukrainian characters for search:
/// и↔і, е↔є treated as equivalent.
String _normalizeSearch(String s) => s
    .replaceAll('и', 'і')
    .replaceAll('ы', 'і')
    .replaceAll('э', 'е')
    .replaceAll('ё', 'е')
    .replaceAll('є', 'е')
    .replaceAll('ї', 'і')
    .replaceAll('ъ', 'ь');

// ── Cached normalized names for fast repeated lookups ──────────────────────
final _normalizedCache = <String, String>{};

String _cachedNormalize(String s) {
  return _normalizedCache[s] ??= _normalizeSearch(s.toLowerCase());
}

/// Fuzzy score of [query] against [text].
/// Returns 0.0–1.0 (0 = no match, 1 = exact substring).
double fuzzyScore(String query, String text) {
  if (query.isEmpty) return 1.0;

  final q = _cachedNormalize(query);
  final t = _cachedNormalize(text);

  // 1. Exact substring → best score.
  if (t.contains(q)) return 1.0;

  // 2. Short queries (1-2 chars): only prefix/substring match, skip expensive fuzzy.
  if (q.length <= 2) return 0.0;

  // 3. Quick prefix check on first word — early exit if first chars don't match at all.
  //    If the first character doesn't appear anywhere in the text, skip fuzzy.
  if (!t.contains(q[0])) return 0.0;

  // 4. Sliding-window fuzzy substring match.
  final maxDist = _maxDistance(q.length);
  int bestDist = q.length; // worst possible

  // Window sizes: from (queryLen - maxDist) to (queryLen + maxDist).
  final winMin = max(1, q.length - maxDist);
  final winMax = min(q.length + maxDist, t.length);

  for (int winLen = winMin; winLen <= winMax; winLen++) {
    if (winLen > t.length) continue;
    for (int start = 0; start <= t.length - winLen; start++) {
      final window = t.substring(start, start + winLen);
      final dist = _levenshtein(q, window);
      if (dist < bestDist) {
        bestDist = dist;
        if (bestDist == 0) return 1.0; // exact match found in window
      }
    }
  }

  if (bestDist <= maxDist) {
    // Score: 1.0 for dist=0, decreasing with distance.
    return 1.0 - (bestDist / (q.length + 1));
  }

  return 0.0; // no usable match
}

/// Combined fuzzy score for a [Drug]: best of name & manufacturer.
double drugMatchScore(String query, Drug drug) {
  return max(
    fuzzyScore(query, drug.name),
    fuzzyScore(query, drug.manufacturer),
  );
}
