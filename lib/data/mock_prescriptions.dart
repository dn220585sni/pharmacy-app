import '../models/drug.dart';
import '../models/prescription.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mock e-prescriptions for development & demo.
// ─────────────────────────────────────────────────────────────────────────────

final Map<String, Prescription> mockPrescriptions = {
  '0000-5HXT-1P97-6K15': Prescription(
    number: '0000-5HXT-1P97-6K15',
    type: PrescriptionType.electronic,
    status: PrescriptionStatus.active,
    issueDate: DateTime(2026, 2, 4),
    medication: 'Амлодипін 10 MG таблетки',
    quantity: 90,
    patientName: 'Валяс Л. О.',
    patientAge: 77,
    clinicName: 'КНП «Міська поліклініка №3»',
    doctorName: 'Коваленко О.В.',
    programName:
        'Серцево-судинні та цереброваскулярні захворювання, у тому числі з первинною та вторинною профілактикою інфарктів та інсультів',
    uuid: 'b15d6bfa-66a4-40ba-9965-ef7712f48da9',
    items: const [
      PrescriptionItem(
        helsiName: 'АМЛОДИПІН САНДОЗ®',
        helsiQuantity: 3,
        inn: 'Бісопролол',
        reimbursementPrice: 55.55,
      ),
    ],
  ),
  '724618': Prescription(
    number: '724618',
    type: PrescriptionType.program1303,
    status: PrescriptionStatus.active,
    issueDate: DateTime(2026, 1, 18),
    medication: 'Метформін 500 MG таблетки',
    quantity: 60,
    patientName: 'Петренко І. С.',
    patientAge: 52,
    clinicName: 'КНП «ЦПМ СД м.Києва»',
    doctorName: 'Бондарь Т.М.',
    programName:
        'Цукровий діабет II типу — Доступні ліки',
    uuid: 'a23c8d01-9f42-4e7a-b1c3-d45678ef9012',
    items: const [
      PrescriptionItem(
        helsiName: 'МЕТФОРМІН-БХФЗ',
        helsiQuantity: 2,
        inn: 'Метформін',
        reimbursementPrice: 38.67,
      ),
    ],
  ),
  '0000-3KR9-8MN2-5T04': Prescription(
    number: '0000-3KR9-8MN2-5T04',
    type: PrescriptionType.electronic,
    status: PrescriptionStatus.active,
    issueDate: DateTime(2026, 3, 1),
    medication: 'Аторвастатин 20 MG таблетки',
    quantity: 30,
    patientName: 'Коваленко Д. А.',
    patientAge: 65,
    clinicName: 'КНП «Поліклініка №1»',
    doctorName: 'Ткачук М.В.',
    programName: 'Рецептурні лікарські засоби',
    uuid: 'f78e2b34-1a56-4cd0-9e87-123456abcdef',
    items: const [
      PrescriptionItem(
        helsiName: 'АТОРВАСТАТИН САНДОЗ',
        helsiQuantity: 1,
        inn: 'Аторвастатин',
        reimbursementPrice: 0,
      ),
    ],
  ),
};

/// Find local inventory drugs matching a prescription's items by INN.
List<PrescriptionMatch> findPrescriptionMatches(
  Prescription rx,
  List<Drug> drugs,
) {
  final matches = <PrescriptionMatch>[];
  for (final item in rx.items) {
    if (item.inn == null) continue;
    final innLower = item.inn!.toLowerCase();
    final candidates = drugs
        .where((d) =>
            d.inn != null &&
            d.inn!.toLowerCase() == innLower &&
            d.stock > 0)
        .toList();
    // Sort: lowest copayment first (best for patient)
    candidates.sort((a, b) {
      final copayA = a.price - item.reimbursementPrice;
      final copayB = b.price - item.reimbursementPrice;
      return copayA.compareTo(copayB);
    });
    for (var i = 0; i < candidates.length; i++) {
      final drug = candidates[i];
      final copay = (drug.price - item.reimbursementPrice)
          .clamp(0.0, double.infinity);
      matches.add(PrescriptionMatch(
        prescriptionItem: item,
        drug: drug,
        maxQuantity: drug.stock.clamp(0, item.helsiQuantity),
        reimbursementPrice: item.reimbursementPrice,
        copayment: copay,
        pharmacistBonus: drug.pharmacistBonus ?? 0,
        isSelected: i == 0, // auto-select best option
        selectedQuantity: drug.stock.clamp(0, item.helsiQuantity),
      ));
    }
  }
  return matches;
}
