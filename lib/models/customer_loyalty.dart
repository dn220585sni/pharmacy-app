/// Result from loyalty service after phone lookup.
class CustomerLoyalty {
  final String phone;
  final double bonusBalance; // bonus points in ₴
  final String? cardNo;      // SPL card number (for sale API)
  final String? firstName;
  final String? lastName;

  /// Анкетне «Получать эл-й чек» — сире значення поля `cashreceipt` з
  /// `addonsList` (Спарта, `customer/find`).
  ///
  /// `null` — анкети немає або поле не прийшло. Розбирає це
  /// `ReceiptPrintRule.electronicFromAnketa`: `yes` означає ЕЛЕКТРОННИЙ чек,
  /// тобто папір НЕ друкуємо, `no` — друкуємо.
  final String? cashReceipt;

  const CustomerLoyalty({
    required this.phone,
    required this.bonusBalance,
    this.cardNo,
    this.firstName,
    this.lastName,
    this.cashReceipt,
  });
}
