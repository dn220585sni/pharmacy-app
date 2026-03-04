import 'drug.dart';

class CartItem {
  final Drug drug;
  int quantity;
  int? fractionalQty; // number of blisters (null = whole package mode)

  CartItem({
    required this.drug,
    this.quantity = 1,
    this.fractionalQty,
  });

  bool get isFractional => fractionalQty != null;

  double get total => isFractional
      ? drug.price * fractionalQty! / drug.unitsPerPackage!
      : drug.price * quantity;

  /// Display string: "2" or "2/10"
  String get displayQty => isFractional
      ? '$fractionalQty/${drug.unitsPerPackage}'
      : '$quantity';
}
