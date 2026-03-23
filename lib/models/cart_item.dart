import 'drug.dart';
import 'prescription.dart';

class CartItem {
  final Drug drug;
  int quantity;
  int? fractionalQty; // number of blisters (null = whole package mode)
  final PrescriptionCartData? prescriptionData;

  /// Discounted unit price (e.g. from "Рука допомоги"). null = no discount.
  final double? discountPrice;

  CartItem({
    required this.drug,
    this.quantity = 1,
    this.fractionalQty,
    this.prescriptionData,
    this.discountPrice,
  });

  bool get isFractional => fractionalQty != null;
  bool get isPrescription => prescriptionData != null;
  bool get hasDiscount => discountPrice != null;

  /// Effective unit price (discount or original).
  double get effectivePrice => discountPrice ?? drug.price;

  double get total => isFractional
      ? effectivePrice * fractionalQty! / drug.unitsPerPackage!
      : effectivePrice * quantity;

  /// Patient copayment total (for prescription items).
  double get copaymentTotal =>
      isPrescription ? prescriptionData!.copayment * quantity : total;

  /// Display string: "2" or "2/10"
  String get displayQty => isFractional
      ? '$fractionalQty/${drug.unitsPerPackage}'
      : '$quantity';
}
