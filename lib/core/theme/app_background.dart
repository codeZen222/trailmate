import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 背景风格。
enum BackgroundStyle {
  scene('插画', '山川日落'),
  gradient('渐变', '柔和光斑'),
  flat('纯色', '最省资源');

  const BackgroundStyle(this.label, this.desc);
  final String label;
  final String desc;

  static BackgroundStyle fromKey(String? k) =>
      values.firstWhere((s) => s.name == k, orElse: () => BackgroundStyle.scene);
}

/// 一套场景插画的全部颜色与元素开关。
class ScenePalette {
  const ScenePalette({
    required this.skyTop,
    required this.skyBottom,
    required this.sun,
    required this.sunGlow,
    required this.cloud,
    required this.ridgeFar,
    required this.ridgeMid,
    required this.ridgeNear,
    required this.ridgeFront,
    this.hasMoon = false,
    this.hasStars = false,
    this.hasBirds = true,
    this.waves = false,
    this.snowCaps = false,
  });

  final Color skyTop;
  final Color skyBottom;
  final Color sun;
  final Color sunGlow;
  final Color cloud;
  final Color ridgeFar;
  final Color ridgeMid;
  final Color ridgeNear;
  final Color ridgeFront;

  final bool hasMoon;
  final bool hasStars;
  final bool hasBirds;

  /// 用起伏水波代替山脊（海洋主题）。
  final bool waves;

  /// 山脊顶部加雪线。
  final bool snowCaps;
}

class AppBackgrounds {
  AppBackgrounds._();

  static final Map<AppTheme, ScenePalette> _light = {
    // 海洋：日出海面与远浪
    AppTheme.ocean: const ScenePalette(
      skyTop: Color(0xFFEAF6FC), skyBottom: Color(0xFFCBE8F4),
      sun: Color(0xFFFFF3D0), sunGlow: Color(0xFFFFE1A8),
      cloud: Color(0xFFFFFFFF),
      ridgeFar: Color(0xFFBBDCEA), ridgeMid: Color(0xFF9CCBDD),
      ridgeNear: Color(0xFF7FB7CD), ridgeFront: Color(0xFF5F9BB5),
      hasBirds: true, waves: true,
    ),
    // 森林：晨雾山林
    AppTheme.forest: const ScenePalette(
      skyTop: Color(0xFFF1F8EF), skyBottom: Color(0xFFD7EBD8),
      sun: Color(0xFFFFFBE6), sunGlow: Color(0xFFEAF3C8),
      cloud: Color(0xFFFFFFFF),
      ridgeFar: Color(0xFFC3DFC6), ridgeMid: Color(0xFF9CC6A6),
      ridgeNear: Color(0xFF6FA682), ridgeFront: Color(0xFF4A7D63),
      hasBirds: true,
    ),
    // 日落：暖调山峦
    AppTheme.sunset: const ScenePalette(
      skyTop: Color(0xFFFFF4E4), skyBottom: Color(0xFFFFDCC0),
      sun: Color(0xFFFFE0A8), sunGlow: Color(0xFFFFB877),
      cloud: Color(0xFFFFF6EC),
      ridgeFar: Color(0xFFEFC0A2), ridgeMid: Color(0xFFD79C84),
      ridgeNear: Color(0xFFA96E63), ridgeFront: Color(0xFF734A4A),
      hasBirds: true, snowCaps: true,
    ),
    // 暗夜：雪山月夜
    AppTheme.night: const ScenePalette(
      skyTop: Color(0xFFEEF0FA), skyBottom: Color(0xFFCFD6EF),
      sun: Color(0xFFFFFFFF), sunGlow: Color(0xFFDCE4F8),
      cloud: Color(0xFFF6F8FF),
      ridgeFar: Color(0xFFC6CDE8), ridgeMid: Color(0xFFA2ABD2),
      ridgeNear: Color(0xFF7B86B4), ridgeFront: Color(0xFF535E8C),
      hasBirds: false, snowCaps: true,
    ),
    // 极简：淡墨远山
    AppTheme.minimal: const ScenePalette(
      skyTop: Color(0xFFFBFBFA), skyBottom: Color(0xFFEDF0EE),
      sun: Color(0xFFFFFFFF), sunGlow: Color(0xFFF0EFE9),
      cloud: Color(0xFFFFFFFF),
      ridgeFar: Color(0xFFE4E8E6), ridgeMid: Color(0xFFD3DAD7),
      ridgeNear: Color(0xFFBFC8C4), ridgeFront: Color(0xFFA7B3AE),
      hasBirds: true,
    ),
  };

