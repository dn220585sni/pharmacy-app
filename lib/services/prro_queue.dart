import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'prro_service.dart';

/// Тип відкладеного чеку.
enum PrroQueueType { sale, returnSale }

/// Один відкладений чек у черзі.
class PrroQueuedReceipt {
  final String id;
  final PrroQueueType type;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> payments;
  final double totalSum;
  final double roundSum;

  /// `true` — чек із GetDataRRO (готові products/payments) → переграш через
  /// `createSaleReceiptRaw`. `false` — клієнтська збірка → `createSaleReceipt`.
  final bool raw;
  final int? localNumber;
  final DateTime createdAt;
  int attempts;
  String? lastError;

  PrroQueuedReceipt({
    required this.id,
    required this.type,
    required this.products,
    required this.payments,
    required this.totalSum,
    required this.createdAt,
    this.roundSum = 0,
    this.raw = false,
    this.localNumber,
    this.attempts = 0,
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'products': products,
        'payments': payments,
        'total_sum': totalSum,
        'round_sum': roundSum,
        'raw': raw,
        'local_number': localNumber,
        'created_at': createdAt.toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
      };

  factory PrroQueuedReceipt.fromJson(Map<String, dynamic> json) =>
      PrroQueuedReceipt(
        id: json['id'].toString(),
        type: PrroQueueType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => PrroQueueType.sale,
        ),
        products: (json['products'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        payments: (json['payments'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        totalSum: (json['total_sum'] as num?)?.toDouble() ?? 0,
        roundSum: (json['round_sum'] as num?)?.toDouble() ?? 0,
        raw: json['raw'] == true,
        localNumber: (json['local_number'] as num?)?.toInt(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['last_error']?.toString(),
      );
}

/// Черга чеків, які не пройшли через мережеву помилку.
///
/// Використовується тільки коли ПРРО недоступний (timeout / connection refused).
/// Логічні помилки в чергу не потрапляють — вони блокують продаж.
///
/// При роботі через SmartConnect (локальний 10.15.30.61) сам SmartConnect
/// тримає внутрішню чергу для пушу в податкову — наша черга в цьому випадку
/// служить fallback на ситуацію коли SmartConnect не запущений.
class PrroQueue {
  static const _fileName = 'prro_queue.json';
  static List<PrroQueuedReceipt> _items = [];
  static bool _loaded = false;
  static bool _flushing = false;

  /// Прочитати чергу з диску. Викликати при старті.
  static Future<void> load() async {
    if (_loaded) return;
    final file = await _file();
    if (file == null || !await file.exists()) {
      _loaded = true;
      return;
    }
    try {
      final text = await file.readAsString();
      final list = jsonDecode(text) as List;
      _items = list
          .whereType<Map<String, dynamic>>()
          .map(PrroQueuedReceipt.fromJson)
          .toList();
      debugPrint('PRRO queue loaded: ${_items.length} pending');
    } catch (e) {
      debugPrint('PRRO queue load FAIL: $e');
      _items = [];
    }
    _loaded = true;
  }

  /// Поточний стан черги.
  static List<PrroQueuedReceipt> get pending =>
      List.unmodifiable(_items);

  /// Кількість відкладених чеків.
  static int get count => _items.length;

  /// Покласти чек у чергу.
  static Future<void> enqueueSale({
    required List<PrroProduct> products,
    required List<PrroPayment> payments,
    required double totalSum,
    double roundSum = 0,
    int? localNumber,
    String? error,
  }) async {
    await load();
    final entry = PrroQueuedReceipt(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      type: PrroQueueType.sale,
      products: products.map((p) => p.toJson()).toList(),
      payments: payments.map((p) => p.toJson()).toList(),
      totalSum: totalSum,
      roundSum: roundSum,
      localNumber: localNumber,
      createdAt: DateTime.now(),
      lastError: error,
    );
    _items.add(entry);
    await _persist();
    debugPrint('PRRO queue: enqueued ${entry.id} '
        '(total=${entry.totalSum}, queue=${_items.length})');
  }

  /// Покласти в чергу чек із ГОТОВИМИ products/payments (GetDataRRO). Переграш —
  /// через `createSaleReceiptRaw` (прапорець `raw=true`).
  static Future<void> enqueueSaleRaw({
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> payments,
    required double totalSum,
    int? localNumber,
    String? error,
  }) async {
    await load();
    final entry = PrroQueuedReceipt(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      type: PrroQueueType.sale,
      products: products,
      payments: payments,
      totalSum: totalSum,
      raw: true,
      localNumber: localNumber,
      createdAt: DateTime.now(),
      lastError: error,
    );
    _items.add(entry);
    await _persist();
    debugPrint('PRRO queue: enqueued ${entry.id} '
        '(total=${entry.totalSum}, queue=${_items.length})');
  }

  /// Спробувати відправити всі відкладені чеки.
  /// Повертає кількість успішно відправлених.
  static Future<int> flush() async {
    if (_flushing) return 0;
    await load();
    if (_items.isEmpty) return 0;

    _flushing = true;
    var sent = 0;
    try {
      // Копія, щоб ітерувати і одночасно модифікувати _items.
      final snapshot = List<PrroQueuedReceipt>.from(_items);
      for (final item in snapshot) {
        final PrroResult result;
        if (item.raw) {
          // Готові products/payments з GetDataRRO — сирий проброс.
          result = await PrroService.createSaleReceiptRaw(
            products: item.products,
            payments: item.payments,
            totalSum: item.totalSum,
            localNumber: item.localNumber,
            isReturn: item.type == PrroQueueType.returnSale,
          );
        } else {
          final products = item.products.map(_productFromJson).toList();
          final payments = item.payments.map(_paymentFromJson).toList();
          result = item.type == PrroQueueType.sale
              ? await PrroService.createSaleReceipt(
                  products: products,
                  payments: payments,
                  totalSum: item.totalSum,
                  roundSum: item.roundSum,
                  localNumber: item.localNumber,
                )
              : await PrroService.createReturnReceipt(
                  products: products,
                  payments: payments,
                  totalSum: item.totalSum,
                  localNumber: item.localNumber,
                );
        }

        if (result.success) {
          _items.removeWhere((e) => e.id == item.id);
          sent++;
          debugPrint('PRRO queue: flushed ${item.id} → ${result.orderNum}');
        } else {
          item.attempts++;
          item.lastError = result.error;
          // На connection error — лишаємо в черзі, припиняємо ітерацію
          // (немає сенсу продовжувати якщо мережа недоступна).
          if (result.errorKind == PrroErrorKind.connection) {
            debugPrint('PRRO queue: connection still down, stopping flush');
            break;
          }
          // Логічна помилка — теж лишаємо для ручного розгляду.
          debugPrint('PRRO queue: ${item.id} logical error: ${result.error}');
        }
      }
      await _persist();
    } finally {
      _flushing = false;
    }
    return sent;
  }

  /// Видалити запис з черги вручну (наприклад, після зовнішнього розгляду).
  static Future<void> remove(String id) async {
    await load();
    _items.removeWhere((e) => e.id == id);
    await _persist();
  }

  /// Очистити чергу (тільки для діагностики/тестів).
  static Future<void> clear() async {
    _items.clear();
    await _persist();
  }

  // ── internals ──────────────────────────────────────────────────────────────

  static Future<File?> _file() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persist() async {
    final file = await _file();
    if (file == null) return;
    try {
      await file.writeAsString(
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('PRRO queue persist FAIL: $e');
    }
  }

  static PrroProduct _productFromJson(Map<String, dynamic> j) => PrroProduct(
        name: j['name']?.toString() ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        price: (j['price'] as num?)?.toDouble() ?? 0,
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
        code: j['code']?.toString(),
        barcode: j['bar_code']?.toString(),
        letters: j['letters']?.toString(),
        taxPrc: (j['tax_prc'] as num?)?.toDouble(),
        unitName: j['unit_name']?.toString() ?? 'штука',
        unitCode: j['unit_code']?.toString(),
        discount: (j['sum_discount'] as num?)?.toDouble(),
      );

  static PrroPayment _paymentFromJson(Map<String, dynamic> j) => PrroPayment(
        code: (j['code'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? 'ГОТІВКА',
        sum: (j['sum'] as num?)?.toDouble() ?? 0,
        sumProvided: (j['sum_provided'] as num?)?.toDouble() ?? 0,
        sumRemains: (j['sum_remains'] as num?)?.toDouble() ?? 0,
      );
}
