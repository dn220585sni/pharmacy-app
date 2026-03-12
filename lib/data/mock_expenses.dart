import '../models/cash_expense.dart';

/// Mock cash register expenses based on the legacy "Витрати по касі" screen.
final List<CashExpense> mockExpenses = [
  // ── Recent (within 30 min) — for testing active return button ──────────────
  CashExpense(
    id: 'exp-00',
    receiptNumber: '502419350',
    dateTime: DateTime.now().subtract(const Duration(minutes: 12)),
    amount: 178.10,
    type: ExpenseType.receipt,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Артюх А.Ю',
    register: 'КАСА 1 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '26883210',
        name: 'ЕНТЕРОСГЕЛЬ ПАСТА 135Г',
        manufacturer: 'Креома-Фарм',
        quantity: 1,
        price: 178.10,
        total: 178.10,
      ),
    ],
  ),

  // ── 10.03.2026 ─────────────────────────────────────────────────────────────
  CashExpense(
    id: 'exp-01',
    receiptNumber: '502419311',
    dateTime: DateTime(2026, 3, 10, 10, 31, 17),
    amount: 320.50,

    type: ExpenseType.receipt,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Артюх А.Ю',
    reserveNumber: '165070725',
    register: 'КАСА 1 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '27103951',
        name: 'ДИОКОР ТАБЛ. 80МГ/12,5МГ №30',
        manufacturer: 'Асіно Україна',
        quantity: 0.67,
        price: 280.15,
        total: 186.77,
      ),
      ExpenseItem(
        sku: '',
        name: 'Знижка на чек',
        quantity: 1,
        price: -0.27,
        total: -0.27,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-02',
    receiptNumber: '502419310',
    dateTime: DateTime(2026, 3, 10, 10, 29, 30),
    amount: 127.00,

    type: ExpenseType.receipt,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Артюх А.Ю',
    reserveNumber: '165070322',
    register: 'КАСА 1 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '26883210',
        name: 'ЕНТЕРОСГЕЛЬ ПАСТА 135Г',
        manufacturer: 'Креома-Фарм',
        quantity: 1,
        price: 178.10,
        total: 127.00,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-03',
    receiptNumber: '502419290',
    dateTime: DateTime(2026, 3, 10, 9, 50, 36),
    amount: 203.00,

    type: ExpenseType.receipt,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Артюх А.Ю',
    reserveNumber: '165062539',
    register: 'КАСА 1 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '26771903',
        name: 'МЕЛОКСИКАМ-ТЕВА ТАБЛ. 15МГ №20',
        manufacturer: 'Тева',
        quantity: 1,
        price: 240.00,
        total: 203.00,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-04',
    receiptNumber: '502419277',
    dateTime: DateTime(2026, 3, 10, 9, 10, 2),
    amount: 586.00,

    type: ExpenseType.reserve,
    status: ExpenseStatus.reserved,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Артюх А.Ю',
    reserveNumber: '165054335',
    register: 'КАСА 1 Новокузнецька',
    customerPhone: '+380671234567',
    items: const [
      ExpenseItem(
        sku: '26890213',
        name: 'СІОФОР ХР ТАБЛ. 500МГ №60',
        manufacturer: 'Берлін-Хемі',
        quantity: 2,
        price: 339.00,
        total: 586.00,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-05',
    receiptNumber: '502419276',
    dateTime: DateTime(2026, 3, 10, 9, 9, 10),
    amount: 101.00,

    type: ExpenseType.receipt,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Артюх А.Ю',
    reserveNumber: '165052670',
    register: 'КАСА 1 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '26345670',
        name: 'ДОППЕЛЬГЕРЦ АКТИВ МАГНІЙ + В6 №30',
        manufacturer: 'Queisser Pharma',
        quantity: 1,
        price: 119.00,
        total: 101.00,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-06',
    receiptNumber: '502419269',
    dateTime: DateTime(2026, 3, 10, 8, 42, 46),
    amount: 326.00,

    type: ExpenseType.receipt,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Чирва С.В',
    reserveNumber: '165050445',
    register: 'КАСА 1 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '25487201',
        name: 'ЦИПРОФЛОКСАЦИН ТАБЛ. 500МГ №10',
        manufacturer: 'Дарниця',
        quantity: 2,
        price: 89.50,
        total: 179.00,
      ),
      ExpenseItem(
        sku: '26993528',
        name: 'ПЕЧАЄВСЬКІ ТАБ ВІД ІЗЖОГИ №20',
        manufacturer: 'Технолог',
        quantity: 1,
        price: 69.89,
        total: 69.89,
      ),
      ExpenseItem(
        sku: '',
        name: 'Знижка на чек',
        quantity: 1,
        price: -1.50,
        total: -1.50,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-07',
    receiptNumber: '502419262',
    dateTime: DateTime(2026, 3, 10, 8, 21, 43),
    amount: 1079.00,

    type: ExpenseType.reserve,
    status: ExpenseStatus.reserved,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Чирва С.В',
    reserveNumber: '165047025',
    register: 'КАСА 1 Новокузнецька',
    customerPhone: '+380509876543',
    items: const [
      ExpenseItem(
        sku: '27103951',
        name: 'ДИОКОР ТАБЛ. 80МГ/12,5МГ №30',
        manufacturer: 'Асіно Україна',
        quantity: 3,
        price: 280.15,
        total: 840.45,
      ),
      ExpenseItem(
        sku: '26890213',
        name: 'СІОФОР ХР ТАБЛ. 500МГ №60',
        manufacturer: 'Берлін-Хемі',
        quantity: 1,
        price: 339.00,
        total: 339.00,
      ),
      ExpenseItem(
        sku: '',
        name: 'Знижка на чек',
        quantity: 1,
        price: -100.45,
        total: -100.45,
      ),
    ],
  ),

  // ── 09.03.2026 ─────────────────────────────────────────────────────────────
  CashExpense(
    id: 'exp-08',
    receiptNumber: '502419243',
    dateTime: DateTime(2026, 3, 9, 19, 42, 23),
    amount: 165.00,

    type: ExpenseType.receipt,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 2 Новокузнецька, 27',
    pharmacist: 'Сідєльнікова С.П.',
    reserveNumber: '165037854',
    register: 'КАСА 2 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '26771903',
        name: 'МЕЛОКСИКАМ-ТЕВА ТАБЛ. 15МГ №20',
        manufacturer: 'Тева',
        quantity: 1,
        price: 240.00,
        total: 165.00,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-09',
    receiptNumber: '502419239',
    dateTime: DateTime(2026, 3, 9, 15, 56, 8),
    amount: 250.50,

    type: ExpenseType.returnOp,
    status: ExpenseStatus.returned,
    clientInfo: 'КАСА 2 Новокузнецька, 27',
    pharmacist: 'Чирва С.В',
    reserveNumber: '164987062',
    returnInvoice: 'ПН-00234',
    register: 'КАСА 2 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '26890213',
        name: 'СІОФОР ХР ТАБЛ. 500МГ №60',
        manufacturer: 'Берлін-Хемі',
        quantity: 1,
        price: 339.00,
        total: 250.50,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-10',
    receiptNumber: '502419231',
    dateTime: DateTime(2026, 3, 9, 11, 24, 3),
    amount: 180.00,

    type: ExpenseType.insurance,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Мартинюк О.О.',
    reserveNumber: '164934862',
    register: 'КАСА 3 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '26345670',
        name: 'ДОППЕЛЬГЕРЦ АКТИВ МАГНІЙ + В6 №30',
        manufacturer: 'Queisser Pharma',
        quantity: 2,
        price: 119.00,
        total: 180.00,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-11',
    receiptNumber: '502419024',
    dateTime: DateTime(2026, 3, 9, 9, 32, 59),
    amount: 1086.50,

    type: ExpenseType.receipt,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 2 Новокузнецька, 27',
    pharmacist: 'Чирва С.В',
    reserveNumber: '164910617',
    register: 'КАСА 2 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '27103951',
        name: 'ДИОКОР ТАБЛ. 80МГ/12,5МГ №30',
        manufacturer: 'Асіно Україна',
        quantity: 3,
        price: 280.15,
        total: 840.45,
      ),
      ExpenseItem(
        sku: '26993528',
        name: 'ПЕЧАЄВСЬКІ ТАБ ВІД ІЗЖОГИ №20',
        manufacturer: 'Технолог',
        quantity: 2,
        price: 69.89,
        total: 139.78,
      ),
      ExpenseItem(
        sku: '25487201',
        name: 'ЦИПРОФЛОКСАЦИН ТАБЛ. 500МГ №10',
        manufacturer: 'Дарниця',
        quantity: 1,
        price: 89.50,
        total: 89.50,
      ),
      ExpenseItem(
        sku: '',
        name: 'Знижка на чек',
        quantity: 1,
        price: -16.77,
        total: -16.77,
      ),
    ],
  ),

  // ── 08.03.2026 ─────────────────────────────────────────────────────────────
  CashExpense(
    id: 'exp-12',
    receiptNumber: '502418903',
    dateTime: DateTime(2026, 3, 8, 18, 20, 44),
    amount: 307.50,

    type: ExpenseType.reimbursement,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Чирва С.В',
    reserveNumber: '164895321',
    register: 'КАСА 2 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '26883210',
        name: 'ЕНТЕРОСГЕЛЬ ПАСТА 135Г',
        manufacturer: 'Креома-Фарм',
        quantity: 1,
        price: 178.10,
        total: 178.10,
      ),
      ExpenseItem(
        sku: '26771903',
        name: 'МЕЛОКСИКАМ-ТЕВА ТАБЛ. 15МГ №20',
        manufacturer: 'Тева',
        quantity: 1,
        price: 240.00,
        total: 129.40,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-13',
    receiptNumber: '502418889',
    dateTime: DateTime(2026, 3, 8, 12, 56, 46),
    amount: 39.50,

    type: ExpenseType.receipt,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 2 Новокузнецька, 27',
    pharmacist: 'Мохно Н.В.',
    reserveNumber: '164833007',
    register: 'КАСА 2 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '26993528',
        name: 'ПЕЧАЄВСЬКІ ТАБ ВІД ІЗЖОГИ №20',
        manufacturer: 'Технолог',
        quantity: 0.5,
        price: 69.89,
        total: 34.95,
      ),
      ExpenseItem(
        sku: '',
        name: 'Знижка на чек',
        quantity: 1,
        price: -0.27,
        total: -0.27,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-14',
    receiptNumber: '502418849',
    dateTime: DateTime(2026, 3, 8, 10, 41, 9),
    amount: 89.50,

    type: ExpenseType.receipt,
    status: ExpenseStatus.completed,
    clientInfo: 'КАСА 1 Новокузнецька, 27',
    pharmacist: 'Мохно Н.В.',
    reserveNumber: '164821089',
    register: 'КАСА 1 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '25487201',
        name: 'ЦИПРОФЛОКСАЦИН ТАБЛ. 500МГ №10',
        manufacturer: 'Дарниця',
        quantity: 1,
        price: 89.50,
        total: 89.50,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-15',
    receiptNumber: '502418750',
    dateTime: DateTime(2026, 3, 8, 8, 38, 56),
    amount: 63.00,

    type: ExpenseType.reserve,
    status: ExpenseStatus.reserved,
    clientInfo: 'КАСА 2 Новокузнецька, 27',
    pharmacist: 'Сідєльнікова С.П.',
    reserveNumber: '164804246',
    register: 'КАСА 1 Новокузнецька',
    customerPhone: '+380931112233',
    items: const [
      ExpenseItem(
        sku: '26993528',
        name: 'ПЕЧАЄВСЬКІ ТАБ ВІД ІЗЖОГИ №20',
        manufacturer: 'Технолог',
        quantity: 1,
        price: 69.89,
        total: 63.00,
      ),
    ],
  ),

  // ── Glovo ─────────────────────────────────────────────────────────────────
  CashExpense(
    id: 'exp-16',
    receiptNumber: '502419400',
    dateTime: DateTime(2026, 3, 10, 14, 12, 5),
    amount: 445.00,
    type: ExpenseType.glovo,
    status: ExpenseStatus.completed,
    clientInfo: 'Glovo #GL-88421',
    pharmacist: 'Чирва С.В',
    register: 'КАСА 1 Новокузнецька',
    customerPhone: '+380661234567',
    items: const [
      ExpenseItem(
        sku: '27103951',
        name: 'ДИОКОР ТАБЛ. 80МГ/12,5МГ №30',
        manufacturer: 'Асіно Україна',
        quantity: 1,
        price: 280.15,
        total: 280.15,
      ),
      ExpenseItem(
        sku: '26345670',
        name: 'ДОППЕЛЬГЕРЦ АКТ ВІТАМІН D3 2000 №60',
        manufacturer: 'Queisser Pharma',
        quantity: 1,
        price: 164.85,
        total: 164.85,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-17',
    receiptNumber: '502419055',
    dateTime: DateTime(2026, 3, 9, 16, 45, 12),
    amount: 178.10,
    type: ExpenseType.glovo,
    status: ExpenseStatus.completed,
    clientInfo: 'Glovo #GL-87956',
    pharmacist: 'Артюх А.Ю',
    register: 'КАСА 2 Новокузнецька',
    items: const [
      ExpenseItem(
        sku: '26883210',
        name: 'ЕНТЕРОСГЕЛЬ ПАСТА 135Г',
        manufacturer: 'Креома-Фарм',
        quantity: 1,
        price: 178.10,
        total: 178.10,
      ),
    ],
  ),

  // ── Нова пошта ────────────────────────────────────────────────────────────
  CashExpense(
    id: 'exp-18',
    receiptNumber: '502419320',
    dateTime: DateTime(2026, 3, 10, 11, 8, 33),
    amount: 529.50,
    type: ExpenseType.novaPoshta,
    status: ExpenseStatus.completed,
    clientInfo: 'НП ТТН 20450073812456',
    pharmacist: 'Мартинюк О.О.',
    register: 'КАСА 1 Новокузнецька',
    customerPhone: '+380507778899',
    items: const [
      ExpenseItem(
        sku: '25487201',
        name: 'ЦИПРОФЛОКСАЦИН ТАБЛ. 500МГ №10',
        manufacturer: 'Дарниця',
        quantity: 2,
        price: 89.50,
        total: 179.00,
      ),
      ExpenseItem(
        sku: '26890213',
        name: 'СІОФОР 500 ТАБЛ. №60',
        manufacturer: 'Berlin-Chemie',
        quantity: 1,
        price: 350.50,
        total: 350.50,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-19',
    receiptNumber: '502418920',
    dateTime: DateTime(2026, 3, 9, 9, 22, 10),
    amount: 240.00,
    type: ExpenseType.novaPoshta,
    status: ExpenseStatus.reserved,
    clientInfo: 'НП ТТН 20450073800198',
    pharmacist: 'Сідєльнікова С.П.',
    reserveNumber: '164900102',
    register: 'КАСА 2 Новокузнецька',
    customerPhone: '+380939998877',
    items: const [
      ExpenseItem(
        sku: '26771903',
        name: 'МЕЛОКСИКАМ-ТЕВА ТАБЛ. 15МГ №20',
        manufacturer: 'Тева',
        quantity: 1,
        price: 240.00,
        total: 240.00,
      ),
    ],
  ),

  // ── Рецепт 1303 ──────────────────────────────────────────────────────────
  CashExpense(
    id: 'exp-20',
    receiptNumber: '502419280',
    dateTime: DateTime(2026, 3, 10, 9, 55, 44),
    amount: 0.00,
    type: ExpenseType.prescription1303,
    status: ExpenseStatus.completed,
    clientInfo: 'Рецепт №1303-00456712',
    pharmacist: 'Мохно Н.В.',
    register: 'КАСА 1 Новокузнецька',
    customerPhone: '+380671234509',
    items: const [
      ExpenseItem(
        sku: '26890213',
        name: 'СІОФОР 500 ТАБЛ. №60',
        manufacturer: 'Berlin-Chemie',
        quantity: 1,
        price: 350.50,
        total: 0.00,
      ),
    ],
  ),

  CashExpense(
    id: 'exp-21',
    receiptNumber: '502418800',
    dateTime: DateTime(2026, 3, 8, 11, 15, 20),
    amount: 0.00,
    type: ExpenseType.prescription1303,
    status: ExpenseStatus.completed,
    clientInfo: 'Рецепт №1303-00456698',
    pharmacist: 'Артюх А.Ю',
    register: 'КАСА 2 Новокузнецька',
    customerPhone: '+380501119922',
    items: const [
      ExpenseItem(
        sku: '25487201',
        name: 'ЦИПРОФЛОКСАЦИН ТАБЛ. 500МГ №10',
        manufacturer: 'Дарниця',
        quantity: 2,
        price: 89.50,
        total: 0.00,
      ),
    ],
  ),
];