  static final Map<AppTheme, ScenePalette> _dark = {
    AppTheme.ocean: const ScenePalette(
      skyTop: Color(0xFF0E1B26), skyBottom: Color(0xFF14303F),
      sun: Color(0xFFF2E3B8), sunGlow: Color(0xFF6C6142),
      cloud: Color(0xFF2A4553),
      ridgeFar: Color(0xFF173645), ridgeMid: Color(0xFF12303E),
      ridgeNear: Color(0xFF0D2531), ridgeFront: Color(0xFF081A24),
      hasStars: true, hasBirds: false, waves: true,
    ),
    AppTheme.forest: const ScenePalette(
      skyTop: Color(0xFF0D1712), skyBottom: Color(0xFF16281E),
      sun: Color(0xFFEFF3D2), sunGlow: Color(0xFF55603F),
      cloud: Color(0xFF22392C),
      ridgeFar: Color(0xFF1B3428), ridgeMid: Color(0xFF152A20),
      ridgeNear: Color(0xFF0F2018), ridgeFront: Color(0xFF0A1711),
      hasStars: true, hasBirds: false,
    ),
    AppTheme.sunset: const ScenePalette(
      skyTop: Color(0xFF1A1416), skyBottom: Color(0xFF3A2320),
      sun: Color(0xFFEBC48A), sunGlow: Color(0xFF7A4E33),
      cloud: Color(0xFF422A26),
      ridgeFar: Color(0xFF3A2622), ridgeMid: Color(0xFF2B1C1A),
      ridgeNear: Color(0xFF1D1312), ridgeFront: Color(0xFF130C0C),
      hasStars: true, hasBirds: false, snowCaps: true,
    ),
    AppTheme.night: const ScenePalette(
      skyTop: Color(0xFF0A0C18), skyBottom: Color(0xFF181E3C),
      sun: Color(0xFFF2F1E4), sunGlow: Color(0xFF5A5C86),
      cloud: Color(0xFF262C50),
      ridgeFar: Color(0xFF232A4E), ridgeMid: Color(0xFF1A2040),
      ridgeNear: Color(0xFF121731), ridgeFront: Color(0xFF0B0F21),
      hasMoon: true, hasStars: true, hasBirds: false, snowCaps: true,
    ),
    AppTheme.minimal: const ScenePalette(
      skyTop: Color(0xFF121315), skyBottom: Color(0xFF1C1F21),
      sun: Color(0xFFE8E6DF), sunGlow: Color(0xFF45484A),
      cloud: Color(0xFF23272A),
      ridgeFar: Color(0xFF22262A), ridgeMid: Color(0xFF1C2023),
      ridgeNear: Color(0xFF161A1D), ridgeFront: Color(0xFF101315),
      hasStars: true, hasBirds: false,
    ),
  };

  static ScenePalette of(AppTheme theme, Brightness brightness) {
    final map = brightness == Brightness.dark ? _dark : _light;
    return map[theme] ?? map[AppTheme.minimal]!;
  }
}

