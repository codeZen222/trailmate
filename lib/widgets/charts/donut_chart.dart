import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 环形图的一段。
class DonutSlice {
  const DonutSlice({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;
}

/// 手绘环形占比图：零依赖，样式完全可控。
/// 项目此前吃过图表库与 drift/Kotlin 版本冲突的亏，故不自绘之外的方案。
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.size = 132,
    this.thickness = 22,
    this.centerTitle,
    this.centerValue,
  });

  final List<DonutSlice> slices;
  final double size;
  final double thickness;
  final String? centerTitle;
  final String? centerValue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(
          slices: slices,
          thickness: thickness,
          background: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (centerValue != null)
                Text(
                  centerValue!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: size * 0.15,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              if (centerTitle != null)
                Text(
                  centerTitle!,
                  style: TextStyle(
                    fontSize: size * 0.085,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.thickness,
    required this.background,
  });

  final List<DonutSlice> slices;
  final double thickness;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - thickness / 2 - 1;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 底环：无数据时也画出来，避免空白
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..color = background;
    canvas.drawCircle(center, radius, base);

    final total = slices.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;

    var start = -math.pi / 2; // 12 点方向起
    for (final s in slices) {
      final sweep = (s.value / total) * math.pi * 2;
      paint.color = s.color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.background != background;
}
