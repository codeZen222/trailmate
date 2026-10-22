import 'package:flutter/material.dart';
import '../../mood/mood_effect_layer.dart';
import '../poster_data.dart';
import 'poster_primitives.dart';

/// 底部波浪（撕纸）裁剪。
class WaveClipper extends CustomClipper<Path> {
  const WaveClipper({this.waveHeight = 16, this.waves = 5});

  final double waveHeight;
  final int waves;

  double get baseline => 1.0 - waveHeight / 200;

  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * baseline);

    final seg = size.width / waves;
    final y = size.height * baseline;
    for (var i = waves - 1; i >= 0; i--) {
      final x1 = i * seg;
      final mid = ((i + 1) * seg + x1) / 2;
      final ctrl = i.isEven
          ? Offset(mid, y - waveHeight)
          : Offset(mid, y + waveHeight * 0.55);
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, x1, y);
    }
    path.lineTo(0, size.height * baseline);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant WaveClipper old) =>
      old.waveHeight != waveHeight || old.waves != waves;
}

/// 模板一：撕纸海报——大图 + 波浪撕纸边 + 大字地名 + 红印章。
class WaveTemplate extends StatelessWidget {
  const WaveTemplate({super.key, required this.data, this.width = 340});

  final TripPosterData data;
  final double width;

  static const double _photoHeight = 250;

  @override
  Widget build(BuildContext context) {
    const clipper = WaveClipper();

    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFFFBF9F5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(55),
              blurRadius: 22,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _photoHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 撕纸投影
                Positioned.fill(
                  child: Transform.translate(
                    offset: const Offset(0, 5),
                    child: ClipPath(
                      clipper: clipper,
                      child: Container(color: Colors.black.withAlpha(45)),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ClipPath(
                    clipper: clipper,
                    child: PhotoSlot(
                      path: data.mainPhoto,
                      iconSize: 52,
                      overlay: data.mood == null
                          ? null
                          : MoodEffectLayer(
                              mood: data.mood,
                              seed: data.destination.hashCode & 0x3fff,
                              // 海报是"看一眼就截走"的静态图，不需要常驻动画。
                              // 持续 30fps 重绘正是切特效卡顿的主因之一。
                              animate: false),
                    ),
                  ),
                ),
                Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _topScrim()),
                Positioned(
                    left: 0, right: 0, bottom: 26, child: _titleBlock()),
                Positioned(right: 18, bottom: 54, child: _seal()),
              ],
            ),
          ),
          _body(),
        ],
      ),
    );
  }

  Widget _topScrim() {
    return Container(
      height: 92,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withAlpha(120), Colors.black.withAlpha(0)],
        ),
      ),
      child: Text(
        data.displayCaption,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withAlpha(235),
          fontSize: 11.5,
          letterSpacing: 2.2,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _titleBlock() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFDDEBE3)],
            ).createShader(rect),
            child: Text(
              data.destination,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: 1,
                color: Colors.white,
                shadows: [
                  Shadow(
                      blurRadius: 14,
                      color: Colors.black.withAlpha(140),
                      offset: const Offset(0, 3)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${data.dateRange}  ·  ${data.days} DAYS',
            style: TextStyle(
              color: Colors.white.withAlpha(225),
              fontSize: 10.5,
              letterSpacing: 1.6,
              shadows: [Shadow(blurRadius: 8, color: Colors.black.withAlpha(150))],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seal() => SealStamp(text: data.destination);

  Widget _body() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.notesExcerpt.isNotEmpty) ...[
            Text(
              '「${data.notesExcerpt}」',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Color(0xFF4A5A52),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _thumbStrip(),
          _statsBand(),
          const SizedBox(height: 8),
          PosterCostLine(data: data, color: const Color(0xFF3E6B5A)),
          const SizedBox(height: 12),
          if (data.tagNames.isNotEmpty || data.rating != null)
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final t in data.tagNames.take(4))
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3E6B5A).withAlpha(26),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('#$t',
                              style: const TextStyle(
                                  fontSize: 9.5, color: Color(0xFF3E6B5A))),
                        ),
                    ],
                  ),
                ),
                if (data.rating != null) _stars(),
              ],
            ),
          const SizedBox(height: 12),
          const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: Divider(color: Color(0xFFC9C4B8), thickness: 1)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('TrailMate',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 2.4,
                          color: Color(0xFF9A958A))),
                ),
                Expanded(child: Divider(color: Color(0xFFC9C4B8), thickness: 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbStrip() {
    final extras = data.extraPhotos();
    if (extras.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          for (final p in extras)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PhotoSlot(path: p, width: 44, height: 44, radius: 6, iconSize: 16),
            ),
          const Spacer(),
          if (data.photoCount > extras.length + 1)
            Text('+${data.photoCount - extras.length - 1} 张',
                style: const TextStyle(fontSize: 10, color: Color(0xFF8A9A92))),
        ],
      ),
    );
  }

  Widget _statsBand() {
    Widget cell(String v, String l) => Expanded(
          child: Column(
            children: [
              Text(v,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2F4A3E))),
              const SizedBox(height: 1),
              Text(l, style: const TextStyle(fontSize: 9.5, color: Color(0xFF8A9A92))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EFEA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          cell('${data.days}', '天'),
          _sep(),
          cell('${data.cities.length}', '城'),
          _sep(),
          cell('${data.logCount}', '篇'),
          _sep(),
          cell('${data.photoCount}', '张'),
        ],
      ),
    );
  }

  Widget _sep() => Container(width: 1, height: 20, color: const Color(0xFFD8D4C9));

  Widget _stars() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < data.rating! ? Icons.star : Icons.star_border,
            size: 13,
            color: const Color(0xFFD9A05B),
          ),
      ],
    );
  }
}
