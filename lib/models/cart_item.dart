import 'drug.dart';

class CartItem {
  final Drug drug;
  int quantity;

  CartItem({
    required this.drug,
    this.quantity = 1,
  });

  double get total => drug.price * quantity;
}
