import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/mood_type.dart';

/// 单个粒子的归一化随机参数（坐标/速度/大小/相位/摆动），由 [buildMoodParticles] 生成。
class MoodParticle {
  const MoodParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.phase,
    required this.drift,
  });

  final double x; // 0..1
  final double y; // 0..1
  final double speed;
  final double size;
  final double phase; // 0..1 随机相位
  final double drift; // 左右摆动幅度

  static List<MoodParticle> make(int count, int seed) {
    final r = math.Random(seed);
    return List.generate(
      count,
      (_) => MoodParticle(
        x: r.nextDouble(),
        y: r.nextDouble(),
        speed: 0.25 + r.nextDouble() * 0.9,
        size: r.nextDouble(),
        phase: r.nextDouble(),
        drift: (r.nextDouble() - 0.5) * 2,
      ),
    );
  }
}

/// 心情粒子特效绘制器。
///
/// 设计约束（淡雅档）：
/// - 完全无状态，只依赖 `t`（秒）与粒子表 → 暂停/恢复不会跳变
/// - 不使用 saveLayer / MaskFilter.blur（用径向渐变模拟发光），保证低端机流畅
/// - 所有透明度压低，避免干扰正文阅读
class MoodPainter extends CustomPainter {
  MoodPainter({required this.mood, required this.t, required this.particles});

