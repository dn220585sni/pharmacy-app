// Превʼю монетки АНЦ без бекенду — обидва стилі поруч:
//   flutter run -d web-server -t tool/coin_preview.dart --web-port 8787
import 'package:flutter/material.dart';
import 'package:pharmacy_app/widgets/anc_coin.dart';
import 'package:pharmacy_app/widgets/shift_dashboard.dart';

void main() => runApp(const _CoinPreviewApp());

class _CoinPreviewApp extends StatefulWidget {
  const _CoinPreviewApp();

  @override
  State<_CoinPreviewApp> createState() => _CoinPreviewAppState();
}

class _CoinPreviewAppState extends State<_CoinPreviewApp> {
  int _spin = 0;
  double _earned = 0;
  DateTime? _at;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F5F8),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  FilledButton(
                    key: const Key('spin'),
                    onPressed: () => setState(() => _spin++),
                    child: const Text('Ефект на обох'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    key: const Key('earn'),
                    onPressed: () => setState(() {
                      _earned += 12.5;
                      _at = DateTime.now();
                    }),
                    child: const Text('Нарахувати 12,50'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _column(
                      'Оберт (стандарт)',
                      AncCoinStyle.flat,
                      AncCoinEffect.spin,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _column(
                      'Переливання (опція)',
                      AncCoinStyle.flat,
                      AncCoinEffect.shimmer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(String title, AncCoinStyle style, AncCoinEffect effect) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        // Картка «Нараховано» в реальному контексті дашборду.
        SizedBox(
          height: 250,
          child: ShiftDashboard(
            earnedAmount: _earned,
            lastEarnedAt: _at,
            coinStyle: style,
            coinEffect: effect,
          ),
        ),
        const SizedBox(height: 8),
        // Збільшено — щоб роздивитись деталі.
        Wrap(
          spacing: 28,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final s in [48.0, 120.0])
              AncCoin(size: s, style: style, effect: effect, spinKey: _spin),
          ],
        ),
      ],
    );
  }
}
