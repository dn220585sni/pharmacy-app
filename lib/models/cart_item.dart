import 'drug.dart';
import 'prescription.dart';

class CartItem {
  final Drug drug;
  int quantity;
  int? fractionalQty; // number of blisters (null = whole package mode)
  final PrescriptionCartData? prescriptionData;

  CartItem({
    required this.drug,
    this.quantity = 1,
    this.fractionalQty,
    this.prescriptionData,
  });

  bool get isFractional => fractionalQty != null;
  bool get isPrescription => prescriptionData != null;

  double get total => isFractional
      ? drug.price * fractionalQty! / drug.unitsPerPackage!
      : drug.price * quantity;

  /// Patient copayment total (for prescription items).
  double get copaymentTotal =>
      isPrescription ? prescriptionData!.copayment * quantity : total;

  /// Display string: "2" or "2/10"
  String get displayQty => isFractional
      ? '$fractionalQty/${drug.unitsPerPackage}'
      : '$quantity';
}
