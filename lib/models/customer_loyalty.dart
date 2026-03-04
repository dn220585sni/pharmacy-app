/// Result from loyalty service after phone lookup.
class CustomerLoyalty {
  final String phone;
  final double bonusBalance; // bonus points in ₴
  const CustomerLoyalty({required this.phone, required this.bonusBalance});
}
