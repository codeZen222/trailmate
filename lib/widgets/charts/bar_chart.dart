import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 柱状图的一根柱子。
class BarItem {
  const BarItem({required this.label, required this.value, this.color});

  final String label;
  final double value;
  final Color? color;
}

/// 手绘柱状图（月度趋势用）。零依赖、支持高亮某一根。
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.items,
    this.height = 148,
    this.barColor,
    this.highlightIndex,
    this.valueFormatter,
  });

  final List<BarItem> items;
  final double height;
  final Color? barColor;
  final int? highlightIndex;
  final String Function(double value)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = barColor ?? cs.primary;
    final maxV = items.fold<double>(0, (m, e) => math.max(m, e.value));

    return SizedBox(
      height: height,
      child: maxV <= 0
          ? Center(
              child: Text('暂无数据',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _bar(
                      context,
                      items[i],
                      items[i].value / maxV,
                      i == highlightIndex,
                      color,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _bar(
      BuildContext context, BarItem item, double ratio, bool active, Color color) {
    final cs = Theme.of(context).colorScheme;
    // 给极小值留一点可见高度，否则 0 附近的柱子完全看不见
    final h = (56 * math.max(ratio, item.value > 0 ? 0.06 : 0)).clamp(0.0, 56.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          valueFormatter?.call(item.value) ?? item.value.toStringAsFixed(0),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            color: active ? cs.onSurface : cs.outline,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          height: h + 4,
          margin: EdgeInsets.symmetric(horizontal: (MediaQuery.of(context).size.width * 0.012).clamp(2, 8)),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: active
                  ? [color, color.withAlpha(190)]
                  : [color.withAlpha(120), color.withAlpha(60)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            color: active ? cs.onSurface : cs.outline,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// 横向条形排行（旅程花费对比用）。
class RankBars extends StatelessWidget {
  const RankBars({
    super.key,
    required this.items,
    this.barColor,
    this.valueFormatter,
  });

  final List<BarItem> items;
  final Color? barColor;
  final String Function(double value)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = barColor ?? cs.primary;
    final maxV = items.fold<double>(0, (m, e) => math.max(m, e.value));

    return Column(
      children: [
        for (final e in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Text(
                      valueFormatter?.call(e.value) ?? e.value.toStringAsFixed(0),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (ctx, c) => Stack(
                    children: [
                      Container(
                        height: 7,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: maxV <= 0 ? 0 : (e.value / maxV).clamp(0.02, 1.0),
                        child: Container(
                          height: 7,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                (e.color ?? color).withAlpha(200),
                                (e.color ?? color),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
