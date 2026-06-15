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

  /// Ціна за блістер (для дробового продажу) — ціна паковки / к-сть блістерів,
  /// округлена в копійку. Узгоджено з фіскальним чеком ПРРО.
  Money get blisterPriceMoney =>
      Money.fromHryvnia(effectivePrice / drug.unitsPerPackage!);

  /// Ціна позиції у копійках (без float-похибок). Для дробових позицій
  /// (блістери) — ціна за блістер × ціле число блістерів (як у чеку ПРРО),
  /// а не частка паковки — щоб кошик і фіскальний чек збігалися до копійки.
  Money get totalMoney => isFractional
      ? blisterPriceMoney * fractionalQty!
      : Money.fromHryvnia(effectivePrice) * quantity;

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
