import 'dart:io';

import 'package:flutter/material.dart';
import '../../models/mood_type.dart';
import '../mood/mood_effect_layer.dart';

/// 单篇日志的分享卡片数据。
class LogCardData {
  const LogCardData({
    required this.title,
    required this.content,
    required this.date,
    required this.destination,
    required this.weather,
    required this.mood,
    required this.photos,
    required this.placeName,
    required this.tripName,
  });

  final String title;
  final String content;
  final DateTime date;
  final String destination;
  final String? weather;
  final MoodType? mood;

  /// 最多取前 4 张参与排版，避免卡片过长。
  final List<String> photos;
  final String? placeName;
  final String tripName;

  bool get hasPhoto => photos.isNotEmpty && File(photos.first).existsSync();
}

/// 日志分享卡片：一张竖版小海报，突出正文与当日心情。
///
/// 【为什么不复用旅程海报】旅程海报讲的是"一趟行程"（天数、城市、花费），
/// 而单篇日志的核心是那段文字本身 —— 硬套会把正文挤成一行省略号。
class LogShareCard extends StatelessWidget {
  const LogShareCard({super.key, required this.data, this.width = 340});

  final LogCardData data;
  final double width;

  static const Color _ink = Color(0xFF22303A);
  static const Color _inkSoft = Color(0xFF6C7F8B);

  @override
  Widget build(BuildContext context) {
    final accent = data.mood?.accent ?? const Color(0xFF4A7FB5);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(28),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metaRow(),
                if (data.title.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(data.title.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          height: 1.25)),
                ],
                const SizedBox(height: 10),
                _body(),
                const SizedBox(height: 14),
                _footer(accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部主图：有照片用照片 + 心情特效；没照片用同色系渐变兜底。
  Widget _hero(Color accent) {
    const h = 190.0;
    if (!data.hasPhoto) {
      return Container(
        height: h,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withAlpha(225), accent.withAlpha(140)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: MoodEffectLayer(
                  mood: data.mood,
                  seed: data.destination.hashCode & 0x3fff,
                  animate: false),
            ),
            Center(
              child: Icon(Icons.landscape_outlined,
                  size: 44, color: Colors.white.withAlpha(150)),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(data.photos.first),
              fit: BoxFit.cover,
              cacheWidth: (width * 2).round(),
              errorBuilder: (_, __, ___) => Container(color: accent)),
          if (data.mood != null)
            MoodEffectLayer(
                mood: data.mood,
                seed: data.destination.hashCode & 0x3fff,
                animate: false),
          // 底部压暗，保证叠在图上的日期可读
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x99000000), Color(0x00000000)],
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 12,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    data.destination.isEmpty ? '旅行手记' : data.destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 1),
                  ),
                ),
                if (data.mood != null)
                  Text(data.mood!.emoji, style: const TextStyle(fontSize: 17)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow() {
    final parts = <String>[
      '${data.date.year}.${data.date.month.toString().padLeft(2, '0')}.${data.date.day.toString().padLeft(2, '0')}',
      if ((data.weather ?? '').isNotEmpty) data.weather!,
      if ((data.placeName ?? '').isNotEmpty) data.placeName!,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final p in parts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(p,
                style: const TextStyle(
                    fontSize: 10.5, color: _inkSoft, letterSpacing: .3)),
          ),
      ],
    );
  }

  /// 正文：按字数自适应行数，太长就截断并加省略提示。
  Widget _body() {
    var text = data.content.trim();
    if (text.isEmpty) text = '（这篇没有写文字，只有照片）';
    const limit = 260;
    var truncated = false;
    if (text.length > limit) {
      text = text.substring(0, limit);
      truncated = true;
    }
    return Text(
      truncated ? '$text…' : text,
      maxLines: truncated ? 9 : 8,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.justify,
      style: const TextStyle(
          fontSize: 13, height: 1.75, color: _ink, letterSpacing: .2),
    );
  }

  Widget _footer(Color accent) {
    return Row(
      children: [
        // 剩余照片以"+N"提示，暗示还有更多
        if (data.photos.length > 1) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withAlpha(28),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('+${data.photos.length - 1} 图',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accent.withAlpha(220))),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            data.tripName.isEmpty ? '' : '来自「${data.tripName}」',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: _inkSoft),
          ),
        ),
        CustomPaint(size: const Size(54, 14), painter: _DotsPainter(accent)),
      ],
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withAlpha(150);
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
          Offset(size.width - i * 13, size.height / 2), 2.2, p);
    }
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width - 52, size.height / 2),
      Paint()
        ..color = color.withAlpha(70)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.color != color;
}
