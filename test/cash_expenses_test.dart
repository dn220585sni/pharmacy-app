import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/cash_expense.dart';
import 'package:pharmacy_app/services/cash_expenses_service.dart';

/// Розбір `GetNaklKas` — сервіс під екран «Витрати по касі».
///
/// Фікстура — точний фрагмент відповіді тестової каси (01.09), включно з
/// числами В РЯДКАХ («125.00», «1.000») і рядком «Знижка на чек» без skod.
void main() {
  const raw = '''
{"Status":"OK","Nakls":[
{"dtNakl":"31.08.2026 08:01:19","NumNakl":"2900664544","sum":"125.00",
 "prcdisc":"0.00","tNakl":"Терминал","KliName":"Приват Банк",
 "user":"Вініченко Г.Г.","rezerv":"","pdv":"1","flagRRO":"1",
 "NumNaklForReturn":"","ekkKliName":"КАССА 1, Шевченко б-р, 71 (Копейка)",
 "SpartaCard":"2880178496526","SpisBonus":"0.00","FNRRO":"4HzVgFpPpv8",
 "exReturn":"0","exOtkaz":"","exInsur":"0","idorder":"",
 "items":[{"skod":"26258247","nametov":"ФАРМАДЕКС ГЛАЗ. КАПЛИ 10 МЛ",
   "nameproiz":"Фармак (Украина, Киев)*","kol":"1.000","price":"125.00",
   "sum":"125.00","pdv":"7"}]},
{"dtNakl":"31.08.2026 08:09:42","NumNakl":"2900664546","sum":"1686.21",
 "prcdisc":"-5.00","tNakl":"Терминал","KliName":"Приват Банк",
 "user":"Вініченко Г.Г.","rezerv":"","pdv":"1","flagRRO":"1",
 "NumNaklForReturn":"","ekkKliName":"КАССА 1, Шевченко б-р, 71 (Копейка)",
 "exReturn":"0","exOtkaz":"","exInsur":"0",
 "items":[{"skod":"26215020","nametov":"ЭГИЛОК 50 МГ №60","nameproiz":"Egis",
   "kol":"1.000","price":"116.08","sum":"116.08","pdv":"7"},
  {"skod":"","nametov":"Знижка на чек","nameproiz":"","kol":"1.000",
   "price":"-88.74","sum":"-88.74","pdv":""}]}
]}''';

  List<CashExpense> parseAll() {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return (json['Nakls'] as List)
        .cast<Map<String, dynamic>>()
        .map(CashExpensesService.expenseFromJson)
        .whereType<CashExpense>()
        .toList();
  }

  test('дата з формату каси «31.08.2026 08:01:19»', () {
    final d = CashExpensesService.parseNaklDate('31.08.2026 08:01:19');
    expect(d, DateTime(2026, 8, 31, 8, 1, 19));
  });

  test('крива дата → null, а не «зараз»', () {
    expect(CashExpensesService.parseNaklDate(''), isNull);
    expect(CashExpensesService.parseNaklDate('31.08.2026'), isNull);
    expect(CashExpensesService.parseNaklDate('сьогодні'), isNull);
  });

  test('числа приходять РЯДКАМИ — читаються як числа', () {
    final e = parseAll().first;
    expect(e.amount, 125.00);
    expect(e.items.single.quantity, 1.0);
    expect(e.items.single.price, 125.00);
  });

  test('проведений чек: flagRRO=1 → completed / receipt', () {
    final e = parseAll().first;
    expect(e.status, ExpenseStatus.completed);
    expect(e.type, ExpenseType.receipt);
    expect(e.receiptNumber, '2900664544');
    expect(e.pharmacist, 'Вініченко Г.Г.');
    expect(e.register, 'КАССА 1, Шевченко б-р, 71 (Копейка)');
  });

  test('рядок «Знижка на чек» без skod лишається в позиціях', () {
    // Він потрібен, щоб сума позицій сходилась із сумою чека; для підпису
    // список фільтрується за непорожнім skod уже в UI.
    final e = parseAll().last;
    expect(e.items.length, 2);
    expect(e.items.last.sku, isEmpty);
    expect(e.items.last.total, -88.74);
    expect(
      e.items.fold<double>(0, (s, i) => s + i.total),
      closeTo(27.34, 0.001),
    );
  });

  test('резерв = накладна без фіскального чека', () {
    final e = CashExpensesService.expenseFromJson({
      'dtNakl': '31.08.2026 10:00:00',
      'NumNakl': '2900664999',
      'sum': '50.00',
      'flagRRO': '0',
      'items': [],
    });
    expect(e!.status, ExpenseStatus.reserved);
    expect(e.type, ExpenseType.reserve);
  });

  test('повернення й відмова визначаються прапорцями', () {
    final ret = CashExpensesService.expenseFromJson({
      'dtNakl': '31.08.2026 10:00:00', 'NumNakl': '1', 'sum': '1',
      'flagRRO': '1', 'exReturn': '1', 'items': [],
    });
    expect(ret!.status, ExpenseStatus.returned);
    expect(ret.type, ExpenseType.returnOp);

    final off = CashExpensesService.expenseFromJson({
      'dtNakl': '31.08.2026 10:00:00', 'NumNakl': '2', 'sum': '1',
      'flagRRO': '1', 'exOtkaz': '1', 'items': [],
    });
    expect(off!.status, ExpenseStatus.cancelled);
  });

  test('накладна без дати або номера відкидається, решта лишається', () {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['Nakls'] as List).cast<Map<String, dynamic>>().toList()
      ..add({'dtNakl': '', 'NumNakl': '', 'sum': '5'});
    final parsed =
        list.map(CashExpensesService.expenseFromJson).whereType<CashExpense>();
    expect(parsed.length, 2);
  });
}
