import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../poster_data.dart';

/// 模板共用的照片位：有图显示图，无图/图失效时退回渐变 + 图标，
/// 保证任何模板在零照片旅程下也不会出现空洞。
class PhotoSlot extends StatelessWidget {
  const PhotoSlot({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.iconSize = 34,
    this.overlay,
  });

  final String? path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final double iconSize;

  /// 叠在照片上的内容（如文字、粒子层）。
  final Widget? overlay;

  bool get hasPhoto => (path ?? '').isNotEmpty && File(path!).existsSync();

  @override
  Widget build(BuildContext context) {
    Widget base;
    if (!hasPhoto) {
      base = Container(
        width: width,
        height: height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: TripPosterData.fallbackColors,
          ),
        ),
        child: Center(
          child: Icon(Icons.landscape_outlined,
              size: iconSize, color: Colors.white.withAlpha(120)),
        ),
      );
    } else {
      // width 是 final 字段，Dart 不对它做流分析收窄，所以用 ??/max 一次性求值
      final decodeWidth =
          math.max(math.max(width ?? 0, height ?? 0), 550.0);
      base = Image.file(
        File(path!),
        width: width,
        height: height,
        fit: fit,
        // 【关键性能项】不给 cacheWidth 时 Flutter 会按原图全分辨率解码。
        // 手机照片普遍 3000-4000px，海报里几张一起解就会卡住主线程；
        // 按目标显示宽度的 2 倍解码，视觉上无损但内存与耗时低一个量级。
        cacheWidth: (decodeWidth * 2).round(),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: TripPosterData.fallbackColors),
          ),
        ),
      );
    }

    if (overlay != null) {
      base = Stack(
        fit: StackFit.expand,
        children: [base, overlay!],
      );
    }

    if (radius > 0) {
      base = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: base,
      );
    }
    return base;
  }
}

/// 深色底部压暗渐变，保证压在照片上的文字可读。
class BottomScrim extends StatelessWidget {
  const BottomScrim({super.key, this.height = 130, this.maxAlpha = 175});

  final double height;
  final int maxAlpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withAlpha(0), Colors.black.withAlpha(maxAlpha)],
        ),
      ),
    );
  }
}

/// 海报上的花费行（各模板复用）。未记账时不占位。
class PosterCostLine extends StatelessWidget {
  const PosterCostLine({
    super.key,
    required this.data,
    required this.color,
    this.alignEnd = false,
  });

  final TripPosterData data;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final line = data.costLine;
    if (line == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5, color: color, fontWeight: FontWeight.w600, letterSpacing: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 红色竖排印章（多模板复用）。
class SealStamp extends StatelessWidget {
  const SealStamp({
    super.key,
    required this.text,
    this.size = 12,
    this.angle = -0.10,
  });

  final String text;
  final double size;
  final double angle;

  static List<String> charsFrom(String dest, {int take = 2}) {
    final clean = dest.trim();
    if (clean.isEmpty) return ['旅', '行'];
    final chars = clean.split('').where((c) => c.trim().isNotEmpty).toList();
    if (chars.length >= take) return chars.take(take).toList();
    return [...chars, '印'];
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xCCE03A2C),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withAlpha(150), width: 1.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in charsFrom(text))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  c,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
