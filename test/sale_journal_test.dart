import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/sale_journal.dart';

/// A3 — журнал продажу. Кожен кейс тут про гроші: запис існує рівно для того,
/// щоб продаж, обірваний між «гроші взято» і «зафіксовано в Caché», не зник
/// мовчки.
void main() {
  SaleRecord rec({
    String numNakl = '2900661785',
    SaleStage stage = SaleStage.started,
    String? orderNum,
  }) =>
      SaleRecord(
        numNakl: numNakl,
        localNumber: int.parse(numNakl),
        total: 93,
        isCard: false,
        startedAt: DateTime(2026, 8, 26, 22, 1),
        stage: stage,
        orderNum: orderNum,
      );

  group('SaleRecord серіалізація', () {
    test('round-trip зберігає стадію і фіскальний номер', () {
      final src = rec(stage: SaleStage.fiscalized, orderNum: 'lubcs0eFvXU')
        ..link = 'https://check/x'
        ..recoverAttempts = 2
        ..note = 'чек у черзі ПРРО';
      final back = SaleRecord.fromJson(src.toJson());
      expect(back.numNakl, '2900661785');
      expect(back.localNumber, 2900661785);
      expect(back.total, 93);
      expect(back.stage, SaleStage.fiscalized);
      expect(back.orderNum, 'lubcs0eFvXU');
      expect(back.link, 'https://check/x');
      expect(back.recoverAttempts, 2);
      expect(back.note, 'чек у черзі ПРРО');
      expect(back.startedAt, src.startedAt);
    });

    test('local_number рядком читається (як і в X-звіті ПРРО)', () {
      final r = SaleRecord.fromJson({
        'num_nakl': '2900661785',
        'local_number': '2900661785',
        'total': 93,
      });
      expect(r.localNumber, 2900661785);
    });

    test('невідома стадія → started (не губимо запис)', () {
      final r = SaleRecord.fromJson({
        'num_nakl': '1',
        'local_number': 1,
        'stage': 'щось_нове',
      });
      expect(r.stage, SaleStage.started);
    });
  });

  group('Стадії', () {
    setUp(() => SaleJournal.resetForTest([]));

    test('start → fiscalized → fixed → finish', () async {
      await SaleJournal.start(
        numNakl: '2900661785',
        localNumber: 2900661785,
        total: 93,
        isCard: false,
      );
      expect(SaleJournal.count, 1);
      expect(SaleJournal.pending.single.stage, SaleStage.started);

      await SaleJournal.markFiscalized('2900661785', orderNum: 'lubcs0eFvXU');
      expect(SaleJournal.pending.single.stage, SaleStage.fiscalized);
      expect(SaleJournal.pending.single.orderNum, 'lubcs0eFvXU');

      await SaleJournal.markFixed('2900661785');
      expect(SaleJournal.pending.single.stage, SaleStage.fixed);

      await SaleJournal.finish('2900661785');
      expect(SaleJournal.count, 0);
    });

    test('повторний start за тим самим NumNakl не плодить дублів', () async {
      for (var i = 0; i < 3; i++) {
        await SaleJournal.start(
          numNakl: '2900661785',
          localNumber: 2900661785,
          total: 93,
          isCard: false,
        );
      }
      expect(SaleJournal.count, 1);
    });

    test('abort прибирає запис, поки чека ще немає', () async {
      SaleJournal.resetForTest([rec()]);
      await SaleJournal.abort('2900661785', 'оплату карткою не проведено');
      expect(SaleJournal.count, 0);
    });

    test('abort ПІСЛЯ фіскалізації ігнорується — гроші вже взято', () async {
      // Якби abort спрацював, продаж із реальним чеком зник би з журналу і
      // ніхто б не добив PutKasa.
      SaleJournal.resetForTest(
          [rec(stage: SaleStage.fiscalized, orderNum: 'lubcs0eFvXU')]);
      await SaleJournal.abort('2900661785', 'помилковий виклик');
      expect(SaleJournal.count, 1);
      expect(SaleJournal.pending.single.stage, SaleStage.fiscalized);
    });

    test('позначки для невідомого NumNakl нічого не ламають', () async {
      SaleJournal.resetForTest([]);
      await SaleJournal.markFiscalized('немає такого', orderNum: 'X');
      await SaleJournal.markFixed('немає такого');
      await SaleJournal.markNote('немає такого', 'нотатка');
      await SaleJournal.finish('немає такого');
      expect(SaleJournal.count, 0);
    });

    test('журнал тримає кілька продажів окремо', () async {
      SaleJournal.resetForTest([
        rec(numNakl: '2900661785'),
        rec(numNakl: '2900661786', stage: SaleStage.fiscalized),
      ]);
      await SaleJournal.finish('2900661785');
      expect(SaleJournal.count, 1);
      expect(SaleJournal.pending.single.numNakl, '2900661786');
    });
  });

  group('label — що побачить людина в журналі', () {
    test('містить номер накладної, суму і стадію', () {
      final l = rec(stage: SaleStage.fiscalized, orderNum: 'lubcs0eFvXU').label;
      expect(l, contains('2900661785'));
      expect(l, contains('93'));
      expect(l, contains('fiscalized'));
      expect(l, contains('lubcs0eFvXU'));
    });
  });
}
