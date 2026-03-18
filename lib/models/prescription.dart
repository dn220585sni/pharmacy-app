import 'drug.dart';

// ── Prescription type (selected in dialog) ───────────────────────────────────

enum PrescriptionType {
  electronic,  // Електронний
  paper,       // Паперовий
  program1303, // Програма 1303
  paper1303,   // Папер. рецепт 1303
}

// ── Prescription status ──────────────────────────────────────────────────────

enum PrescriptionStatus {
  active,         // ACTIVE
  partiallyUsed,  // PARTIALLY_USED
  used,           // USED
  expired,        // EXPIRED
  rejected,       // REJECTED
}

// ── A single prescribed medication line ──────────────────────────────────────

class PrescriptionItem {
  final String helsiName;
  final int helsiQuantity;
  final String? inn;
  final double reimbursementPrice;

  const PrescriptionItem({
    required this.helsiName,
    required this.helsiQuantity,
    this.inn,
    required this.reimbursementPrice,
  });
}

// ── Match between prescription item and local inventory drug ─────────────────

class PrescriptionMatch {
  final PrescriptionItem prescriptionItem;
  final Drug drug;
  final int maxQuantity;
  final double reimbursementPrice;
  final double copayment; // drug.price - reimbursementPrice
  final int pharmacistBonus;
  final bool isInRegistry;
  bool isSelected;
  int selectedQuantity;

  PrescriptionMatch({
    required this.prescriptionItem,
    required this.drug,
    required this.maxQuantity,
    required this.reimbursementPrice,
    required this.copayment,
    this.pharmacistBonus = 0,
    this.isInRegistry = true,
    this.isSelected = false,
    this.selectedQuantity = 1,
  });

  double get totalCopayment => copayment * selectedQuantity;
  double get totalReimbursement => reimbursementPrice * selectedQuantity;
  double get totalPrice => drug.price * selectedQuantity;
}

// ── Full prescription record ─────────────────────────────────────────────────

class Prescription {
  final String number;
  final PrescriptionType type;
  final PrescriptionStatus status;
  final DateTime issueDate;
  final String medication;   // Призначення (e.g. "Амлодипін 10 MG таблетки")
  final int quantity;
  final String patientName;
  final int? patientAge;
  final String? clinicName;
  final String? doctorName;
  final String programName;
  final String uuid;
  final List<PrescriptionItem> items;
  final String? redemptionCode;

  const Prescription({
    required this.number,
    required this.type,
    required this.status,
    required this.issueDate,
    required this.medication,
    required this.quantity,
    required this.patientName,
    this.patientAge,
    this.clinicName,
    this.doctorName,
    required this.programName,
    required this.uuid,
    required this.items,
    this.redemptionCode,
  });
}

// ── Prescription data attached to CartItem ───────────────────────────────────

class PrescriptionCartData {
  final String prescriptionNumber;
  final double reimbursementPrice;
  final double copayment;
  final String programName;
  final PrescriptionType prescriptionType;
  final String? redemptionCode;

  const PrescriptionCartData({
    required this.prescriptionNumber,
    required this.reimbursementPrice,
    required this.copayment,
    required this.programName,
    required this.prescriptionType,
    this.redemptionCode,
  });

  /// Paper 1303 prescriptions don't need a redemption code.
  bool get needsRedemptionCode => prescriptionType != PrescriptionType.paper1303;
}
