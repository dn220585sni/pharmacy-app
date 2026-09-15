import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Стиль монетки.
enum AncCoinStyle {
  /// «Реалістичне» золото: градієнти, рифлений обід, блік, тінь.
  gold,

  /// Плоска: лого як є + тонке кільце двох плоских золотих тонів, без
  /// градієнтів і тіней у спокої. Сяйво лише під час нарахування.
  flat,
}

/// Ефект при нарахуванні.
enum AncCoinEffect {
  /// Переливання: монета стоїть на місці, по лицю двічі пробігає світло.
  shimmer,

  /// Переворот навколо вертикальної осі (з ребром, підскоком і сяйвом).
  spin,
}

/// Золота монетка з емблемою АНЦ.
///
/// Малюється повністю кодом (без растрових асетів): золотий градієнт,
/// рифлений обід, внутрішнє кільце, дуги-«руки» з логотипа й напис «АНЦ»
/// синім кольором бренду. При зміні [spinKey] (або при монтуванні, якщо
/// [spinOnMount]) монетка робить кілька обертів навколо вертикальної осі,
/// трохи «підстрибує», світиться золотим ореолом і ловить відблиск.
///
/// Використання: `AncCoin(size: 44, spinKey: lastEarnedAt)` — кожне нове
/// нарахування дає новий `lastEarnedAt` → новий оберт.
class AncCoin extends StatefulWidget {
  /// Діаметр монетки у логічних пікселях.
  final double size;

  /// Будь-який об'єкт; коли він змінюється (`!=`), монетка обертається.
  final Object? spinKey;

  /// Крутнути одразу при першому показі (наприклад, дашборд щойно
  /// з'явився після оплати).
  final bool spinOnMount;

  /// Кількість повних обертів за одну анімацію.
  final int turns;

  /// SVG-лого на лиці монетки (кругле, вписується у внутрішнє кільце).
  /// Малюється як вектор — без спотворень і чітко на будь-якому масштабі.
  /// `null` або помилка завантаження — малюється запасна векторна емблема.
  final String? logoSvgAsset;

  /// Стандартний файл лого АНЦ (з https://storage.googleapis.com/static-storage/mobile_logo.svg).
  static const defaultLogoSvgAsset = 'assets/images/anc_logo.svg';

  /// Стиль малювання (див. [AncCoinStyle]).
  final AncCoinStyle style;

  /// Ефект при нарахуванні (див. [AncCoinEffect]).
  final AncCoinEffect effect;

  /// Тривалість ефекту. За замовчуванням збігається з анімацією лічильника
  /// «Нараховано» у дашборді (1,4 с), щоб переливання йшло разом із цифрами.
  final Duration duration;

  const AncCoin({
    super.key,
    this.size = 44,
    this.spinKey,
    this.spinOnMount = false,
    this.turns = 1,
    this.logoSvgAsset = defaultLogoSvgAsset,
    this.style = AncCoinStyle.flat,
    this.effect = AncCoinEffect.spin,
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<AncCoin> createState() => _AncCoinState();
}

class _AncCoinState extends State<AncCoin> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  TextPainter? _label;
  double _labelSize = -1;

  PictureInfo? _logo;
  String? _loadedLogoAsset;
  int _logoLoadSeq = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    if (widget.spinOnMount) {
      // Невелика пауза, щоб панель встигла з'явитись (AnimatedSwitcher 300 мс).
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) spin();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveLogo();
  }

