import 'package:flutter/material.dart';
import '../models/cart_item.dart';
import '../models/stop_price_action.dart';
import 'stop_price_info_dialog.dart';

class CartItemWidget extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  /// Whether this item has been scanned (barcode confirmed).
  final bool isScanned;

  /// Callback when the pharmacist taps the price (simulates barcode scan).
  final VoidCallback? onScan;

  /// Ціна за одиницю після всіх знижок з сервера (`GetSumSkid`).
  /// Якщо менша за `drug.price` — UI показує style "стара → нова" (як рука допомоги).
  final double? serverUnitPrice;

  /// Підсумок по позиції з сервера. Якщо `null` — рендеримо локальний `item.total`.
  final double? serverCost;

  /// Активні акції/стоп-ціни на товар (з `GetStopPriceUKod`).
  /// Якщо непустий — під ціною показуємо бейдж із коротким `opis`.
  final List<StopPriceAction> actions;

  const CartItemWidget({
    super.key,
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    this.isScanned = false,
    this.onScan,
    this.serverUnitPrice,
    this.serverCost,
    this.actions = const [],
  });

  /// Чи є будь-яка знижка (серверна або локальна "рука допомоги").
  bool get _hasAnyDiscount {
    if (item.hasDiscount) return true;
    if (serverUnitPrice == null) return false;
    return serverUnitPrice! < item.drug.price - 0.001;
  }

  /// Ціна за одиницю для відображення — server pricing якщо є, інакше effective.
  double get _displayUnitPrice => serverUnitPrice ?? item.effectivePrice;

  /// Найвигідніша знижка (за реальною економією в грн), що ВЖЕ діє на рядок при
  /// поточній кількості [qty] — базове правило (безумовне) + qty-правила, поріг
  /// яких досягнуто (`kol ≤ qty`). Умовні правила з недосягнутим порогом не
  /// враховуються. null — якщо жодна знижка ще не діє.
  StopPriceRule? _bestAppliedRule(int qty) {
    final unit = item.drug.price;
    StopPriceRule? best;
    double bestSaving = 0;
    for (final a in actions) {
      // Акції з набором діють у зв'язці з іншим препаратом — умовні; їх
      // застосовує лише сервер (ловимо через _serverUnitDiscount). Не рахуємо
      // їх власним правилом, інакше знижка показалась би передчасно.
      if (a.nabor.isNotEmpty) continue;
      for (final r in a.appliedRules(qty)) {
        final pct = r.discountPercent;
        final uah = r.discountUah;
        final saving = pct != null ? unit * pct.abs() / 100 : (uah ?? 0);
        if (saving <= 0) continue;
        if (saving > bestSaving) {
          bestSaving = saving;
          best = r;
        }
      }
    }
    return best;
  }

  /// Серверна знижка на одиницю (роздріб − [serverUnitPrice]), якщо сервер уже
  /// застосував її до позиції (`GetSumSkid`). Покриває умови, що залежать від
  /// усього кошика — напр. знижку у зв'язці з іншим препаратом. 0 якщо нема.
  double get _serverUnitDiscount {
    final sp = serverUnitPrice;
    final retail = item.drug.price;
    if (sp == null || retail <= 0 || sp >= retail - 0.001) return 0;
    return retail - sp;
  }

  /// Пояснювальний бейдж знижки + явна іконка «і». Показує знижку, що ВЖЕ діє на
  /// позицію: безумовну (з 1 уп), або умовну коли умову виконано — досягнуто
  /// поріг кількості, чи сервер застосував знижку у зв'язці з іншим препаратом.
  /// Поки умова не виконана — бейджа нема.
  /// По кліку на «і» відкривається попап з поясненням акції.
  /// Повертає null, якщо знижка на позицію ще не діє.
  Widget? _buildDiscountBadge(BuildContext context) {
    if (actions.isEmpty) return null;
    // 1) Знижка з власного правила (безумовна або qty-поріг досягнуто).
    var appliedText = _bestAppliedRule(item.quantity)?.appliedText;
    // 2) Інакше — якщо сервер усе ж знизив ціну (напр. зв'язка з іншим товаром).
    if (appliedText == null) {
      final disc = _serverUnitDiscount;
      if (disc > 0) {
        final pct = disc / item.drug.price * 100;
        final f = pct == pct.roundToDouble()
            ? pct.toStringAsFixed(0)
            : pct.toStringAsFixed(1);
        appliedText = '−$f%';
      }
    }
    if (appliedText == null) return null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_offer_rounded,
                  size: 10, color: Color(0xFF16A34A)),
              const SizedBox(width: 4),
              Text(
                appliedText,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF15803D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        // Явна іконка «і» — попап з поясненням акції (замість hover-tooltip).
        InkWell(
          onTap: () => _showActionInfo(context),
          customBorder: const CircleBorder(),
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F3FB),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.info_outline_rounded,
                size: 12, color: Color(0xFF1E7DC8)),
          ),
        ),
      ],
    );
  }

  /// Попап з поясненням акції(й) — спільний хелпер (той самий, що в картці).
  void _showActionInfo(BuildContext context) {
    showStopPriceInfoDialog(
      context,
      drugName: item.drug.displayName,
      actions: actions,
      qty: item.quantity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canScan = onScan != null && !isScanned;
    final discountBadge = _buildDiscountBadge(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: isScanned ? const Color(0xFFEFF6FF) : const Color(0xFFF9FAFB),
        border: Border.all(
          color:
              isScanned ? const Color(0xFFBFDBFE) : const Color(0xFFE5E7EB),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Drug icon — Rx badge for prescriptions, blue checkbox when scanned
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.isPrescription
                  ? const Color(0xFFDCFCE7)
                  : isScanned
                      ? const Color(0xFFDBEAFE)
                      : const Color(0xFFE8F3FB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: item.isPrescription
                ? const Center(
                    child: Text('Rx',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF16A34A))))
                : Icon(
                    isScanned
                        ? Icons.check_box_rounded
                        : Icons.medication_rounded,
                    color: const Color(0xFF1E7DC8),
                    size: 17,
                  ),
          ),
          const SizedBox(width: 10),

          // Name and price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.drug.displayName,
                  style: TextStyle(
                    color: isScanned
                        ? const Color(0xFF1E7DC8)
                        : const Color(0xFF1C1C2E),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (item.isPrescription) ...[
                  Text(
                    'Доплата: ${item.prescriptionData!.copayment.toStringAsFixed(2)} ₴ × ${item.displayQty}',
                    style: const TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else if (_hasAnyDiscount) ...[
                  Row(
                    children: [
                      // Стара ціна — закреслена, контрастний сірий
                      Text(
                        '${item.drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴',
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Тег-іконка + акційна ціна — єдиний стиль з таблицею/карткою
                      const Icon(Icons.local_offer_rounded,
                          size: 10, color: Color(0xFF16A34A)),
                      const SizedBox(width: 3),
                      Text(
                        '${_displayUnitPrice.toStringAsFixed(2).replaceAll('.', ',')} ₴ × ${item.displayQty}',
                        style: const TextStyle(
                          color: Color(0xFF15803D),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    '${item.drug.price.toStringAsFixed(2).replaceAll('.', ',')} ₴ × ${item.displayQty}',
                    style: TextStyle(
                      color: isScanned
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFF9CA3AF),
                      fontSize: 11,
                    ),
                  ),
                if (discountBadge != null) ...[
                  const SizedBox(height: 4),
                  discountBadge,
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Quantity controls
          Row(
            children: [
              _ControlButton(
                icon: Icons.remove_rounded,
                onTap: onDecrease,
              ),
              SizedBox(
                width: item.isFractional ? 42 : 30,
                child: Text(
                  item.displayQty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFF1C1C2E),
                    fontSize: item.isFractional ? 12 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ControlButton(
                icon: Icons.add_rounded,
                onTap: item.isFractional
                    ? (item.fractionalQty! < item.drug.unitsPerPackage!
                        ? onIncrease
                        : null)
                    : (item.quantity < item.drug.stock
                        ? onIncrease
                        : null),
              ),
            ],
          ),
          const SizedBox(width: 10),

          // Total price — tappable to simulate scan
          GestureDetector(
            onTap: canScan ? onScan : null,
            child: MouseRegion(
              cursor: canScan
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: canScan
                    ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: const Color(0xFF1E7DC8)
                                .withValues(alpha: 0.3),
                            style: BorderStyle.solid,
                          ),
                        ),
                      )
                    : null,
                child: Text(
                  '${(serverCost ?? item.total).toStringAsFixed(2).replaceAll('.', ',')} ₴',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: isScanned
                        ? const Color(0xFF1E7DC8)
                        : const Color(0xFF1C1C2E),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Remove button
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Color(0xFFEF5350),
                size: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ControlButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFFE8F3FB)
              : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          color: enabled
              ? const Color(0xFF1E7DC8)
              : const Color(0xFFD1D5DB),
          size: 15,
        ),
      ),
    );
  }
}