  final MoodType mood;
  final double t;
  final List<MoodParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    // 先铺一层极淡氛围色，让每种心情有整体色调差异（不影响文字可读）
    _applyTint(canvas, size);
    switch (mood) {
      case MoodType.rain:
        _paintRain(canvas, size);
        break;
      case MoodType.sunshine:
        _paintSunshine(canvas, size);
        break;
      case MoodType.snow:
        _paintSnow(canvas, size);
        break;
      case MoodType.petal:
        _paintPetal(canvas, size);
        break;
      case MoodType.star:
        _paintStar(canvas, size);
        break;
      case MoodType.leaf:
        _paintLeaf(canvas, size);
        break;
      case MoodType.night:
        _paintNight(canvas, size);
        break;
      case MoodType.wind:
        _paintWind(canvas, size);
        break;
      case MoodType.rainbow:
        _paintRainbow(canvas, size);
        break;
      case MoodType.waves:
        _paintWaves(canvas, size);
        break;
      case MoodType.fireworks:
        _paintFireworks(canvas, size);
        break;
      case MoodType.mist:
        _paintMist(canvas, size);
        break;
    }
  }

  // ---------- 各心情实现 ----------

  /// 每种心情的整体氛围色（极淡，顶部浓、往下渐隐）。
  static const Map<MoodType, Color> _tints = {
    MoodType.rain: Color(0xFF4A6E96),
    MoodType.sunshine: Color(0xFFFFD98A),
    MoodType.snow: Color(0xFFCBE4F2),
    MoodType.petal: Color(0xFFF3B6C6),
    MoodType.star: Color(0xFF4A4E8F),
    MoodType.leaf: Color(0xFFD9A05B),
    MoodType.night: Color(0xFF243257),
    MoodType.wind: Color(0xFFB6D2DC),
    MoodType.rainbow: Color(0xFFE8B4D2),
    MoodType.waves: Color(0xFF7FC4DA),
    MoodType.fireworks: Color(0xFF6A3A6E),
    MoodType.mist: Color(0xFFB9C6D4),
  };

  void _applyTint(Canvas c, Size s) {
    final color = _tints[mood];
    if (color == null) return;
    // 夜/星/烟花用稍强的沉浸感，其余保持极淡
    final deep = mood == MoodType.night || mood == MoodType.star || mood == MoodType.fireworks;
    final top = deep ? 46 : 26;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withAlpha(top), color.withAlpha(0)],
        stops: const [0.0, 0.72],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
    c.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), paint);
  }

  /// 依据粒子 size 做远近景深：远处小而慢而淡，近处大而快而亮。
  double _depth(MoodParticle p) => 0.45 + p.size * 0.55; // 0.45..1.0

  /// 🌧️ 斜落雨丝（远近景深）+ 落地水花
  void _paintRain(Canvas c, Size s) {
    final line = Paint()
      ..strokeCap = StrokeCap.round;
    final splash = Paint()..style = PaintingStyle.stroke;
    final n = math.min(64, particles.length);
    for (var i = 0; i < n; i++) {
      final p = particles[i];
      final d = _depth(p); // 远处慢、近处快
      final fall = (p.y + t * (0.8 + d * 1.1)) % 1.15;
      final y = (fall - 0.1) * s.height;
      final x = p.x * s.width + y * 0.14;
      final len = (8 + d * 16);
      line
        ..strokeWidth = 0.7 + d * 0.9
        ..color = const Color(0xFF6E8FB8).withAlpha((34 + d * 62).round());
      c.drawLine(Offset(x, y), Offset(x - len * 0.14, y - len), line);

      if (fall > 0.93) {
        final k = ((fall - 0.93) / 0.22).clamp(0.0, 1.0);
        splash.color = const Color(0xFF6E8FB8).withAlpha((44 * d * (1 - k)).round());
        c.drawOval(
          Rect.fromCenter(
              center: Offset(x, s.height * 0.985),
              width: 3 + k * 13 * d,
              height: 1 + k * 4.5 * d),
          splash,
        );
      }
    }
  }

  /// ☀️ 右上暖光呼吸 + 上升光尘
  void _paintSunshine(Canvas c, Size s) {
    final pulse = 0.5 + 0.5 * math.sin(t * 0.8);
    final center = Offset(s.width * 0.86, s.height * 0.1);
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFFFFD98A).withAlpha((34 + pulse * 22).round()),
        const Color(0xFFFFD98A).withAlpha(0),
      ], stops: const [0.0, 1.0], tileMode: TileMode.clamp)
          .createShader(Rect.fromCircle(center: center, radius: s.width * (0.42 + pulse * 0.06)));
    c.drawCircle(center, s.width * (0.48 + pulse * 0.06), glow);

    final dot = Paint();
    final n = math.min(16, particles.length);
    for (var i = 0; i < n; i++) {
      final p = particles[i];
      final rise = (p.y - t * (0.03 + p.speed * 0.05)) % 1.0;
      final y = (rise < 0 ? rise + 1.0 : rise) * s.height;
      final x = p.x * s.width + math.sin(t * 0.6 + p.phase * 6.28) * 12 * p.drift;
      dot.color = const Color(0xFFFFE9B8).withAlpha(38 + (p.size * 30).round());
      c.drawCircle(Offset(x, y), 1.1 + p.size * 1.9, dot);
    }
  }

  /// ❄️ 缓落雪花（远近两层，近处更大更亮且摇曳更明显）
  void _paintSnow(Canvas c, Size s) {
    final paint = Paint();
    final n = math.min(44, particles.length);
    for (var i = 0; i < n; i++) {
      final p = particles[i];
      final d = _depth(p);
      final fall = (p.y + t * (0.04 + d * 0.07)) % 1.1;
      final y = (fall - 0.05) * s.height;
      final x = p.x * s.width + math.sin(t * (0.5 + d) + p.phase * 6.28) * 20 * p.drift;
      paint.color = Colors.white.withAlpha((44 + d * 76).round());
      c.drawCircle(Offset(x, y), 1.1 + d * 3.0, paint);
      // 近处雪花画成六角，增加细节层次
      if (d > 0.85) {
        paint.color = Colors.white.withAlpha((30 + d * 40).round());
        final r = 1.1 + d * 3.0;
        for (var k = 0; k < 3; k++) {
          final a = k * math.pi / 3 + t * 0.25;
          c.drawLine(Offset(x - math.cos(a) * r * 1.9, y - math.sin(a) * r * 1.9),
              Offset(x + math.cos(a) * r * 1.9, y + math.sin(a) * r * 1.9), paint);
        }
      }
    }
  }

  /// 🌸 旋转飘落花瓣（远近两层）
  void _paintPetal(Canvas c, Size s) {
    final paint = Paint();
    final n = math.min(30, particles.length);
    for (var i = 0; i < n; i++) {
      final p = particles[i];
      final d = _depth(p);
      final prog = (p.y + t * (0.05 + d * 0.09)) % 1.15;
      final y = (prog - 0.07) * s.height;
      final x = p.x * s.width + math.sin(t * (0.7 + d * 0.5) + p.phase * 6.28) * 30 * p.drift;
      final rot = t * (0.8 + d * 0.9) + p.phase * 6.28;
      final w = (3.5 + d * 6.0);
      c.save();
      c.translate(x, y);
      c.rotate(rot);
      // 翻转感：横向压缩
      c.scale(math.cos(rot * 1.2).abs() * 0.65 + 0.35, 1);
      paint.color = Color.lerp(const Color(0xFFF7C8D6), const Color(0xFFE88FB4), p.size)!
          .withAlpha((40 + d * 62).round());
      final path = Path()
        ..moveTo(0, -w * 0.5)
        ..quadraticBezierTo(w * 0.72, 0, 0, w * 0.5)
        ..quadraticBezierTo(-w * 0.35, 0, 0, -w * 0.5);
      c.drawPath(path, paint);
      c.restore();
    }
  }

  /// ✨ 明灭星点 + 偶发流星
  void _paintStar(Canvas c, Size s) {
    final paint = Paint();
    final n = math.min(36, particles.length);
    for (var i = 0; i < n; i++) {
      final p = particles[i];
      final tw = 0.5 + 0.5 * math.sin(t * (1.2 + p.speed * 1.6) + p.phase * 6.28);
      final alpha = (18 + tw * 70).round();
      final r = (1.0 + p.size * 1.8) * (0.6 + tw * 0.6);
      final pos = Offset(p.x * s.width, p.y * s.height * 0.8);
      paint.color = const Color(0xFFFFE9A8).withAlpha(alpha);
      // 四角星
      final path = Path();
      final arm = r * 3.2;
      path
        ..moveTo(pos.dx, pos.dy - arm)
        ..quadraticBezierTo(pos.dx + r * 0.5, pos.dy - r * 0.5, pos.dx + arm, pos.dy)
        ..quadraticBezierTo(pos.dx + r * 0.5, pos.dy + r * 0.5, pos.dx, pos.dy + arm)
        ..quadraticBezierTo(pos.dx - r * 0.5, pos.dy + r * 0.5, pos.dx - arm, pos.dy)
        ..quadraticBezierTo(pos.dx - r * 0.5, pos.dy - r * 0.5, pos.dx, pos.dy - arm);
      c.drawPath(path, paint);
    }

    // 流星：每 6 秒一次，划过 1.4 秒
    final cyc = (t % 6.0) / 1.4;
    if (cyc < 1.0) {
      final k = cyc;
      final sx = s.width * (0.75 - k * 0.55);
      final sy = s.height * (0.12 + k * 0.3);
      final tail = Paint()
        ..strokeWidth = 1.6
        ..shader = LinearGradient(colors: [
          Colors.white.withAlpha((110 * (1 - k)).round()),
          Colors.white.withAlpha(0),
        ]).createShader(Rect.fromPoints(Offset(sx, sy), Offset(sx + 90, sy - 46)));
      c.drawLine(Offset(sx, sy), Offset(sx + 90, sy - 46), tail);
    }
  }

  /// 🍂 翻转落叶
  void _paintLeaf(Canvas c, Size s) {
    final paint = Paint()..style = PaintingStyle.fill;
    final n = math.min(20, particles.length);
    for (var i = 0; i < n; i++) {
      final p = particles[i];
      final prog = (p.y + t * (0.07 + p.speed * 0.08)) % 1.2;
      final y = (prog - 0.1) * s.height;
      final x = p.x * s.width + math.sin(t * 0.8 + p.phase * 6.28) * 34 * p.drift;
      final rot = t * (1.1 + p.speed) + p.phase * 6.28;
      final w = 5 + p.size * 5;
      c.save();
      c.translate(x, y);
      c.rotate(rot);
      // 翻转感：横向压缩随旋转变化
      c.scale(math.cos(rot * 0.8).abs() * 0.7 + 0.3, 1);
      paint.color = Color.lerp(const Color(0xFFD9A05B), const Color(0xFFB4703A), p.size)!
          .withAlpha(60 + (p.size * 36).round());
      final path = Path()
        ..moveTo(0, -w)
        ..quadraticBezierTo(w * 0.8, 0, 0, w)
        ..quadraticBezierTo(-w * 0.8, 0, 0, -w);
      c.drawPath(path, paint);
      c.restore();
    }
  }

  /// 🌙 顶部极淡夜色 + 萤火浮动
  void _paintNight(Canvas c, Size s) {
    final tint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF2B3A63).withAlpha(26), const Color(0xFF2B3A63).withAlpha(0)],
        stops: const [0.0, 0.45],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
    c.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), tint);

    final glow = Paint();
    final n = math.min(10, particles.length);
    for (var i = 0; i < n; i++) {
      final p = particles[i];
      final x = p.x * s.width + math.sin(t * 0.45 + p.phase * 6.28) * 30;
      final y = s.height * (0.35 + p.y * 0.55) + math.cos(t * 0.35 + p.phase * 3.1) * 18;
      final blink = 0.5 + 0.5 * math.sin(t * (1.4 + p.speed) + p.phase * 6.28);
      final r = (2.2 + p.size * 2.0) * (0.7 + blink * 0.5);
      glow.shader = RadialGradient(colors: [
        const Color(0xFFD9E88A).withAlpha((26 + blink * 60).round()),
        const Color(0xFFD9E88A).withAlpha(0),
      ]).createShader(Rect.fromCircle(center: Offset(x, y), radius: r * 3.4));
      c.drawCircle(Offset(x, y), r * 3.4, glow);
    }
  }

  /// 💨 横向流线
  void _paintWind(Canvas c, Size s) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    final n = math.min(11, particles.length);
    for (var i = 0; i < n; i++) {
      final p = particles[i];
      final prog = (p.x + t * (0.16 + p.speed * 0.22)) % 1.4;
      final baseX = (prog - 0.2) * s.width;
      final y = s.height * (0.12 + p.y * 0.76);
      final len = 40 + p.size * 70;
      // 进出场淡入淡出
      final edge = math.min(prog / 0.2, (1.4 - prog) / 0.2).clamp(0.0, 1.0);
      paint.color = const Color(0xFF9FBAC9).withAlpha((30 + edge * 44).round());
      final path = Path()
        ..moveTo(baseX, y)
        ..quadraticBezierTo(baseX + len * 0.5, y - 7 * p.drift, baseX + len, y);
      c.drawPath(path, paint);
    }
  }

  /// 🌈 缓慢掠过的光弧
  void _paintRainbow(Canvas c, Size s) {
    const colors = [
      Color(0xFFF2A0A0), Color(0xFFF4C793), Color(0xFFF7E9A0),
      Color(0xFFA8D8A8), Color(0xFF9CC7E8), Color(0xFFBBA8E0),
    ];
    final sweep = (t * 0.06) % 1.6; // 缓慢横扫
    final cx = s.width * (sweep * 1.4 - 0.2);
    final cy = s.height * 0.95;
    final base = s.width * 0.62;
    final fade = math.min(sweep / 0.25, (1.6 - sweep) / 0.25).clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    for (var i = 0; i < colors.length; i++) {
      paint.color = colors[i].withAlpha((14 + fade * 22).round());
      final r = base - i * 6.5;
      c.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), math.pi, math.pi, false, paint);
    }
  }

  /// 🌊 底部波纹
  void _paintWaves(Canvas c, Size s) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var layer = 0; layer < 3; layer++) {
      final amp = 5.0 + layer * 2.5;
      final yBase = s.height * (0.9 - layer * 0.035);
      final speed = 0.7 + layer * 0.25;
      paint.color = const Color(0xFF6FB4CC).withAlpha(34 - layer * 7);
      final path = Path()..moveTo(0, yBase);
      for (var x = 0.0; x <= s.width; x += 8) {
        final y = yBase + math.sin(x / 46 + t * speed + layer) * amp;
        path.lineTo(x, y);
      }
      c.drawPath(path, paint);
    }
  }

  /// 🎆 烟花：主束 + 半周期错开的副束，形成连续绽放感
  void _paintFireworks(Canvas c, Size s) {
    _burst(c, s, t, 0.0, 20, 1.0);
    _burst(c, s, t, 1.45, 14, 0.62);
  }

  void _burst(Canvas c, Size s, double time, double offset, int rays, double scale) {
    const period = 2.9;
    final local = (((time - offset) % period) / period);
    if (time < offset || local <= 0 || local > 0.85) return;
    final idx = ((time - offset) / period).floor();

    final rnd = math.Random(idx * 977 + 13);
    final cx = s.width * (0.18 + rnd.nextDouble() * 0.64);
    final cy = s.height * (0.14 + rnd.nextDouble() * 0.34);
    final hue = rnd.nextDouble();
    final base = HSVColor.fromAHSV(1, hue * 360, 0.6, 0.95).toColor();
    final ease = Curves.easeOutCubic.transform(local);
    final alpha = ((1 - local / 0.85) * 110 * scale).round();
    final paint = Paint()..strokeWidth = 1.5;
    for (var i = 0; i < rays; i++) {
      final ang = (i / rays) * 6.28318 + idx;
      final dist = ease * (30 + (i % 3) * 15) * scale;
      final tip = Offset(
          cx + math.cos(ang) * dist,
          cy + math.sin(ang) * dist * 0.92 + ease * ease * 14);
      paint.color = base.withAlpha(alpha);
      c.drawCircle(tip, 1.4 + (1 - local) * 1.4 * scale, paint);
      paint.color = base.withAlpha((alpha * 0.5).round());
      c.drawLine(
        Offset(cx + math.cos(ang) * dist * 0.7, cy + math.sin(ang) * dist * 0.7 * 0.92),
        tip,
        paint,
      );
    }
  }

  /// 🌫️ 缓慢漂移的雾团
  void _paintMist(Canvas c, Size s) {
    final paint = Paint();
    final n = math.min(6, particles.length);
    for (var i = 0; i < n; i++) {
      final p = particles[i];
      final prog = (p.x + t * (0.02 + p.speed * 0.025)) % 1.5;
      final x = (prog - 0.25) * s.width;
      final y = s.height * (0.2 + p.y * 0.6);
      final r = s.width * (0.16 + p.size * 0.16);
      paint.shader = RadialGradient(colors: [
        const Color(0xFFB9C6D4).withAlpha(20 + (p.size * 14).round()),
        const Color(0xFFB9C6D4).withAlpha(0),
      ]).createShader(Rect.fromCircle(center: Offset(x, y), radius: r));
      c.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant MoodPainter old) =>
      old.t != t || old.mood != mood || old.particles != particles;
}