  @override
  void didUpdateWidget(AncCoin old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) _ctrl.duration = widget.duration;
    if (old.spinKey != widget.spinKey) spin();
    if (old.logoSvgAsset != widget.logoSvgAsset) _resolveLogo();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _label?.dispose();
    _logo?.picture.dispose();
    super.dispose();
  }

  /// Завантажити SVG-лого. Помилка (файлу нема) — тихий відкат на векторну
  /// емблему, без винятків у консолі.
  Future<void> _resolveLogo() async {
    final asset = widget.logoSvgAsset;
    if (asset == _loadedLogoAsset && (_logo != null || asset == null)) return;
    final seq = ++_logoLoadSeq;
    PictureInfo? info;
    if (asset != null) {
      try {
        info = await vg.loadPicture(SvgAssetLoader(asset), context);
      } catch (_) {
        info = null;
      }
    }
    if (!mounted || seq != _logoLoadSeq) {
      info?.picture.dispose();
      return;
    }
    setState(() {
      _logo?.picture.dispose();
      _logo = info;
      _loadedLogoAsset = asset;
    });
  }

  /// Запустити ефект нарахування вручну (переливання або оберт — за [AncCoin.effect]).
  void spin() => _ctrl.forward(from: 0);

  TextPainter _labelFor(double size) {
    if (_label != null && _labelSize == size) return _label!;
    _label?.dispose();
    final tp = TextPainter(
      text: TextSpan(
        text: 'АНЦ',
        style: TextStyle(
          color: _AncCoinPainter.brandBlue,
          fontSize: size * 0.25,
          fontWeight: FontWeight.w900,
          letterSpacing: -size * 0.004,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _label = tp;
    _labelSize = size;
    return tp;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          final running = _ctrl.isAnimating;
          final isFlat = widget.style == AncCoinStyle.flat;

          double angle = 0, scale = 1, glow = 0, shine = -1, shineStrength;
          if (widget.effect == AncCoinEffect.spin) {
            final eased = Curves.easeOutCubic.transform(t);
            angle = eased * widget.turns * 2 * math.pi;
            // Підскок: плавно росте до ~+10% посередині й повертається.
            final bump = math.sin(math.pi * Curves.easeOut.transform(t));
            scale = running ? 1.0 + 0.10 * bump : 1.0;
            glow = running ? bump : 0.0;
            // Відблиск пробігає по лицю наприкінці, коли оберт майже стих.
            shine = t < 0.62 ? -1.0 : ((t - 0.62) / 0.38).clamp(0.0, 1.0);
            shineStrength = isFlat ? 0.45 : 0.75;
          } else {
            // Переливання: монета нерухома, світло пробігає двічі, поки
            // змінюються цифри; ледь помітне тепле сяйво посилює ефект.
            if (running) {
              shine = (t * 2) % 1.0;
              glow = 0.35 * math.sin(math.pi * t);
            }
            shineStrength = isFlat ? 0.6 : 0.75;
          }

          return Transform.scale(
            scale: scale,
            child: CustomPaint(
              size: Size(size, size),
              painter: _AncCoinPainter(
                angle: angle,
                glow: glow,
                shine: shine,
                shineStrength: shineStrength,
                label: _labelFor(size),
                logo: _logo,
                style: widget.style,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AncCoinPainter extends CustomPainter {
  static const brandBlue = Color(0xFF2B84D3);

  static const _goldLight = Color(0xFFFFF4B8);
  static const _gold = Color(0xFFFFD447);
  static const _goldMid = Color(0xFFE8B21C);
  static const _goldDark = Color(0xFFB8860B);
  static const _goldEdge = Color(0xFF9A6E08);

  final double angle;
  final double glow; // 0..1 — сила золотого ореолу
  final double shine; // <0 — нема; 0..1 — позиція відблиску
  final double shineStrength; // максимальна яскравість відблиску 0..1
  final TextPainter label;
  final PictureInfo? logo;
  final AncCoinStyle style;

  // Плоский стиль: два плоскі золоті тони + кант.
  static const _flatRing = Color(0xFFF0C64E);
  static const _flatEdge = Color(0xFFC48F1C);
  static const _logoYellow = Color(0xFFFFE241);

  const _AncCoinPainter({
    required this.angle,
    required this.glow,
    required this.shine,
    required this.label,
    this.shineStrength = 0.75,
    this.logo,
    this.style = AncCoinStyle.flat,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (style == AncCoinStyle.flat) {
      _paintFlat(canvas, size);
      return;
    }
    _paintGold(canvas, size);
  }

  // ── Плоский стиль ─────────────────────────────────────────────────────────

  void _paintFlat(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 * 0.96;
    final c = math.cos(angle);
    final s = math.sin(angle);
    final w = math.max(c.abs(), 0.07);
    final thickness = r * 0.12;

    // Сяйво — лише під час нарахування; у спокої жодних тіней.
    if (glow > 0) {
      canvas.drawCircle(
        center,
        r * (1.0 + 0.22 * glow),
        Paint()
          ..color = _flatRing.withValues(alpha: 0.45 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.3),
      );
    }

    // Ребро — один плоский темніший тон.
    final dx = -s * thickness;
    const steps = 6;
    final edgePaint = Paint()..color = _flatEdge;
    for (var i = steps; i >= 1; i--) {
      final o = Offset(dx * i / steps, 0);
      canvas.drawOval(
        Rect.fromCenter(center: center + o, width: 2 * r * w, height: 2 * r),
        edgePaint,
      );
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(w, 1.0);
    final face = Rect.fromCircle(center: Offset.zero, radius: r);
    final kant = math.max(1.0, r * 0.03);

    // Кільце обода — плоский золотий тон + темніший кант зовні.
    canvas.drawCircle(Offset.zero, r, Paint()..color = _flatRing);
    canvas.drawCircle(
      Offset.zero,
      r - kant / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kant
        ..color = _flatEdge.withValues(alpha: 0.8),
    );

    // Лице: лого як є; без лого — жовтий диск і векторна емблема.
    final inner = r * 0.84;
    if (logo != null) {
      _paintLogo(canvas, logo!, inner);
    } else {
      canvas.drawCircle(Offset.zero, inner, Paint()..color = _logoYellow);
      _paintVectorEmblem(canvas, r);
      canvas.drawCircle(
        Offset.zero,
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = kant
          ..color = _flatEdge.withValues(alpha: 0.5),
      );
    }

    if (shine >= 0) _paintShine(canvas, face, r);

    canvas.restore();
  }

  // ── Золотий стиль ─────────────────────────────────────────────────────────

  void _paintGold(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 * 0.94; // трохи запасу під тінь
    final c = math.cos(angle);
    final s = math.sin(angle);
    // Ширина «видимого» лиця; мінімум — щоб ребро ніколи не зникало.
    final w = math.max(c.abs(), 0.07);
    final thickness = r * 0.16;

    // ── Тінь під монеткою ─────────────────────────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, r * 0.12),
        width: 2 * r * w,
        height: 2 * r,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.18),
    );

    // ── Золотий ореол при нарахуванні ─────────────────────────────────────
    if (glow > 0) {
      canvas.drawCircle(
        center,
        r * (1.05 + 0.25 * glow),
        Paint()
          ..color = _gold.withValues(alpha: 0.55 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35),
      );
    }

    // ── Ребро (товщина) ───────────────────────────────────────────────────
    final dx = -s * thickness;
    const steps = 8;
    final edgePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [_goldMid, _goldEdge, _goldDark, _goldEdge],
        stops: const [0.0, 0.35, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    for (var i = steps; i >= 1; i--) {
      final o = Offset(dx * i / steps, 0);
      canvas.drawOval(
        Rect.fromCenter(center: center + o, width: 2 * r * w, height: 2 * r),
        edgePaint,
      );
    }

    // ── Лице монетки (стиснуте по X під кутом обертання) ──────────────────
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(w, 1.0);
    final face = Rect.fromCircle(center: Offset.zero, radius: r);

    // Базовий диск — радіальний градієнт зі зміщеним бліком.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.1,
          colors: [_goldLight, _gold, _goldMid, _goldDark],
          stops: [0.0, 0.38, 0.8, 1.0],
        ).createShader(face),
    );

    // Обід — «металевий» кільцевий градієнт.
    final rimWidth = r * 0.13;
    canvas.drawCircle(
      Offset.zero,
      r - rimWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..shader = const SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: [
            _goldLight,
            _goldMid,
            _goldLight,
            _goldDark,
            _goldLight,
            _goldMid,
            _goldLight,
          ],
        ).createShader(face),
    );

    // Рифлення обода.
    final tick = Paint()
      ..color = _goldEdge.withValues(alpha: 0.45)
      ..strokeWidth = math.max(1.0, r * 0.03)
      ..strokeCap = StrokeCap.round;
    const ticks = 48;
    for (var i = 0; i < ticks; i++) {
      final a = i * 2 * math.pi / ticks;
      final ca = math.cos(a), sa = math.sin(a);
      canvas.drawLine(
        Offset(ca * (r - rimWidth), sa * (r - rimWidth)),
        Offset(ca * (r - r * 0.02), sa * (r - r * 0.02)),
        tick,
      );
    }

    // Внутрішнє кільце: темна лінія + світлий кант (ефект карбування).
    final inner = r * 0.79;
    canvas.drawCircle(
      Offset.zero,
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.035)
        ..color = _goldDark.withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      Offset.zero,
      inner - r * 0.035,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * 0.02)
        ..color = _goldLight.withValues(alpha: 0.75),
    );

    if (logo != null) {
      _paintLogo(canvas, logo!, inner - r * 0.07);
    } else {
      _paintVectorEmblem(canvas, r);
    }

    // Блік (спекулярний) зверху-зліва.
    _paintSpecular(canvas, r);

    // Відблиск, що пробігає по лицю після оберту.
    if (shine >= 0) _paintShine(canvas, face, r);

    canvas.restore();
  }

  /// SVG-лого, вписане у коло радіуса [radius] по центру лиця
  /// (як емальована вставка всередині карбованого кільця).
  void _paintLogo(Canvas canvas, PictureInfo info, double radius) {
    final dst = Rect.fromCircle(center: Offset.zero, radius: radius);
    final sw = info.size.width, sh = info.size.height;
    if (sw <= 0 || sh <= 0) return;
    canvas.save();
    canvas.clipPath(Path()..addOval(dst), doAntiAlias: true);
    canvas.translate(dst.left, dst.top);
    canvas.scale(dst.width / sw, dst.height / sh);
    canvas.drawPicture(info.picture);
    canvas.restore();
    // Тонкий темний кант по краю вставки — читається як заглиблення.
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, radius * 0.025)
        ..color = _goldEdge.withValues(alpha: 0.35),
    );
  }

  /// Векторна емблема (запасний варіант, коли лого-файл недоступний).
  void _paintVectorEmblem(Canvas canvas, double r) {
    final face = Rect.fromCircle(center: Offset.zero, radius: r);
    // Емблема: дві дуги-«руки» з логотипа (розрив зліва і справа).
    final arcR = r * 0.58;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.10
      ..strokeCap = StrokeCap.round
      ..color = brandBlue;
    final arcRect = Rect.fromCircle(center: Offset.zero, radius: arcR);
    // Верхня дуга: від 205° до 335° (у радіанах, 0 = праворуч, за год. стрілкою).
    canvas.drawArc(arcRect, _deg(205), _deg(130), false, arcPaint);
    // Нижня дуга: від 25° до 155°.
    canvas.drawArc(arcRect, _deg(25), _deg(130), false, arcPaint);
    // «Долоні» — маленькі кінцівки дуг, що загинаються всередину.
    final palm = Paint()
      ..color = brandBlue
      ..style = PaintingStyle.fill;
    _palm(canvas, arcR, 335, palm, r);
    _palm(canvas, arcR, 155, palm, r);

    // Напис «АНЦ» з легким світлим тисненням.
    final lo = Offset(-label.width / 2, -label.height / 2 + r * 0.02);
    canvas.saveLayer(face, Paint());
    label.paint(canvas, lo + Offset(r * 0.02, r * 0.02));
    canvas.drawRect(
      face,
      Paint()
        ..color = _goldLight.withValues(alpha: 0.8)
        ..blendMode = BlendMode.srcIn,
    );
    canvas.restore();
    label.paint(canvas, lo);
  }

  void _paintSpecular(Canvas canvas, double r) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.32, -r * 0.42),
        width: r * 0.9,
        height: r * 0.45,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCenter(
            center: Offset(-r * 0.32, -r * 0.42),
            width: r * 0.9,
            height: r * 0.45,
          ),
        ),
    );
  }

  void _paintShine(Canvas canvas, Rect face, double r) {
    final strength = shineStrength;
    canvas.save();
    canvas.clipPath(Path()..addOval(face));
    canvas.rotate(-math.pi / 5);
    final x = -r * 1.6 + shine * r * 3.2;
    final band = Rect.fromCenter(
      center: Offset(x, 0),
      width: r * 0.7,
      height: r * 3,
    );
    final fade = math.sin(math.pi * shine); // м'яко з'явився і зник
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: strength * fade),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(band),
    );
    canvas.restore();
  }

  static double _deg(double d) => d * math.pi / 180;

  /// Маленька крапля на кінці дуги, що імітує долоню з логотипа.
  static void _palm(Canvas canvas, double arcR, double deg, Paint p, double r) {
    final a = _deg(deg);
    final tip = Offset(math.cos(a) * arcR, math.sin(a) * arcR);
    // Зсув до центру — «пальці» тягнуться всередину кола.
    final toCenter = Offset(-math.cos(a), -math.sin(a)) * (r * 0.12);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(
        tip.dx + toCenter.dx * 0.6 - toCenter.dy * 0.5,
        tip.dy + toCenter.dy * 0.6 + toCenter.dx * 0.5,
        tip.dx + toCenter.dx,
        tip.dy + toCenter.dy,
      )
      ..quadraticBezierTo(
        tip.dx + toCenter.dx * 0.6 + toCenter.dy * 0.5,
        tip.dy + toCenter.dy * 0.6 - toCenter.dx * 0.5,
        tip.dx,
        tip.dy,
      )
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_AncCoinPainter old) =>
      old.angle != angle ||
      old.glow != glow ||
      old.shine != shine ||
      old.shineStrength != shineStrength ||
      old.label != label ||
      old.logo != logo ||
      old.style != style;
}
