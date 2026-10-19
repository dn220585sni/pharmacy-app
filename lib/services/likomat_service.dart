import 'dart:ui';

import 'cache_api_client.dart';
import 'fiscal_log.dart';

/// Комірка лікомата зі схеми `DrawLikomat` (Катя 14.10).
class LikomatCellInfo {
  final int number;
  /// Положення на схемі в координатах сервісу (x, y, x2, y2).
  final Rect rect;
  /// Замовлення в комірці (порожньо — вільна).
  final String orderId;
  final bool blocked; // block = 1
  final bool service; // service = 1 — технічна комірка
  final bool notWorking; // notwork — несправна

  const LikomatCellInfo({
    required this.number,
    required this.rect,
    this.orderId = '',
    this.blocked = false,
    this.service = false,
    this.notWorking = false,
  });

  bool get isOccupied => orderId.isNotEmpty;
  bool get isAvailable => !isOccupied && !blocked && !service && !notWorking;
}

class LikomatScheme {
  final List<LikomatCellInfo> cells;
  final double maxX;
  final double maxY;
  const LikomatScheme(this.cells, this.maxX, this.maxY);
}

class LikomatService {
  static bool _flag(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isNotEmpty && s != '0';
  }

  static double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  /// Схема лікомата з поточним станом комірок. null — сервіс недоступний.
  static Future<LikomatScheme?> draw() async {
    try {
      final r = await CacheApiClient().call('DrawLikomat');
      final raw = r.data['Coords'];
      if (!r.isOk || raw is! List) {
        FiscalLog.log('DrawLikomat FAIL: ${r.result}');
        return null;
      }
      final cells = <LikomatCellInfo>[];
      for (final c in raw.whereType<Map<String, dynamic>>()) {
        final n = int.tryParse(c['cell']?.toString() ?? '');
        if (n == null) continue;
        cells.add(LikomatCellInfo(
          number: n,
          rect: Rect.fromLTRB(_d(c['x']), _d(c['y']), _d(c['x2']), _d(c['y2'])),
          orderId: c['idorder']?.toString().trim() ?? '',
          blocked: _flag(c['block']),
          service: _flag(c['service']),
          notWorking: _flag(c['notwork']),
        ));
      }
      if (cells.isEmpty) return null;
      var maxX = _d(r.data['maxx']);
      var maxY = _d(r.data['maxy']);
      for (final c in cells) {
        if (c.rect.right > maxX) maxX = c.rect.right;
        if (c.rect.bottom > maxY) maxY = c.rect.bottom;
      }
      return LikomatScheme(cells, maxX, maxY);
    } catch (e) {
      FiscalLog.log('DrawLikomat помилка: $e');
      return null;
    }
  }
}
