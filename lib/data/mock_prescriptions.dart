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

  // ── Електронний: 100% реімбурсація ────────────────────────────────────
  '0000-9WQ4-7LB3-2H68': Prescription(
    number: '0000-9WQ4-7LB3-2H68',
    type: PrescriptionType.electronic,
    status: PrescriptionStatus.active,
    issueDate: DateTime(2026, 3, 10),
    medication: 'Лоратадин 10 MG таблетки',
    quantity: 20,
    patientName: 'Мельник О. Г.',
    patientAge: 34,
    clinicName: 'КНП «Амбулаторія ЗПСМ №7»',
    doctorName: 'Савченко І.П.',
    programName:
        'Бронхіальна астма та ХОЗЛ — Доступні ліки',
    uuid: 'c42d7e19-3b56-4af0-81c2-987654fedcba',
    items: const [
      PrescriptionItem(
        helsiName: 'ЛОРАТАДИН-ТЕВА',
        helsiQuantity: 2,
        inn: 'Лоратадин',
        reimbursementPrice: 45.20,
      ),
    ],
  ),

  // ── Електронний: частково використаний ─────────────────────────────────
  '0000-2FN8-4KP1-7R53': Prescription(
    number: '0000-2FN8-4KP1-7R53',
    type: PrescriptionType.electronic,
    status: PrescriptionStatus.partiallyUsed,
    issueDate: DateTime(2026, 2, 20),
    medication: 'Омепразол 20 MG капсули',
    quantity: 28,
    patientName: 'Бондаренко В. С.',
    patientAge: 48,
    clinicName: 'КНП «Міська лікарня №5»',
    doctorName: 'Яковлєва Н.М.',
    programName: 'Рецептурні лікарські засоби',
    uuid: 'd56e3a72-8c14-4bf9-a0d1-abcdef123456',
    items: const [
      PrescriptionItem(
        helsiName: 'ОМЕПРАЗОЛ-ТЕВА',
        helsiQuantity: 2,
        inn: 'Омепразол',
        reimbursementPrice: 28.90,
      ),
    ],
  ),

  // ── Програма 1303: Бісопролол ─────────────────────────────────────────
  '385201': Prescription(
    number: '385201',
    type: PrescriptionType.program1303,
    status: PrescriptionStatus.active,
    issueDate: DateTime(2026, 3, 5),
    medication: 'Бісопролол 5 MG таблетки',
    quantity: 30,
    patientName: 'Шевченко Г. М.',
    patientAge: 62,
    clinicName: 'КНП «Поліклініка №2»',
    doctorName: 'Литвиненко В.А.',
    programName:
        'Серцево-судинні захворювання — Доступні ліки (1303)',
    uuid: 'e67f4b83-9d25-4ca0-b1e2-bcdef2345678',
    items: const [
      PrescriptionItem(
        helsiName: 'БІСОПРОЛОЛ-РАТІОФАРМ',
        helsiQuantity: 1,
        inn: 'Бісопролол',
        reimbursementPrice: 52.30,
      ),
    ],
  ),

  // ── Програма 1303: Еналаприл ──────────────────────────────────────────
  '917432': Prescription(
    number: '917432',
    type: PrescriptionType.program1303,
    status: PrescriptionStatus.active,
    issueDate: DateTime(2026, 3, 12),
    medication: 'Еналаприл 10 MG таблетки',
    quantity: 60,
    patientName: 'Ткаченко А. П.',
    patientAge: 58,
    clinicName: 'КНП «Амбулаторія ЗПСМ №12»',
    doctorName: 'Марчук О.І.',
    programName:
        'Артеріальна гіпертензія — Доступні ліки (1303)',
    uuid: 'f89a5c94-0e36-4db1-c2f3-cdefg3456789',
    items: const [
      PrescriptionItem(
        helsiName: 'ЕНАЛАПРИЛ-ЗДОРОВ\'Я',
        helsiQuantity: 2,
        inn: 'Еналаприл',
        reimbursementPrice: 18.50,
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
