import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/json_num.dart';
import 'fiscal_log.dart';
import 'prro_service.dart';
import 'session_service.dart';

/// Стадія продажу. Порядок важливий: кожна наступна означає, що попередня
/// відпрацювала.
enum SaleStage {
  /// Накладна створена (є NumNakl), фіскального документа ЩЕ немає.
  started,

  /// Чек ПРРО зареєстровано (є фіскальний номер). Гроші вже взяті.
  fiscalized,

  /// `PutKasa` пройшов — чек відмічено в касі/накладній Caché.
  fixed,
}

/// Один продаж у журналі.
class SaleRecord {
  /// NumNakl накладної; він же `local_number` чека ПРРО.
  final String numNakl;
  final int localNumber;
  final double total;
  final bool isCard;
  final DateTime startedAt;

  SaleStage stage;
  String? orderNum;
  String? link;
  int recoverAttempts;
  String? note;

  SaleRecord({
    required this.numNakl,
    required this.localNumber,
    required this.total,
    required this.isCard,
    required this.startedAt,
    this.stage = SaleStage.started,
    this.orderNum,
    this.link,
    this.recoverAttempts = 0,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'num_nakl': numNakl,
        'local_number': localNumber,
        'total': total,
        'is_card': isCard,
        'started_at': startedAt.toIso8601String(),
        'stage': stage.name,
        'order_num': orderNum,
        'link': link,
        'recover_attempts': recoverAttempts,
        'note': note,
      };

  factory SaleRecord.fromJson(Map<String, dynamic> j) => SaleRecord(
        numNakl: j['num_nakl']?.toString() ?? '',
        localNumber: flexInt(j['local_number']) ?? 0,
        total: flexDouble(j['total']) ?? 0,
        isCard: j['is_card'] == true,
        startedAt:
            DateTime.tryParse(j['started_at']?.toString() ?? '') ?? DateTime.now(),
        stage: SaleStage.values.firstWhere(
          (s) => s.name == j['stage'],
          orElse: () => SaleStage.started,
        ),
        orderNum: j['order_num']?.toString(),
        link: j['link']?.toString(),
        recoverAttempts: flexInt(j['recover_attempts']) ?? 0,
        note: j['note']?.toString(),
      );

  /// Короткий опис для журналу/діагностики.
  String get label => 'nakl=$numNakl сума=$total '
      '${isCard ? "картка" : "готівка"} стадія=${stage.name}'
      '${orderNum != null ? " чек=$orderNum" : ""}';
}

/// Write-ahead журнал продажів (audit A3).
///
/// Проблема, яку закриває: між «гроші взято» і «продаж зафіксовано в Caché»
/// існує вікно, в якому падіння застосунку (або каси) губить продаж мовчки —
/// чек у ПРРО є, а в накладній він не відмічений. Тому кожна стадія лягає на
/// диск ДО того, як робиться відповідний крок, а на старті незавершені записи
/// добиваються.
///
/// Файл: `%APPDATA%\...\pharmacy_app\sale_journal.json`. Запис живе лише поки
/// продаж не завершено — журнал не історія, а список незакритих хвостів.
class SaleJournal {
  static const _fileName = 'sale_journal.json';
  static List<SaleRecord> _items = [];
  static bool _loaded = false;

