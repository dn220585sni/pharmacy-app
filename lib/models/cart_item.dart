import 'drug.dart';
import 'money.dart';
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

  /// Ціна позиції у копійках (без float-похибок). Для дробових позицій
  /// (блістери) — частка ціни паковки, округлена в копійку.
  Money get totalMoney {
    final unit = Money.fromHryvnia(effectivePrice);
    return isFractional
        ? unit.fraction(fractionalQty!, drug.unitsPerPackage!)
        : unit * quantity;
  }

  double get total => totalMoney.toHryvnia();

  /// Сума співоплати пацієнта у копійках (для рецептурних позицій).
  Money get copaymentTotalMoney => isPrescription
      ? Money.fromHryvnia(prescriptionData!.copayment) * quantity
      : totalMoney;

  /// Patient copayment total (for prescription items).
  double get copaymentTotal => copaymentTotalMoney.toHryvnia();

  /// Display string: "2" or "2/10"
  String get displayQty => isFractional
      ? '$fractionalQty/${drug.unitsPerPackage}'
      : '$quantity';
}
