import 'package:flutter/material.dart';
import '../../mood/mood_effect_layer.dart';
import '../poster_data.dart';
import 'poster_primitives.dart';

/// 模板三：拍立得——相纸底 + 微倾斜的立得相 + 胶带 + 手写字感说明。
class PolaroidTemplate extends StatelessWidget {
  const PolaroidTemplate({super.key, required this.data, this.width = 340});

  final TripPosterData data;
  final double width;

  static const _desk = Color(0xFFEFE9DF);
  static const _ink = Color(0xFF3A342C);
  static const _soft = Color(0xFF8A8073);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _desk,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(50),
              blurRadius: 22,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          // 背景斜纹，避免纯色太平
          Positioned.fill(
            child: CustomPaint(painter: _DiagonalPainter(_ink.withAlpha(9))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.displayCaption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      color: _soft,
                      height: 1.5),
                ),
                const SizedBox(height: 16),
                _polaroid(),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _dot('${data.days} 天'),
                    _sep(),
                    _dot('${data.cities.length} 城'),
                    _sep(),
                    _dot('${data.logCount} 篇'),
                    _sep(),
                    _dot('${data.photoCount} 张'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(data.dateRange,
                    style: const TextStyle(fontSize: 10, color: _soft, letterSpacing: 1)),
                PosterCostLine(data: data, color: const Color(0xFF6B5F4F)),
                const SizedBox(height: 12),
                if (data.tagNames.isNotEmpty)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in data.tagNames.take(4))
                        Text('#$t',
                            style: const TextStyle(
                                fontSize: 10, color: _ink, fontWeight: FontWeight.w600)),
                    ],
                  ),
                const SizedBox(height: 10),
                const Text('TrailMate',
                    style: TextStyle(
                        fontSize: 8.5, letterSpacing: 2.6, color: Color(0xFFB0A697))),
              ],
            ),
          ),
          // 印章压在相纸右上角
          const Positioned(top: 18, right: 18, child: SizedBox.shrink()),
        ],
      ),
    );
  }

  /// 立得相：白框 + 方形照片 + 底部手写区。
  Widget _polaroid() {
    return Transform.rotate(
      angle: -0.045,
      child: Stack(
        alignment: AlignmentDirectional.topCenter,
        children: [
          Container(
            width: 236,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withAlpha(60),
                    blurRadius: 16,
                    offset: const Offset(2, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhotoSlot(
                  path: data.mainPhoto,
                  width: 212,
                  height: 212,
                  iconSize: 44,
                  overlay: data.mood == null ? null : _mood(),
                ),
                SizedBox(
                  height: 52,
                  child: Center(
                    child: Text(
                      data.destination,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                          color: _ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 两条胶带
          const Positioned(top: -10, left: 14, child: _Tape(angle: -0.5)),
          const Positioned(top: -6, right: 16, child: _Tape(angle: 0.42)),
        ],
      ),
    );
  }

  Widget _mood() => MoodEffectLayer(
      mood: data.mood,
      seed: data.destination.hashCode & 0x3fff,
      // 海报静态呈现，不起常驻动画（持续重绘是切特效卡顿的主因之一）
      animate: false);

  Widget _dot(String t) => Text(t,
      style: const TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w600, color: _ink, letterSpacing: 0.5));

  Widget _sep() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Text('·', style: TextStyle(fontSize: 14, color: _soft)),
      );
}

/// 半透明胶带条。
class _Tape extends StatelessWidget {
  const _Tape({required this.angle});

  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: 62,
        height: 20,
        color: const Color(0x59E8D9A6),
        child: const Divider(height: 1),
      ),
    );
  }
}

/// 细斜纹背景。
class _DiagonalPainter extends CustomPainter {
  const _DiagonalPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalPainter old) => old.color != color;
}