  /// Незавершені продажі (для UI/діагностики).
  static List<SaleRecord> get pending => List.unmodifiable(_items);
  static int get count => _items.length;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final file = await _file();
    if (file == null || !await file.exists()) return;
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      _items = list
          .whereType<Map<String, dynamic>>()
          .map(SaleRecord.fromJson)
          .toList();
      if (_items.isNotEmpty) {
        debugPrint('SaleJournal: ${_items.length} незавершених продажів');
      }
    } catch (e) {
      debugPrint('SaleJournal load FAIL: $e');
      _items = [];
    }
  }

  /// Накладна створена — фіксуємо намір продати ДО фіскалізації.
  static Future<void> start({
    required String numNakl,
    required int localNumber,
    required double total,
    required bool isCard,
  }) async {
    await load();
    _items.removeWhere((e) => e.numNakl == numNakl);
    _items.add(SaleRecord(
      numNakl: numNakl,
      localNumber: localNumber,
      total: total,
      isCard: isCard,
      startedAt: DateTime.now(),
    ));
    await _persist();
  }

  /// Чек ПРРО зареєстровано.
  static Future<void> markFiscalized(
    String numNakl, {
    String? orderNum,
    String? link,
  }) async {
    final r = _find(numNakl);
    if (r == null) return;
    r.stage = SaleStage.fiscalized;
    r.orderNum = orderNum;
    r.link = link;
    await _persist();
  }

  /// `PutKasa` пройшов.
  static Future<void> markFixed(String numNakl) async {
    final r = _find(numNakl);
    if (r == null) return;
    r.stage = SaleStage.fixed;
    await _persist();
  }

  /// Дописати примітку до запису (напр. «чек у черзі ПРРО») — щоб журнал
  /// відновлення не радив шукати те, що й так відомо.
  static Future<void> markNote(String numNakl, String note) async {
    final r = _find(numNakl);
    if (r == null) return;
    r.note = note;
    await _persist();
  }

  /// Продаж завершено повністю — прибрати з журналу.
  static Future<void> finish(String numNakl) async {
    if (_items.isEmpty) return;
    _items.removeWhere((e) => e.numNakl == numNakl);
    await _persist();
  }

  /// Продаж не відбувся ДО фіскалізації (скасована оплата карткою, відмова
  /// ПРРО) — фіскального сліду немає, добивати нічого.
  static Future<void> abort(String numNakl, String reason) async {
    final r = _find(numNakl);
    if (r == null) return;
    // Захист від помилки виклику: якщо чек уже пробитий, це НЕ abort.
    if (r.stage != SaleStage.started) {
      FiscalLog.log('A3 ⚠️ abort на стадії ${r.stage.name} проігноровано '
          '(${r.label}) — запис лишається на відновлення');
      return;
    }
    _items.removeWhere((e) => e.numNakl == numNakl);
    await _persist();
    debugPrint('SaleJournal: abort $numNakl ($reason)');
  }

  /// Добити незавершені продажі. Викликати на старті застосунку.
  ///
  /// Повертає кількість записів, які вдалося закрити.
  static Future<int> recover() async {
    await load();
    if (_items.isEmpty) return 0;

    FiscalLog.log('A3 ВІДНОВЛЕННЯ: ${_items.length} незавершених продажів '
        '(${_items.map((e) => e.label).join('; ')})');

    var closed = 0;
    for (final r in List<SaleRecord>.from(_items)) {
      r.recoverAttempts++;
      final resolved = await _recoverOne(r);
      if (resolved) {
        _items.removeWhere((e) => e.numNakl == r.numNakl);
        closed++;
      }
    }
    await _persist();
    return closed;
  }

  /// `true` — запис можна прибрати з журналу.
  static Future<bool> _recoverOne(SaleRecord r) async {
    switch (r.stage) {
      case SaleStage.started:
        // Найнеприємніший випадок: не знаємо, чи встиг пройти чек. Питаємо
        // ПРРО (та сама звірка, що й у A1). Знайшли → продаж реальний,
        // добиваємо PutKasa. Не знайшли → НЕ стверджуємо «продажу не було»
        // (ПРРО міг бути недоступний або зміна вже закрита) — лишаємо запис
        // людині.
        final check = await PrroService.findRegisteredCheck(
          localNumber: r.localNumber,
          attempts: 1,
        );
        if (check == null) {
          FiscalLog.log('A3 ${r.numNakl}: чека в зміні НЕМАЄ — продаж, схоже, '
              'обірвався до фіскалізації. Запис лишено на розгляд '
              '(спроб: ${r.recoverAttempts}'
              '${r.note != null ? ", ${r.note}" : ""}). '
              'Перевірте накладну в Caché.');
          return false;
        }
        FiscalLog.log('A3 ${r.numNakl}: чек ЗНАЙДЕНО в зміні (№${check.orderNum}) '
            '— продаж був фіскалізований, добиваємо фіксацію');
        r.stage = SaleStage.fiscalized;
        r.orderNum = check.orderNum;
        return _fixInCache(r);

      case SaleStage.fiscalized:
        // Гроші взято, чек є, але PutKasa не пройшов → у касі продаж не
        // відмічений. Це головний сценарій, заради якого журнал і робиться.
        return _fixInCache(r);

      case SaleStage.fixed:
        // Лишався тільки хвіст Лайка (orderModify/D/PutKasaSPL). Переграти
        // його наосліп не можна — бонуси нарахувались би двічі.
        FiscalLog.log('A3 ${r.numNakl}: чек і каса в порядку (№${r.orderNum}), '
            'незавершеним лишився хвіст Лайка — перевірте бонуси вручну');
        return true;
    }
  }

  static Future<bool> _fixInCache(SaleRecord r) async {
    final ok = await SessionService.putKasa(
      r.numNakl,
      r.orderNum ?? '',
      '0',
      r.link ?? '',
    );
    FiscalLog.log(ok
        ? 'A3 ${r.numNakl}: PutKasa добито (№${r.orderNum}) — продаж закрито'
        : 'A3 ${r.numNakl}: PutKasa НЕ пройшов (спроб: ${r.recoverAttempts}) — '
            'запис лишається, спробуємо на наступному старті');
    if (ok) r.stage = SaleStage.fixed;
    return ok;
  }

  static SaleRecord? _find(String numNakl) {
    for (final e in _items) {
      if (e.numNakl == numNakl) return e;
    }
    return null;
  }

  // ── internals ──────────────────────────────────────────────────────────────

  static Future<File?> _file() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persist() async {
    final file = await _file();
    if (file == null) return;
    try {
      await file.writeAsString(
        jsonEncode(_items.map((e) => e.toJson()).toList()),
        flush: true,
      );
    } catch (e) {
      debugPrint('SaleJournal persist FAIL: $e');
    }
  }

  /// Лише для тестів: скинути стан у пам'яті.
  @visibleForTesting
  static void resetForTest(List<SaleRecord> items) {
    _items = items;
    _loaded = true;
  }
}
