import 'package:flutter/material.dart';

/// 时间轴外壳：左侧画一个圆点 + 竖向连线，右侧放内容（如 TripCard）。
class TimelineRow extends StatelessWidget {
  final Widget child;
  final bool isFirst;
  final bool isLast;
  final Color dotColor;

  const TimelineRow({
    super.key,
    required this.child,
    required this.isFirst,
    required this.isLast,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    const railWidth = 28.0;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 上段线
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: railWidth / 2 - 1,
                  child: Container(
                    width: 2,
                    color: isFirst ? Colors.transparent : dotColor.withAlpha(60),
                  ),
                ),
                // 圆点
                Positioned(
                  top: 24,
                  left: railWidth / 2 - 7,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.surface, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
