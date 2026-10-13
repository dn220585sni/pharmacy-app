import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/widgets/robot_correction_dialog.dart';

void main() {
  test('комірки робота з поля robot GetSKUprice', () {
    expect(parseRobotCells('E9,G4'), ['E9', 'G4']);
    expect(parseRobotCells(' E9; G4 '), ['E9', 'G4']);
    expect(parseRobotCells('E9'), ['E9']);
    expect(parseRobotCells(''), isEmpty);
    expect(parseRobotCells(null), isEmpty);
  });
}
