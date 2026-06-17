import 'package:flutter/foundation.dart';
import '../models/payment_terminal.dart';
import 'api_config.dart';
import 'cache_api_client.dart';

/// Платіжні термінали аптеки (`GetTermBank`).
///
/// Основний термінал (`isMain`) привʼязаний до касового місця (`ekkKodKli`);
/// решта — резервні, на випадок поломки основного. Кешується в памʼяті.
class TerminalService {
  static List<PaymentTerminal>? _cache;

  /// Список налаштованих терміналів аптеки (основний — першим).
  /// На помилку — порожній список (UI лишиться без вибору терміналу).
  static Future<List<PaymentTerminal>> getTerminals({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cache != null) return _cache!;
    try {
      final r = await CacheApiClient().call(
        'GetTermBank',
        params: {'ekkKodKli': ApiConfig.ekkKodKli},
      );
      if (r.isOk) {
        final list = PaymentTerminal.listFromResponse(r.data);
        debugPrint('TerminalService: ${list.length} terminals '
            '(main=${list.where((t) => t.isMain).length})');
        return _cache = list;
      }
      debugPrint('TerminalService FAIL: ${r.result}');
    } catch (e) {
      debugPrint('TerminalService ERROR: $e');
    }
    return const [];
  }

  /// Основний термінал; якщо позначки немає — перший зі списку (або null).
  static PaymentTerminal? mainOf(List<PaymentTerminal> terminals) {
    for (final t in terminals) {
      if (t.isMain) return t;
    }
    return terminals.isEmpty ? null : terminals.first;
  }
}
