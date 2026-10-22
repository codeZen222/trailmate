import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../poster_data.dart';
import 'poster_primitives.dart';

/// 模板四：登机牌——深色航头 + 字段网格 + 虚线撕口 + 票根条码。
class BoardingTemplate extends StatelessWidget {
  const BoardingTemplate({super.key, required this.data, this.width = 340});

  final TripPosterData data;
  final double width;

  static const _navy = Color(0xFF16294A);
  static const _navySoft = Color(0xFF2C5296);
  static const _paper = Color(0xFFFFFFFF);
  static const _ink = Color(0xFF1B2A3E);
  static const _grey = Color(0xFF8A97A8);
  static const _accent = Color(0xFFE0862C);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(18),
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
          _header(),
          _fields(),
          _perforation(),
          _stub(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _navySoft],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flight_takeoff, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              const Text('BOARDING PASS',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const Spacer(),
              Text('登机牌',
                  style: TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white.withAlpha(170))),
            ],
          ),
          const SizedBox(height: 16),
          // 出发 → 到达
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FROM',
                        style: TextStyle(
                            fontSize: 8, letterSpacing: 1.6, color: Colors.white.withAlpha(150))),
                    const SizedBox(height: 2),
                    Text(
                      (data.cities.isNotEmpty ? data.cities.first : 'HOME')
                          .toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Icon(Icons.airline_stops, size: 22, color: _accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('TO',
                        style: TextStyle(
                            fontSize: 8, letterSpacing: 1.6, color: Colors.white.withAlpha(150))),
                    const SizedBox(height: 2),
                    Text(
                      data.destination.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(data.displayCaption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10, letterSpacing: 1.4, color: Colors.white.withAlpha(180))),
        ],
      ),
    );
  }

  Widget _fields() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Column(
        children: [
          Row(
            children: [
              _field('日期 DATE', data.dateRange),
              _field('时长 DUR', '${data.days} 天'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _field('城市 CITY', '${data.cities.length} 座'),
              _field('记录 LOG', '${data.logCount} 篇'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _field('影像 FILM', '${data.photoCount} 张'),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('评分 RATING',
                        style: TextStyle(fontSize: 8, letterSpacing: 1.4, color: _grey)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        for (var i = 0; i < 5; i++)
                          Icon(
                            data.rating != null && i < data.rating!
                                ? Icons.star
                                : Icons.star_border,
                            size: 14,
                            color: _accent,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 8, letterSpacing: 1.4, color: _grey)),
            const SizedBox(height: 4),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
          ],
        ),
      );

  /// 虚线撕口 + 两侧半圆缺口。
  Widget _perforation() {
    return SizedBox(
      height: 18,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: _notch(true),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: _notch(false),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _DashedPainter(_grey.withAlpha(120))),
          ),
        ],
      ),
    );
  }

  /// 撕口两侧的冲孔（浅灰圆，视觉上像被打了孔）。
  Widget _notch(bool left) {
    return Container(
      width: 18,
      height: 18,
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        width: 15,
        height: 15,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFEDEEF0),
        ),
      ),
    );
  }

  Widget _stub() {
    return Container(
      color: const Color(0xFFF7F8FA),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.tagNames.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final t in data.tagNames.take(3))
                          Text('#$t',
                              style: const TextStyle(
                                  fontSize: 9.5, color: _navy, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                PosterCostLine(
                    data: data, color: const Color(0xFF2C5296)),
                const Text('TrailMate',
                    style: TextStyle(
                        fontSize: 8.5, letterSpacing: 2.4, color: _grey)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          BarcodeStrip(seedText: data.destination, height: 40),
        ],
      ),
    );
  }
}

/// 确定性条码（同一旅程每次一致）。
class BarcodeStrip extends StatelessWidget {
  const BarcodeStrip({super.key, required this.seedText, this.height = 40});

  final String seedText;
  final double height;

  @override
  Widget build(BuildContext context) {
    final rnd = math.Random(seedText.hashCode);
    return SizedBox(
      width: 96,
      height: height,
      child: CustomPaint(painter: _BarcodePainter(rnd)),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.rnd);

  final math.Random rnd;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF1B2A3E);
    var x = 0.0;
    while (x < size.width) {
      final w = 1.0 + rnd.nextDouble() * 2.6;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), p);
      x += w + 1.0 + rnd.nextDouble() * 2.4;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter old) => true;
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const dash = 5.0;
    const gap = 4.0;
    final y = size.height / 2;
    for (var x = 18.0; x < size.width - 18; x += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, size.width - 18), y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter old) => old.color != color;
}
