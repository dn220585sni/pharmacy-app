import 'package:flutter/foundation.dart';
import '../models/payment_terminal.dart';
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
    // Перший виклик у сесії інколи падає "Перевірте клієнта ПРРО" (серверний
    // контекст клієнта ще не готовий) — ретраїмо (GET безпечно повторювати).
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        // ekkKodKli більше не передаємо — сервер бере код каси з LoginRlz.
        final r = await CacheApiClient().call('GetTermBank');
        if (r.isOk) {
          final list = PaymentTerminal.listFromResponse(r.data);
          debugPrint('TerminalService: ${list.length} terminals '
              '(main=${list.where((t) => t.isMain).length})');
          return _cache = list;
        }
        debugPrint('TerminalService FAIL (спроба $attempt): ${r.result}');
      } catch (e) {
        debugPrint('TerminalService ERROR (спроба $attempt): $e');
      }
      if (attempt < 3) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
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
