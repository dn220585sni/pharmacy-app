/// Result from loyalty service after phone lookup.
class CustomerLoyalty {
  final String phone;
  final double bonusBalance; // bonus points in ₴
  final String? cardNo;      // SPL card number (for sale API)
  final String? firstName;
  final String? lastName;
  const CustomerLoyalty({
    required this.phone,
    required this.bonusBalance,
    this.cardNo,
    this.firstName,
    this.lastName,
  });
}
