import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/sprite_form.dart';
import 'sprite_skin.dart';

/// 3D 观感的精灵绘制器。
///
/// 用**多层径向渐变 + 高光条 + 边缘轮廓光 + 半透明虹彩翅膀**模拟柔和立体渲染。
/// 不是真 3D：没有透视旋转与真实光照模型，但在 60~90px 的悬浮尺寸下
/// 足以呈现"软 3D 手办"观感，同时保持零图片资源、跟随主题、可逐帧做表情。
class SpritePainter extends CustomPainter {
  SpritePainter({
    required this.skin,
    required this.mood,
    required this.t,
    required this.dark,
  });

  final SpriteSkin skin;
  final SpriteMood mood;
  final double t;
  final bool dark;

  // 几何比例（相对画布）
  static const double _headCy = 0.355;
  static const double _headR = 0.295;
  static const double _bodyCy = 0.685;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2;
    final headC = Offset(cx, h * _headCy);
    final headR = w * _headR;

    _groundShadow(canvas, size);
    if (skin.wings) _wings(canvas, size);
    _body(canvas, size);
    if (skin.backpack) _straps(canvas, size);
    _chestCore(canvas, size);
    if (skin.camera) _camera(canvas, size);
    if (skin.chip) _chip(canvas, size);
    _head(canvas, headC, headR);
    if (skin.earDisc) _ears(canvas, headC, headR);
    _visor(canvas, headC, headR);
    _face(canvas, headC, headR);
    _rimLight(canvas, headC, headR, w, h);
    if (skin.glassHead) _glassHighlight(canvas, headC, headR);
    if (skin.starfield) _starfield(canvas, headC, headR);
    if (skin.circuits) _circuits(canvas, headC, headR);
    if (skin.halo) _halo(canvas, headC, headR);
    if (skin.antenna) _antenna(canvas, headC, headR);
    _cue(canvas, size);
  }

  // ---------------- 基础件 ----------------

  /// 径向渐变球体：受光点偏左上，营造体积感。
  void _sphere(Canvas c, Offset center, double r,
      {Color? light, Color? mid, Color? shadow, double focal = 0.42}) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(-0.45, -0.5),
        radius: 1.15,
        colors: [
          light ?? skin.shellLight,
          mid ?? skin.shellMid,
          shadow ?? skin.shellShadow,
        ],
        stops: [0.0, focal, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    c.drawCircle(center, r, paint);
  }

  void _groundShadow(Canvas c, Size s) {
    final cy = s.height * 0.955;
    final rx = s.width * 0.26;
    final paint = Paint()
      ..shader = RadialGradient(colors: [
        Colors.black.withAlpha(dark ? 70 : 46),
        Colors.black.withAlpha(0),
      ]).createShader(
          Rect.fromCenter(center: Offset(s.width / 2, cy), width: rx * 2, height: rx * 0.9));
    c.drawOval(
      Rect.fromCenter(center: Offset(s.width / 2, cy), width: rx * 2, height: rx * 0.9),
      paint,
    );
  }

  // ---------------- 身体 ----------------

  void _body(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final cx = w / 2;
    final bw = w * 0.30, bh = h * 0.26;
    final rect = Rect.fromCenter(center: Offset(cx, h * _bodyCy), width: bw, height: bh);

    // 腿
    final legPaint = Paint();
    for (final dx in [-0.075, 0.075]) {
      legPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [skin.shellMid, skin.shellShadow],
      ).createShader(Rect.fromLTWH(cx + w * dx - w * 0.045, h * 0.78, w * 0.09, h * 0.12));
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx + w * dx - w * 0.045, h * 0.78, w * 0.09, h * 0.115),
          Radius.circular(w * 0.05),
        ),
        legPaint,
      );
    }

    // 手臂
    final armR = w * 0.052;
    for (final side in [-1, 1]) {
      final swing = mood == SpriteMood.happy && side > 0
          ? math.sin(t * 10) * 0.5 - 0.6
          : math.sin(t * 1.6 + (side > 0 ? 1.2 : 0)) * 0.12;
      final start = Offset(cx + side * bw * 0.5, h * 0.63);
      final end = start + Offset(math.sin(swing) * w * 0.13, w * 0.14 * math.cos(swing));
      c.drawLine(
        start,
        end,
        Paint()
          ..shader = LinearGradient(
            colors: [skin.shellMid, skin.shellShadow],
          ).createShader(Rect.fromLTWH(
              math.min(start.dx, end.dx) - 4, math.min(start.dy, end.dy) - 4, 8, 8))
          ..strokeWidth = armR * 1.5
          ..strokeCap = StrokeCap.round,
      );
      _sphere(c, end, armR * 0.92, focal: 0.5);
    }

    // 躯干
    final torsoPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.5),
        radius: 1.2,
        colors: [skin.shellLight, skin.shellMid, skin.shellShadow],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(bw * 0.44)),
      torsoPaint,
    );
  }

  void _straps(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final brown = Paint()
      ..color = dark ? const Color(0xFF6B5540) : const Color(0xFF8D6E4F)
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round;
    for (final dx in [-0.085, 0.085]) {
      c.drawLine(
        Offset(w / 2 + w * dx, h * 0.60),
        Offset(w / 2 + w * dx * 1.15, h * 0.74),
        brown,
      );
    }
    // 背包侧面露出一点
    final pack = Paint()
      ..color = (dark ? const Color(0xFF5A4633) : const Color(0xFF7A5C3F));
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w / 2 + w * 0.175, h * 0.665), width: w * 0.075, height: h * 0.10),
        Radius.circular(w * 0.03),
      ),
      pack,
    );
  }

  void _chestCore(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final center = Offset(w / 2, h * 0.665);
    final r = w * 0.075;
    final pulse = 0.6 + 0.4 * math.sin(t * 2.2);

    // 外发光
    c.drawCircle(
      center,
      r * 2.4,
      Paint()
        ..shader = RadialGradient(colors: [
          skin.core.withAlpha((70 * pulse).round()),
          skin.core.withAlpha(0),
        ]).createShader(Rect.fromCircle(center: center, radius: r * 2.4)),
    );
    // 环
    c.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.34
          ..color = skin.core.withAlpha(200));
    // 内芯
    c.drawCircle(
        center,
        r * 0.45,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withAlpha(230),
            skin.core,
          ]).createShader(Rect.fromCircle(center: center, radius: r * 0.45)));
  }

  void _camera(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final rect = Rect.fromCenter(
        center: Offset(w * 0.30, h * 0.72), width: w * 0.19, height: w * 0.135);
    c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w * 0.022)),
      Paint()..color = dark ? const Color(0xFF3A3A40) : const Color(0xFF4A4A52),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left + w * 0.055, rect.top - w * 0.022, w * 0.06, w * 0.026),
          Radius.circular(w * 0.01)),
      Paint()..color = dark ? const Color(0xFF3A3A40) : const Color(0xFF4A4A52),
    );
    final lens = Offset(rect.center.dx, rect.center.dy + w * 0.005);
    c.drawCircle(lens, w * 0.045, Paint()..color = const Color(0xFF22242A));
    c.drawCircle(
      lens,
      w * 0.032,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [const Color(0xFF9FD8FF), const Color(0xFF2A5A8C)],
        ).createShader(Rect.fromCircle(center: lens, radius: w * 0.032)),
    );
    c.drawCircle(lens + Offset(-w * 0.012, -w * 0.012), w * 0.008,
        Paint()..color = Colors.white.withAlpha(220));
  }

  void _chip(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final center = Offset(w * 0.5, h * 0.80);
    final r = w * 0.085;
    final rect = Rect.fromCenter(center: center, width: r * 2, height: r * 2);

    c.drawCircle(
      center,
      r * 2.6,
      Paint()
        ..shader = RadialGradient(colors: [
          skin.core.withAlpha(90),
          skin.core.withAlpha(0),
        ]).createShader(Rect.fromCircle(center: center, radius: r * 2.6)),
    );
    // 引脚
    final pin = Paint()..color = const Color(0xFFD9A94B);
    for (var i = 0; i < 4; i++) {
      final off = -r * 0.6 + i * (r * 0.4);
      c.drawRect(Rect.fromLTWH(rect.left - w * 0.018, center.dy + off, w * 0.018, w * 0.012), pin);
      c.drawRect(Rect.fromLTWH(rect.right, center.dy + off, w * 0.018, w * 0.012), pin);
    }
    c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w * 0.014)),
      Paint()..color = dark ? const Color(0xFF2E2A38) : const Color(0xFFEFE7D6),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(w * 0.016), Radius.circular(w * 0.01)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFD9A94B),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: 'AI',
        style: TextStyle(
            fontSize: r * 1.05, fontWeight: FontWeight.w800, color: skin.core),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  // ---------------- 头与脸 ----------------

  void _head(Canvas c, Offset center, double r) {
    if (skin.glassHead) {
      // 透明穹顶：内部偏暗的太空，外面一圈玻璃
      c.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.45),
            radius: 1.1,
            colors: [
              Colors.white.withAlpha(dark ? 120 : 175),
              skin.shellMid.withAlpha(dark ? 150 : 200),
              skin.shellShadow.withAlpha(210),
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
      return;
    }
    _sphere(c, center, r);
    // 顶部柔和高光
    c.drawOval(
      Rect.fromCenter(
          center: center + Offset(-r * 0.28, -r * 0.52), width: r * 0.85, height: r * 0.5),
      Paint()..color = Colors.white.withAlpha(dark ? 60 : 130),
    );
  }

  void _glassHighlight(Canvas c, Offset center, double r) {
    // 玻璃反光：两道斜高光
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));
    final p = Paint()..color = Colors.white.withAlpha(dark ? 70 : 120);
    c.drawOval(
      Rect.fromCenter(
          center: center + Offset(-r * 0.35, -r * 0.42), width: r * 0.7, height: r * 0.34),
      p,
    );
    c.drawOval(
      Rect.fromCenter(
          center: center + Offset(r * 0.42, r * 0.3), width: r * 0.34, height: r * 0.16),
      Paint()..color = Colors.white.withAlpha(dark ? 45 : 80),
    );
    c.restore();
  }

  void _ears(Canvas c, Offset center, double r) {
    for (final side in [-1, 1]) {
      final e = Offset(center.dx + side * r * 0.98, center.dy + r * 0.06);
      c.drawCircle(e, r * 0.24, Paint()..color = skin.shellShadow);
      c.drawCircle(
        e,
        r * 0.16,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.4),
            colors: [Colors.white.withAlpha(200), skin.core],
          ).createShader(Rect.fromCircle(center: e, radius: r * 0.16)),
      );
    }
  }

  void _visor(Canvas c, Offset center, double r) {
    final vw = r * 1.34, vh = r * 0.92;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center + Offset(0, r * 0.04), width: vw, height: vh),
      Radius.circular(r * 0.40),
    );

    c.drawRRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [skin.visorTop, skin.visorBottom],
        ).createShader(rect.outerRect),
    );
    // 屏幕内发光（底部）
    c.save();
    c.clipRRect(rect);
    c.drawRRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 1.1),
          radius: 1.2,
          colors: [skin.eye.withAlpha(70), skin.eye.withAlpha(0)],
        ).createShader(rect.outerRect),
    );
    // 镜面斜高光条
    c.drawOval(
      Rect.fromCenter(
          center: center + Offset(-vw * 0.22, -vh * 0.34),
          width: vw * 0.55,
          height: vh * 0.20),
      Paint()..color = Colors.white.withAlpha(dark ? 40 : 62),
    );
    c.restore();

    // 外圈描边
    c.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.055
        ..color = skin.shellShadow.withAlpha(230),
    );
  }

  void _face(Canvas c, Offset center, double r) {
    final eyeY = center.dy + r * 0.02;
    final dx = r * 0.30;
    final er = r * 0.115;
    final left = Offset(center.dx - dx, eyeY);
    final right = Offset(center.dx + dx, eyeY);

    final fill = Paint()..color = skin.eye;
    final stroke = Paint()
      ..color = skin.eye
      ..style = PaintingStyle.stroke
      ..strokeWidth = er * 1.1
      ..strokeCap = StrokeCap.round;

    switch (mood) {
      case SpriteMood.happy:
        for (final e in [left, right]) {
          c.drawArc(Rect.fromCircle(center: e, radius: er * 1.25), math.pi * 1.15,
              math.pi * 0.7, false, stroke);
        }
        break;
      case SpriteMood.dragging:
        for (final pair in [
          [left, 1.0],
          [right, -1.0],
        ]) {
          final e = pair[0] as Offset;
          final f = pair[1] as double;
          c.drawLine(Offset(e.dx + er * f, e.dy - er * 1.1),
              Offset(e.dx - er * f * 0.4, e.dy), stroke);
          c.drawLine(Offset(e.dx + er * f, e.dy + er * 1.1),
              Offset(e.dx - er * f * 0.4, e.dy), stroke);
        }
        break;
      case SpriteMood.sleepy:
        for (final e in [left, right]) {
          c.drawLine(Offset(e.dx - er, e.dy), Offset(e.dx + er, e.dy), stroke);
        }
        break;
      case SpriteMood.thinking:
        _glossyEyes(c, left + Offset(0, -er * 0.55), right + Offset(0, -er * 0.55), er, fill);
        break;
      case SpriteMood.idle:
      case SpriteMood.speaking:
        if (_blinking) {
          for (final e in [left, right]) {
            c.drawLine(Offset(e.dx - er, e.dy), Offset(e.dx + er, e.dy), stroke);
          }
        } else {
          _glossyEyes(c, left, right, er, fill);
        }
        break;
    }

    _mouth(c, Offset(center.dx, center.dy + r * 0.34), r * 0.20);
    if (skin.blush) {
      for (final bx in [left.dx - dx * 0.55, right.dx + dx * 0.55]) {
        final p = Offset(bx, eyeY + r * 0.16);
        c.drawOval(
          Rect.fromCenter(center: p, width: r * 0.26, height: r * 0.15),
          Paint()
            ..shader = RadialGradient(colors: [
              const Color(0xFFFF8FA8).withAlpha(110),
              const Color(0xFFFF8FA8).withAlpha(0),
            ]).createShader(
                Rect.fromCenter(center: p, width: r * 0.26, height: r * 0.15)),
        );
      }
    }
  }

  /// 大眼 + 双高光点，做出"玻璃珠"质感。
  void _glossyEyes(Canvas c, Offset left, Offset right, double r, Paint fill) {
    for (final e in [left, right]) {
      c.drawCircle(e, r, fill);
      c.drawCircle(e + Offset(-r * 0.32, -r * 0.34), r * 0.36,
          Paint()..color = Colors.white.withAlpha(235));
      c.drawCircle(e + Offset(r * 0.28, r * 0.3), r * 0.16,
          Paint()..color = Colors.white.withAlpha(170));
    }
  }

  void _mouth(Canvas c, Offset center, double w) {
    final p = Paint()
      ..color = skin.mouth
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.28
      ..strokeCap = StrokeCap.round;
    switch (mood) {
      case SpriteMood.happy:
        p.style = PaintingStyle.fill;
        c.drawArc(Rect.fromCenter(center: center, width: w * 1.5, height: w * 1.3),
            0, math.pi, false, p);
        break;
      case SpriteMood.speaking:
        final open = 0.5 + 0.5 * math.sin(t * 9);
        p.style = PaintingStyle.fill;
        c.drawOval(
          Rect.fromCenter(
              center: center, width: w * 1.0, height: w * (0.3 + open * 0.9)),
          p,
        );
        break;
      case SpriteMood.dragging:
        final path = Path()..moveTo(center.dx - w, center.dy);
        for (var i = 0; i < 3; i++) {
          final x0 = center.dx - w + i * (w * 2 / 3);
          path.quadraticBezierTo(
              x0 + w / 3, center.dy + (i.isEven ? -w * 0.4 : w * 0.4),
              x0 + w * 2 / 3, center.dy);
        }
        c.drawPath(path, p);
        break;
      case SpriteMood.thinking:
        c.drawLine(Offset(center.dx - w * 0.5, center.dy),
            Offset(center.dx + w * 0.5, center.dy), p);
        break;
      case SpriteMood.sleepy:
        p.style = PaintingStyle.fill;
        c.drawOval(
          Rect.fromCenter(center: center, width: w * 0.8, height: w * 0.8), p);
        break;
      case SpriteMood.idle:
        c.drawArc(
          Rect.fromCenter(center: center, width: w * 1.6, height: w * 1.2),
          math.pi * 0.15, math.pi * 0.7, false, p);
        break;
    }
  }

  // ---------------- 光效配件 ----------------

  void _rimLight(Canvas c, Offset headC, double headR, double w, double h) {
    // 头部右下逆光边
    c.drawArc(
      Rect.fromCircle(center: headC, radius: headR * 0.98),
      math.pi * 0.05,
      math.pi * 0.72,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = headR * 0.11
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [skin.rim.withAlpha(0), skin.rim.withAlpha(200)],
        ).createShader(Rect.fromCircle(center: headC, radius: headR)),
    );
  }

  void _wings(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final cx = w / 2;
    final cy = h * 0.50;
    final flap = math.sin(t * 5.2) * 0.14;

    for (final side in [-1, 1]) {
      final count = skin.wingCount ~/ 2;
      for (var i = 0; i < count; i++) {
        // 上翅大、下翅小
        final upper = i == 0;
        final len = w * (upper ? 0.46 : 0.30);
        final wid = w * (upper ? 0.20 : 0.14);
        final angle = side * (upper ? 0.42 : 1.05) + flap * side;

        c.save();
        c.translate(cx + side * w * 0.10, cy + (upper ? -h * 0.04 : h * 0.09));
        c.rotate(angle);

        final path = Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(len * 0.45 * side, -wid, len, -wid * 0.12)
          ..quadraticBezierTo(len * 0.6, wid * 0.55, 0, wid * 0.30)
          ..close();

        c.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                skin.wingA.withAlpha(150),
                skin.wingB.withAlpha(110),
                skin.wingC.withAlpha(85),
              ],
            ).createShader(Rect.fromLTRB(0, -wid, len, wid)),
        );
        c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..color = Colors.white.withAlpha(dark ? 90 : 150),
        );
        // 翅脉
        final vein = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = Colors.white.withAlpha(dark ? 60 : 110);
        for (var v = 1; v <= 2; v++) {
          final t0 = v / 3;
          c.drawLine(
            Offset(len * 0.12, 0),
            Offset(len * (0.35 + t0 * 0.45), -wid * (0.5 - t0 * 0.3)),
            vein,
          );
        }
        c.restore();
      }
    }
  }

  void _halo(Canvas c, Offset headC, double r) {
    final center = Offset(headC.dx, headC.dy - r * 1.28);
    final rect = Rect.fromCenter(center: center, width: r * 1.15, height: r * 0.40);
    final pulse = 0.7 + 0.3 * math.sin(t * 1.8);
    c.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.22
        ..color = skin.core.withAlpha((60 * pulse).round()),
    );
    c.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.075
        ..color = Colors.white.withAlpha((220 * pulse).round()),
    );
  }

  void _antenna(Canvas c, Offset headC, double r) {
    final base = Offset(headC.dx - r * 0.35, headC.dy - r * 0.92);
    final tip = base + Offset(-r * 0.22, -r * 0.52);
    c.drawLine(
      base,
      tip,
      Paint()
        ..color = skin.shellShadow
        ..strokeWidth = r * 0.07
        ..strokeCap = StrokeCap.round,
    );
    final pulse = 0.6 + 0.4 * math.sin(t * 3.1);
    c.drawCircle(
      tip,
      r * 0.30,
      Paint()
        ..shader = RadialGradient(colors: [
          skin.core.withAlpha((150 * pulse).round()),
          skin.core.withAlpha(0),
        ]).createShader(Rect.fromCircle(center: tip, radius: r * 0.30)),
    );
    c.drawCircle(tip, r * 0.085, Paint()..color = Colors.white.withAlpha(230));
    _sparkle(c, tip, r * 0.30 * (0.7 + pulse * 0.5), Colors.white.withAlpha(190));
  }

  void _sparkle(Canvas c, Offset p, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 2; i++) {
      final a = i * math.pi / 2;
      c.drawLine(
        p - Offset(math.cos(a) * size, math.sin(a) * size),
        p + Offset(math.cos(a) * size, math.sin(a) * size),
        paint..strokeWidth = i == 0 ? size * 0.16 : size * 0.1,
      );
    }
  }

  void _starfield(Canvas c, Offset headC, double r) {
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: headC, radius: r * 0.98)));
    for (var i = 0; i < 7; i++) {
      final a = i * 2.399; // 黄金角分布，避免规则感
      final rad = r * (0.18 + (i % 4) * 0.18);
      final p = headC + Offset(math.cos(a) * rad, math.sin(a) * rad * 0.8 + r * 0.1);
      final tw = 0.4 + 0.6 * math.sin(t * (1.2 + i * 0.3) + i);
      c.drawCircle(p, r * 0.028 * (0.6 + tw * 0.8),
          Paint()..color = Colors.white.withAlpha((120 * tw).round()));
    }
    c.restore();
  }

  void _circuits(Canvas c, Offset headC, double r) {
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: headC, radius: r * 0.99)));
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.045
      ..color = const Color(0xFFE0B84C).withAlpha(dark ? 170 : 130);
    final ox = headC.dx + r * 0.30, oy = headC.dy - r * 0.55;
    c.drawLine(Offset(ox, oy), Offset(ox + r * 0.35, oy + r * 0.1), p);
    c.drawLine(Offset(ox + r * 0.35, oy + r * 0.1), Offset(ox + r * 0.35, oy + r * 0.45), p);
    c.drawLine(Offset(ox, oy + r * 0.22), Offset(ox + r * 0.18, oy + r * 0.22), p);
    c.drawCircle(Offset(ox + r * 0.35, oy + r * 0.45), r * 0.05,
        Paint()..color = const Color(0xFFE0B84C).withAlpha(dark ? 190 : 150));
    c.restore();
  }

  void _cue(Canvas c, Size s) {
    if (mood == SpriteMood.thinking) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = skin.core;
      final center = Offset(s.width * 0.82, s.height * 0.12);
      c.drawArc(
        Rect.fromCircle(center: center, radius: s.width * 0.075),
        (t * 3.2) % (math.pi * 2),
        math.pi * 1.25,
        false,
        p,
      );
    } else if (mood == SpriteMood.sleepy) {
      for (var i = 0; i < 2; i++) {
        final k = ((t * 0.45 + i * 0.5) % 1.0);
        final tp = TextPainter(
          text: TextSpan(
            text: 'z',
            style: TextStyle(
              fontSize: s.width * (0.11 + k * 0.07),
              fontWeight: FontWeight.w800,
              color: skin.core.withAlpha((190 * (1 - k)).round()),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset(s.width * 0.78 + k * s.width * 0.08,
            s.height * (0.26 - k * 0.18)));
      }
    } else if (mood == SpriteMood.happy) {
      _sparkle(c, Offset(s.width * 0.16, s.height * 0.22), s.width * 0.07,
          skin.core.withAlpha(200));
      _sparkle(c, Offset(s.width * 0.86, s.height * 0.34), s.width * 0.055,
          skin.rim.withAlpha(190));
    }
  }

  bool get _blinking {
    final cycle = t % 3.6;
    return cycle > 3.47;
  }

  @override
  bool shouldRepaint(covariant SpritePainter old) =>
      old.skin != skin || old.mood != mood || old.dark != dark;
}
