/// Types of cash register operations.
enum ExpenseType {
  receipt, // Чек — completed sale
  reserve, // Резерв — reserved but not finalized
  returnOp, // Повернення — return/refund
  insurance, // Страхові
  reimbursement, // Реімбурсація
  glovo, // Glovo — delivery order
  novaPoshta, // Нова пошта — postal delivery
  prescription1303, // Рецепт 1303 — prescription-based
}

/// Status of the cash expense.
enum ExpenseStatus {
  completed, // Проведений
  reserved, // Зарезервований
  returned, // Повернений
  cancelled, // Скасований
}

/// A single item within a cash expense (receipt line).
class ExpenseItem {
  const ExpenseItem({
    required this.sku,
    required this.name,
    this.manufacturer,
    required this.quantity,
    required this.price,
    required this.total,
  });

  final String sku;
  final String name;
  final String? manufacturer;
  final double quantity;
  final double price;
  final double total;
}

/// A cash register operation (receipt / reserve / return).
class CashExpense {
  const CashExpense({
    required this.id,
    required this.receiptNumber,
    required this.dateTime,
    required this.amount,
    required this.type,
    required this.status,
    required this.clientInfo,
    required this.pharmacist,
    this.reserveNumber,
    this.returnInvoice,
    required this.register,
    this.customerPhone,
    required this.items,
  });

  final String id;
  final String receiptNumber; // e.g. "502419311"
  final DateTime dateTime;
  final double amount;
  final ExpenseType type;
  final ExpenseStatus status;
  final String clientInfo; // e.g. "КАСА 1 Новокузнецька, 27"
  final String pharmacist; // e.g. "Артюх А.Ю"
  final String? reserveNumber;
  final String? returnInvoice; // "№ накл для повернення"
  final String register; // e.g. "КАСА 1 Новокузнецька"
  final String? customerPhone;
  final List<ExpenseItem> items;

  bool get isReserve => status == ExpenseStatus.reserved;

  String get statusLabel {
    switch (status) {
      case ExpenseStatus.completed:
        return 'Проведений';
      case ExpenseStatus.reserved:
        return 'Резерв';
      case ExpenseStatus.returned:
        return 'Повернений';
      case ExpenseStatus.cancelled:
        return 'Скасований';
    }
  }

  String get typeLabel {
    switch (type) {
      case ExpenseType.receipt:
        return 'Чек';
      case ExpenseType.reserve:
        return 'Резерв';
      case ExpenseType.returnOp:
        return 'Повернення';
      case ExpenseType.insurance:
        return 'Страхові';
      case ExpenseType.reimbursement:
        return 'Реімбурсація';
      case ExpenseType.glovo:
        return 'Glovo';
      case ExpenseType.novaPoshta:
        return 'Нова пошта';
      case ExpenseType.prescription1303:
        return 'Рецепт 1303';
    }
  }
}
