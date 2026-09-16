import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/services/drug_service.dart';

void main() {
  group('meaningfulIntakeWarning — порожні «Особливості прийому» → null', () {
    test('лише назви категорій без тексту (косметика) — null', () {
      expect(
        meaningfulIntakeWarning(
            ':Дорослим_:Дітям_:Вагітним_:Годуючим_:Алергікам_:Водіям_:Діабетикам_'),
        isNull,
      );
      expect(meaningfulIntakeWarning(''), isNull);
      expect(meaningfulIntakeWarning(null), isNull);
      expect(meaningfulIntakeWarning('_:_'), isNull);
    });

    test('є текст або signType — лишається як є', () {
      const w = 'Можна:1:Дорослим_Тільки після їжі:2:Дітям_Не можна:3:Вагітним_';
      expect(meaningfulIntakeWarning(w), w);
      expect(meaningfulIntakeWarning(':1:Дорослим_'), ':1:Дорослим_');
      expect(meaningfulIntakeWarning('Вживайте тільки після їжі!'),
          'Вживайте тільки після їжі!');
    });

    test('SKUDetailResult.fromJson не пропускає порожню плашку', () {
      final d = SKUDetailResult.fromJson({
        'ids': '1078390',
        'intakeWarning': ':Дорослим_:Дітям_:Вагітним_',
      });
      expect(d.intakeWarning, isNull);
      expect(d.toUsageInfo(), isNull);
      final m = SKUDetailResult.fromJson({'intakeWarning': 'Можна:1:Дорослим_'});
      expect(m.intakeWarning, 'Можна:1:Дорослим_');
    });
  });
}
