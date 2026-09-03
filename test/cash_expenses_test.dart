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

  group('типи документів за описом Катерини (03.09)', () {
    CashExpense parse(Map<String, dynamic> extra) =>
        CashExpensesService.expenseFromJson({
          'dtNakl': '31.08.2026 10:00:00',
          'NumNakl': '1',
          'sum': '10',
          'flagRRO': '1',
          'items': [],
          ...extra,
        })!;

    test('wdservice → служба доставки', () {
      expect(parse({'wdservice': 'Glovo'}).type, ExpenseType.glovo);
      expect(parse({'wdservice': 'Нова пошта'}).type, ExpenseType.novaPoshta);
    });

    test('«Рецепт беспл» → реімбурсація, звичайний рецепт → 1303', () {
      expect(parse({'tNakl': 'Рецепт беспл'}).type, ExpenseType.reimbursement);
      expect(parse({'tNakl': 'Рецепт', 'Receipt': '1303/77'}).type,
          ExpenseType.prescription1303);
    });

    test('«Терминал» і «Чек» — звичайний чек, а не окремий тип', () {
      // tNakl — тип ДОКУМЕНТА, і «Терминал» тут не робить чек особливим.
      expect(parse({'tNakl': 'Терминал'}).type, ExpenseType.receipt);
      expect(parse({'tNakl': 'Чек'}).type, ExpenseType.receipt);
    });

    test('страхування має пріоритет над рецептом', () {
      expect(parse({'exInsur': '1', 'Receipt': '55'}).type,
          ExpenseType.insurance);
    });

    test('exReturn ≠ повернення: чек лишається чеком, але статус «повернений»',
        () {
      // `exReturn` каже, що ПО ЦЬОМУ чеку є повернення, а не що він ним є.
      final e = parse({'exReturn': '1'});
      expect(e.type, ExpenseType.receipt);
      expect(e.status, ExpenseStatus.returned);
      // А ось документ повернення — це той, у якого є NumNaklForReturn.
      expect(parse({'NumNaklForReturn': '2900664544'}).type,
          ExpenseType.returnOp);
    });

    test('телефон ЖУК витягується з rezerv', () {
      expect(parse({'rezerv': 'ЖУК 0978288880'}).customerPhone, '978288880');
      // Звичайний резерв або номер ІЗ телефону не містить.
      expect(parse({'rezerv': 'Резерв 12'}).customerPhone, isNull);
      expect(parse({'rezerv': ''}).customerPhone, isNull);
    });

    test('неповний номер краще відкинути, ніж узяти обрізаним', () {
      // У прикладі Катерини «ЖУК 097828888» лише 9 цифр разом із нулем, тобто
      // на цифру менше за український мобільний. Такий номер ми не беремо:
      // показати обрізаний гірше, ніж не показати нічого.
      expect(parse({'rezerv': 'ЖУК 097828888'}).customerPhone, isNull);
    });
  });

  test('відмова (exOtkaz) має пріоритет над рештою статусів', () {
    final off = CashExpensesService.expenseFromJson({
      'dtNakl': '31.08.2026 10:00:00', 'NumNakl': '2', 'sum': '1',
      'flagRRO': '1', 'exOtkaz': '1', 'exReturn': '1', 'items': [],
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
