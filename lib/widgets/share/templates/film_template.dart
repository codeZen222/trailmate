import 'package:flutter/material.dart';
import '../poster_data.dart';
import 'poster_primitives.dart';

/// 模板五：胶片条——深色底 + 齿孔边 + 三格画面 + 叠印地名。
class FilmTemplate extends StatelessWidget {
  const FilmTemplate({super.key, required this.data, this.width = 340});

  final TripPosterData data;
  final double width;

  static const _film = Color(0xFF16161A);
  static const _hole = Color(0xFFE8E4DA);
  static const _amber = Color(0xFFE0A050);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _film,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Text('TRAILMATE FILM',
                    style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 2.6,
                        color: _hole.withAlpha(170))),
                const Spacer(),
                Text('ISO 400', style: TextStyle(fontSize: 9, color: _amber.withAlpha(220))),
              ],
            ),
          ),
          _strip(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.destination,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800, color: _hole, letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                Text(data.displayCaption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, letterSpacing: 1.4, color: _hole.withAlpha(150))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _meta('${data.days}天'),
                    _meta('${data.cities.length}城'),
                    _meta('${data.logCount}篇'),
                    _meta('${data.photoCount}张'),
                    const Spacer(),
                    Text(data.dateRange,
                        style: TextStyle(
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                            color: _hole.withAlpha(140))),
                  ],
                ),
                PosterCostLine(data: data, color: _amber.withAlpha(230)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 胶片主体：两侧齿孔 + 三格画面。
  /// 必须显式给高度：卡片整体处在 SingleChildScrollView 里，
  /// 高度无界时 Stack(fit: StackFit.expand) 会塌成 0，导致整条胶片"空白"。
  Widget _strip() {
    const frameH = 150.0;
    final photos = <String?>[
      data.mainPhoto,
      ...data.extraPhotos(max: 6),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: frameH + 16,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const _Sprockets(),
          Expanded(
            child: SizedBox(
              height: frameH,
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PhotoSlot(
                            path: i < photos.length ? photos[i] : null,
                            iconSize: 22,
                          ),
                          if (i == 0)
                            Positioned(
                              left: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _amber.withAlpha(220),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text('${data.days} DAYS',
                                    style: const TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black87,
                                        letterSpacing: 1)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (i < 2) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          const _Sprockets(),
        ],
      ),
    );
  }

  Widget _meta(String t) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Text(t, style: TextStyle(fontSize: 11, color: _hole.withAlpha(210))),
      );
}

/// 胶片齿孔边。
class _Sprockets extends StatelessWidget {
  const _Sprockets();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          7,
          (_) => Container(
            width: 9,
            height: 6,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: FilmTemplate._hole.withAlpha(215),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ),
      ),
    );
  }
}