/// 应用插画背景：天空 + 日月星辰 + 流云 + 层叠山脊（或海浪）+ 飞鸟。
///
/// 【为什么这样布局】插画集中在**顶部约 25%** 与**底部约 32%**，
/// 中间留给内容区——卡片和文字压在上面不会花。
/// 【性能】全部是静态路径与渐变填充：无 blur、无 BackdropFilter、无动画。
class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    required this.theme,
    required this.brightness,
    this.style = BackgroundStyle.scene,
    this.child,
  });

  final AppTheme theme;
  final Brightness brightness;
  final BackgroundStyle style;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = AppBackgrounds.of(theme, brightness);

    final Widget background;
    switch (style) {
      case BackgroundStyle.flat:
        background = ColoredBox(color: p.skyBottom);
      case BackgroundStyle.gradient:
        background = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.skyTop, p.skyBottom],
            ),
          ),
        );
      case BackgroundStyle.scene:
        background = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.skyTop, p.skyBottom],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _ScenePainter(p, brightness)),
              // 内容渐隐纱：中间（卡片密集区）偏实以保证可读，
              // 顶部与底部半透明让太阳和山脊透出来，避免插画被卡片完全盖住。
              // 用天空同色系而非写死白色，否则深色模式会蒙灰、浅色会过曝。
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      p.skyTop.withAlpha(46),
                      p.skyTop.withAlpha(brightness == Brightness.dark ? 195 : 185),
                      p.skyBottom.withAlpha(26),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ],
          ),
        );
    }

    if (child == null) return background;
    return Stack(
      children: [
        Positioned.fill(child: background),
        Positioned.fill(child: child!),
      ],
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.p, this.brightness);

  final ScenePalette p;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    if (p.hasStars) _stars(canvas, w, h);
    if (p.hasMoon) {
      _moon(canvas, Offset(w * 0.78, h * 0.075), w * 0.055);
    } else {
      _sun(canvas, Offset(w * 0.76, h * 0.085), w * 0.05);
    }
    _clouds(canvas, w, h);

    if (p.waves) {
      _waveBand(canvas, size, p.ridgeFar, 0.60, 0.030, 3.0, 0.0);
      _waveBand(canvas, size, p.ridgeMid, 0.68, 0.034, 2.4, 1.1);
      _waveBand(canvas, size, p.ridgeNear, 0.78, 0.040, 2.0, 2.3);
      _waveBand(canvas, size, p.ridgeFront, 0.88, 0.046, 1.7, 3.4);
    } else {
      // 由远及近：越靠前颜色越深、位置越低，形成纵深
      _ridge(canvas, size, 0.615, 0.085, 5, 0.9, p.ridgeFar);
      if (p.snowCaps) _snow(canvas, size, 0.615, 0.085, 5, 0.9, p.ridgeFar);
      _ridge(canvas, size, 0.700, 0.105, 4, 2.4, p.ridgeMid);
      _ridge(canvas, size, 0.790, 0.125, 5, 4.1, p.ridgeNear);
      if (p.snowCaps) _snow(canvas, size, 0.790, 0.125, 5, 4.1, p.ridgeNear);
      _ridge(canvas, size, 0.885, 0.150, 3, 5.7, p.ridgeFront);
    }

    if (p.hasBirds) _birds(canvas, w, h);
  }

  void _sun(Canvas c, Offset center, double r) {
    // 外圈光晕
    c.drawCircle(
      center,
      r * 4.2,
      Paint()
        ..shader = RadialGradient(colors: [
          p.sunGlow.withAlpha(brightness == Brightness.dark ? 90 : 110),
          p.sunGlow.withAlpha(0),
        ]).createShader(Rect.fromCircle(center: center, radius: r * 4.2)),
    );
    c.drawCircle(center, r, Paint()..color = p.sun.withAlpha(235));
    c.drawCircle(center, r * 0.62, Paint()..color = Colors.white.withAlpha(90));
  }

  void _moon(Canvas c, Offset center, double r) {
    c.drawCircle(
      center,
      r * 3.6,
      Paint()
        ..shader = RadialGradient(colors: [
          p.sunGlow.withAlpha(80),
          p.sunGlow.withAlpha(0),
        ]).createShader(Rect.fromCircle(center: center, radius: r * 3.6)),
    );
    // 月牙：Path.subtract 在 Flutter 里不存在，要用 Path.combine(difference)
    final full = Path()..addOval(Rect.fromCircle(center: center, radius: r));
    final bite = Path()
      ..addOval(Rect.fromCircle(
          center: center + Offset(r * 0.45, -r * 0.28), radius: r * 0.92));
    c.drawPath(
      Path.combine(PathOperation.difference, full, bite),
      Paint()..color = p.sun.withAlpha(240),
    );
  }

  void _stars(Canvas c, double w, double h) {
    final rnd = math.Random(7);
    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < 46; i++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * h * 0.42;
      final a = (60 + rnd.nextDouble() * 150).round();
      final r = 0.6 + rnd.nextDouble() * 1.3;
      paint.color = Colors.white.withAlpha(a);
      c.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _clouds(Canvas c, double w, double h) {
    // 每朵云由 4 个错开的椭圆叠成，边缘靠低透明度自然柔化
    void cloud(double fx, double fy, double scale, int alpha) {
      final paint = Paint()..color = p.cloud.withAlpha(alpha);
      final at = Offset(w * fx, h * fy);
      final blobs = <(double, double, double)>[
        (0.0, 0.0, 26.0),
        (24.0, 6.0, 19.0),
        (-24.0, 7.0, 17.0),
        (10.0, -10.0, 17.0),
      ];
      for (final b in blobs) {
        final dx = b.$1 * scale;
        final dy = b.$2 * scale;
        final r = b.$3 * scale;
        c.drawOval(
          Rect.fromCenter(
              center: at + Offset(dx, dy),
              width: r * 2.4,
              height: r * 1.5),
          paint,
        );
      }
    }

    final unit = w / 390.0;
    cloud(0.20, 0.075, unit, 120);
    cloud(0.52, 0.135, unit * 0.72, 90);
    cloud(0.86, 0.185, unit * 0.60, 70);
  }

  /// 一层山脊：从 baseline 向上起伏，下方填满。
  void _ridge(Canvas c, Size s, double baseRatio, double ampRatio, int peaks,
      double phase, Color color) {
    final w = s.width, h = s.height;
    final base = h * baseRatio;
    final amp = h * ampRatio;
    final step = w / peaks;

    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, base);
    for (var i = 0; i < peaks; i++) {
      final x0 = i * step;
      final peakX = x0 + step * (0.42 + 0.16 * math.sin(phase + i * 1.7));
      final peakY = base - amp * (0.5 + 0.5 * math.sin(phase * 1.3 + i * 2.1)).abs();
      final valleyY = base - amp * 0.06;
      path
        ..lineTo(peakX, peakY)
        ..lineTo(x0 + step, valleyY);
    }
    path.lineTo(w, h);
    path.close();

    c.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // 山顶略亮、山脚略暗，增强体积感
          colors: [
            Color.alphaBlend(Colors.white.withAlpha(16), color),
            Color.alphaBlend(Colors.black.withAlpha(22), color),
          ],
        ).createShader(Rect.fromLTWH(0, base - amp, w, h - base + amp)),
    );
  }

  /// 雪线：在山脊峰顶画一小块浅色。
  void _snow(Canvas c, Size s, double baseRatio, double ampRatio, int peaks,
      double phase, Color _) {
    final w = s.width, h = s.height;
    final base = h * baseRatio;
    final amp = h * ampRatio;
    final step = w / peaks;
    final paint = Paint()..color = Colors.white.withAlpha(brightness == Brightness.dark ? 110 : 150);
    for (var i = 0; i < peaks; i++) {
      final x0 = i * step;
      final peakX = x0 + step * (0.42 + 0.16 * math.sin(phase + i * 1.7));
      final peakY = base - amp * (0.5 + 0.5 * math.sin(phase * 1.3 + i * 2.1)).abs();
      final cap = Path()
        ..moveTo(peakX, peakY)
        ..lineTo(peakX + step * 0.13, peakY + h * 0.022)
        ..lineTo(peakX + step * 0.05, peakY + h * 0.016)
        ..lineTo(peakX - step * 0.04, peakY + h * 0.024)
        ..lineTo(peakX - step * 0.12, peakY + h * 0.014)
        ..close();
      c.drawPath(cap, paint);
    }
  }

  /// 一层海浪：正弦曲线下方填满。
  void _waveBand(Canvas c, Size s, Color color, double baseRatio,
      double ampRatio, double freq, double phase) {
    final w = s.width, h = s.height;
    final base = h * baseRatio;
    final amp = h * ampRatio;
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, base);
    for (var x = 0.0; x <= w; x += 6) {
      final y = base + math.sin(x / w * math.pi * 2 * freq + phase) * amp;
      path.lineTo(x, y);
    }
    path
      ..lineTo(w, h)
      ..close();
    c.drawPath(path, Paint()..color = color);

    // 浪尖高光
    final hl = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withAlpha(brightness == Brightness.dark ? 40 : 90);
    final top = Path();
    for (var x = 0.0; x <= w; x += 6) {
      final y = base + math.sin(x / w * math.pi * 2 * freq + phase) * amp;
      if (x == 0) {
        top.moveTo(x, y);
      } else {
        top.lineTo(x, y);
      }
    }
    c.drawPath(top, hl);
  }

  void _birds(Canvas c, double w, double h) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = (brightness == Brightness.dark ? Colors.white : Colors.black87)
          .withAlpha(110);
    for (final (x, y, s) in [(0.30, 0.115, 1.0), (0.38, 0.085, 0.75), (0.44, 0.125, 0.6)]) {
      final cx = w * x, cy = h * y, r = w * 0.018 * s;
      final path = Path()
        ..moveTo(cx - r, cy)
        ..quadraticBezierTo(cx - r * 0.45, cy - r * 0.8, cx, cy - r * 0.15)
        ..quadraticBezierTo(cx + r * 0.45, cy - r * 0.8, cx + r, cy);
      c.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.p != p || old.brightness != brightness;
}
