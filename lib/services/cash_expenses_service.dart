import 'package:flutter/foundation.dart';
import '../models/cash_expense.dart';
import '../utils/json_num.dart';
import '../utils/phone.dart';
import 'api_config.dart';
import 'cache_api_client.dart';
import 'fiscal_log.dart';

/// «Витрати по касі» — накладні каси за період.
///
/// `GetNaklKas&dateFrom=31.08.2026&dateTo=31.08.2026&KodKli=1334`
/// → `{"Status":"OK","Nakls":[{... "items":[...]}]}`
///
/// Сервіс написаний Катериною спеціально під цей екран (01.09).
class CashExpensesService {
  /// Формат дат, який приймає сервіс: `31.08.2026`.
  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// `31.08.2026 08:01:19` → DateTime. `null` при будь-якому відхиленні —
  /// краще пропустити рядок, ніж показати накладну з датою «зараз».
  static DateTime? parseNaklDate(String raw) {
    final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})[ T](\d{2}):(\d{2}):(\d{2})')
        .firstMatch(raw.trim());
    if (m == null) return null;
    return DateTime(
      int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!),
      int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!),
    );
  }

  static bool _flag(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isNotEmpty && s != '0';
  }

  static bool _isGlovo(String s) => s.toLowerCase().contains('glovo');

  static bool _isNovaPoshta(String s) {
    final t = s.toLowerCase();
    return t.contains('пошт') || t.contains('нп') || t.contains('poshta');
  }

  /// Телефон із поля `rezerv` — там він буває у вигляді «ЖУК 097828888».
  /// `null`, якщо схожого на номер там немає (звичайний резерв або номер ІЗ).
  static String? _phoneFrom(String rezerv) {
    final m = RegExp(r'(?:\+?38)?0?(\d{9})(?!\d)').firstMatch(rezerv);
    if (m == null) return null;
    final digits = nationalDigits(m[0]!);
    return digits.length == 9 ? digits : null;
  }

  /// Розібрати одну накладну. `null` — рядок без дати або без номера.
  static CashExpense? expenseFromJson(Map<String, dynamic> j) {
    final when = parseNaklDate(j['dtNakl']?.toString() ?? '');
    final num_ = j['NumNakl']?.toString() ?? '';
    if (when == null || num_.isEmpty) return null;

    // Поля за описом Катерини (03.09):
    //   tNakl      — ТИП документа: «Организация» / «Чек» / «Рецепт» /
    //                «Рецепт беспл» / «Терминал» (не спосіб оплати);
    //   rezerv     — резерв АБО номер ІЗ, або «ЖУК <телефон>»;
    //   flagRRO    — чек проведено через РРО;
    //   Receipt    — № рецепта (реімбурсація, 1303 тощо);
    //   wdservice  — служба доставки;
    //   exReturn   — для цього чека Є повернення (сам чек не є поверненням);
    //   exOtkaz    — відмова клієнта або аптеки;
    //   exInsur    — продаж за страхуванням.
    final reserve = j['rezerv']?.toString().trim() ?? '';
    final returnFor = j['NumNaklForReturn']?.toString().trim() ?? '';
    final receiptNo = j['Receipt']?.toString().trim() ?? '';
    final delivery = j['wdservice']?.toString().trim() ?? '';
    final tNakl = j['tNakl']?.toString().trim() ?? '';
    final fiscalized = _flag(j['flagRRO']);
    final hasReturn = _flag(j['exReturn']);
    final refused = _flag(j['exOtkaz']);
    final insurance = _flag(j['exInsur']);

    // Резерв = не проведено через РРО. `rezerv` для цього не годиться: воно
    // може нести і номер ІЗ, і телефон ЖУК у цілком проведеному чеку.
    final isReserve = !fiscalized;

    final items = (j['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((i) => ExpenseItem(
              sku: i['skod']?.toString() ?? '',
              name: i['nametov']?.toString() ?? '',
              manufacturer: i['nameproiz']?.toString(),
              quantity: flexDouble(i['kol']) ?? 0,
              price: flexDouble(i['price']) ?? 0,
              total: flexDouble(i['sum']) ?? 0,
            ))
        .toList(growable: false);

    return CashExpense(
      id: num_,
      receiptNumber: num_,
      dateTime: when,
      amount: flexDouble(j['sum']) ?? 0,
      // Порядок важливий: спершу те, що однозначно визначає документ
      // (повернення, страхування), далі доставка й рецепт, і аж потім резерв.
      type: switch (true) {
        // Сам документ Є поверненням — на відміну від `exReturn`, який лише
        // каже, що ПО ЦЬОМУ чеку колись оформили повернення.
        _ when returnFor.isNotEmpty => ExpenseType.returnOp,
        _ when insurance => ExpenseType.insurance,
        _ when _isGlovo(delivery) => ExpenseType.glovo,
        _ when _isNovaPoshta(delivery) => ExpenseType.novaPoshta,
        // «Рецепт беспл» — безоплатний, тобто відшкодування; звичайний
        // «Рецепт» із номером — пільговий за 1303.
        _ when tNakl.toLowerCase().contains('беспл') =>
          ExpenseType.reimbursement,
        _ when receiptNo.isNotEmpty || tNakl.toLowerCase().contains('рецепт') =>
          ExpenseType.prescription1303,
        _ when isReserve => ExpenseType.reserve,
        _ => ExpenseType.receipt,
      },
      status: switch (true) {
        _ when refused => ExpenseStatus.cancelled,
        _ when hasReturn => ExpenseStatus.returned,
        _ when isReserve => ExpenseStatus.reserved,
        _ => ExpenseStatus.completed,
      },
      clientInfo: j['ekkKliName']?.toString() ?? '',
      pharmacist: j['user']?.toString() ?? '',
      reserveNumber: reserve.isEmpty ? null : reserve,
      returnInvoice: returnFor.isEmpty ? null : returnFor,
      register: j['ekkKliName']?.toString() ?? '',
      // Окремого поля телефону немає, але для ЖУК він лежить у `rezerv`
      // («ЖУК 097828888») — за описом Катерини. Витягуємо тільки звідти;
      // `SpartaCard` у це поле не підставляємо: інша сутність.
      customerPhone: _phoneFrom(reserve),
      items: items,
    );
  }

  /// Накладні каси за період. Порожній список = або справді порожньо, або
  /// сервіс не відповів — розрізняти нема потреби, екран в обох випадках
  /// показує «нічого не знайдено».
  static Future<List<CashExpense>> fetch({
    required DateTime from,
    required DateTime to,
  }) async {
    if (ApiConfig.useMock) return const [];
    try {
      final r = await CacheApiClient().call('GetNaklKas', params: {
        'dateFrom': _fmt(from),
        'dateTo': _fmt(to),
        'KodKli': ApiConfig.ekkKodKli,
      });
      if (!r.isOk) {
        FiscalLog.log('GetNaklKas FAIL (${_fmt(from)}–${_fmt(to)}, '
            'KodKli=${ApiConfig.ekkKodKli}): ${r.result}');
        return const [];
      }
      final raw = (r.data['Nakls'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final parsed = raw
          .map(expenseFromJson)
          .whereType<CashExpense>()
          .toList(growable: false);
      if (parsed.length != raw.length) {
        FiscalLog.log('GetNaklKas: ${raw.length - parsed.length} з '
            '${raw.length} накладних не розібрано (немає дати або номера)');
      }
      debugPrint('GetNaklKas ${_fmt(from)}–${_fmt(to)}: '
          '${parsed.length} накладних');
      return parsed;
    } catch (e) {
      FiscalLog.log('GetNaklKas ERROR: $e');
      return const [];
    }
  }
}
