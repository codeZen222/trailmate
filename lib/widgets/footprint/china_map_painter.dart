import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/province_shape.dart';

/// 经纬度 -> 屏幕坐标的等距圆柱投影（带缩放/平移视口）。
///
/// 【为什么不用墨卡托】中国跨纬度大（18°N~54°N），墨卡托会把北方严重拉伸，
/// 新疆看起来比实际大得多。足迹看板要的是"形状正确"，等距圆柱更贴近直觉。
///
/// 【为什么之前显得又小又扁】旧实现把 bounds 取到曾母暗沙（south=2.5°N），
/// geoH 被撑到 52.5°，而 geoW 只有 64°；竖屏可用区是窄高的，
/// min(innerW/geoW, innerH/geoH) 必然取横向限制 → 地图按宽铺满后垂直留大片空白，
/// 中国就缩成中间一条。修法：主体只框陆域（南海改成右下角附图），
/// 再叠加用户缩放，让地图真正放大填满可视高度。
class MapProjection {
  /// [baseBounds] 是中国陆域主体范围；[viewBounds] 是当前缩放视口（默认等于 base）。
  MapProjection({
    required this.bounds,
    required this.size,
    this.padding = 8,
    this.scale = 1.0,
    this.originShift = Offset.zero,
    Offset? anchorScreen,
  }) {
    final innerW = math.max(1, size.width - padding * 2);
    final innerH = math.max(1, size.height - padding * 2);

    final geoW = bounds.east - bounds.west;
    final geoH = bounds.north - bounds.south;

    // 等比贴合可用区。竖屏下宽度是约束边，按宽贴合后垂直方向自然留白给信息区。
    _pxPerDeg = math.min(innerW / geoW, innerH / geoH) * scale;
    drawnW = geoW * _pxPerDeg;
    drawnH = geoH * _pxPerDeg;

    // 定位只有一套逻辑：中国几何中心对齐到 anchorScreen。
    // 默认取"水平居中 + 垂直位于可用区的 38%"，这个比例是按内框算的，
    // 不再用整块屏幕高度做系数（之前那样会在有 AppBar/状态栏时被推到底部）。
    final a = anchorScreen ??
        Offset(padding + innerW / 2, padding + innerH * 0.38);
    offsetX = a.dx - (geoW / 2) * _pxPerDeg;
    offsetY = a.dy - (geoH / 2) * _pxPerDeg;
  }

  final LatLngBounds bounds;
  final Size size;
  final double padding;
  final double scale;

  /// 额外整体平移（附图投影用它挪到画布角落）。
  final Offset originShift;

  late final double _pxPerDeg;
  late final double offsetX;
  late final double offsetY;

  /// 当前视口下主体绘制出来的尺寸（像素）。
  late double drawnW;
  late double drawnH;

  double get pxPerDeg => _pxPerDeg;

  /// 投影锚点：中国几何中心在屏幕上的落点（缩放围绕它进行）。
  ///
  /// 【为什么暴露它】手势缩放要保持"焦点下的地点不动"，必须由
  /// pan = 焦点 - anchor - (起始焦点 - anchor - panStart) * grow
  /// 反推平移量，这个 anchor 就是公式里的基准点，与 scale 无关。
  Offset get anchor => Offset(
        offsetX + (bounds.east - bounds.west) / 2 * _pxPerDeg,
        offsetY + (bounds.north - bounds.south) / 2 * _pxPerDeg,
      );

  Offset project(double lat, double lon) => Offset(
        offsetX + (lon - bounds.west) * _pxPerDeg + originShift.dx,
        offsetY + (bounds.north - lat) * _pxPerDeg + originShift.dy,
      );

  /// 反查：屏幕点 -> 经纬度（用于命中测试）。
  (double lat, double lon) unproject(Offset p) {
    final lon = bounds.west + (p.dx - offsetX) / _pxPerDeg;
    final lat = bounds.north - (p.dy - offsetY) / _pxPerDeg;
    return (lat, lon);
  }
}

class LatLngBounds {
  const LatLngBounds(this.south, this.west, this.north, this.east);

  final double south;
  final double west;
  final double north;
  final double east;

  static LatLngBounds of(List<LatLngBounds> parts) {
    double s = 90, w = 180, n = -90, e = -180;
    for (final p in parts) {
      s = math.min(s, p.south);
      w = math.min(w, p.west);
      n = math.max(n, p.north);
      e = math.max(e, p.east);
    }
    return LatLngBounds(s, w, n, e);
  }

  double get width => east - west;
  double get height => north - south;
  double get centerLat => (north + south) / 2;
  double get centerLon => (east + west) / 2;
}

/// 中国全图绘制器：省界填色 + 城市亮点 + 时间轨迹 + 飞机。
///
/// 【彻底不依赖任何地图服务】所有几何来自 assets/geo/china_provinces.json，
/// 境外什么都不画 —— 天然满足"只保留中国区域"。
class ChinaMapPainter extends CustomPainter {
  ChinaMapPainter({
    required this.projection,
    required this.stats,
    required this.cityDots,
    this.trackPoints = const [],
    this.planeAt,
    this.selectedProvince,
    required this.dark,
    this.showTrack = true,
    this.labelViews = const [],
    this.labelAvoid = const [],
    this.southSeaLines = const [],
    this.southSeaInsetRect,
  });

  final MapProjection projection;
  final List<ProvinceStatView> stats;

  /// 城市亮点（已投影到屏幕坐标）。
  final List<CityDotView> cityDots;

  /// 时间轨迹（屏幕坐标）。
  final List<Offset> trackPoints;

  /// 飞机位置（屏幕坐标），null 表示不画。
  final Offset? planeAt;

  final String? selectedProvince;
  final bool dark;
  final bool showTrack;

  /// 需要标注省名的省份视图（通常等于 stats，只画点亮的）。
  final List<ProvinceStatView> labelViews;

  /// 城市标签占位矩形，省名避让它们以免叠成重影。
  final List<Rect> labelAvoid;

  /// 九段线（附图投影坐标系下的点集），画在 [southSeaInsetRect] 内。
  final List<List<Offset>> southSeaLines;
  final Rect? southSeaInsetRect;

  @override
  void paint(Canvas canvas, Size size) {
    _paintOcean(canvas, size);
    for (final s in stats) {
      _paintProvince(canvas, s);
    }
    if (showTrack && trackPoints.length >= 2) _paintTrack(canvas);
    _paintCities(canvas);
    _paintProvinceLabels(canvas);
    _paintSouthSeaInset(canvas);
    if (planeAt != null) _paintPlane(canvas, planeAt!);
  }

  /// 右下角"南海诸岛附图"：框 + 九段线。主图收紧到陆域后，
  /// 这块保证九段线与南海岛礁仍然完整呈现（中国地图的合规必需项）。
  void _paintSouthSeaInset(Canvas canvas) {
    final rect = southSeaInsetRect;
    if (rect == null || southSeaLines.isEmpty) return;

    // 必须裁剪：附图投影按 inset 范围算比例，但九段线个别点会略微越界，
    // 不裁就会像之前那样把红点画到框外的主图海面上。
    canvas.save();
    final clip = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)));
    canvas.clipPath(clip);

    final bg = Paint()
      ..color = dark
          ? const Color(0xFF0E1A2B).withAlpha(200)
          : const Color(0xFFF4F8FB).withAlpha(220);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)), bg);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = dark ? Colors.white.withAlpha(90) : Colors.black.withAlpha(70);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)), border);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD2554F).withAlpha(dark ? 220 : 200);
    for (final pts in southSeaLines) {
      if (pts.length < 2) continue;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, line);
    }
    canvas.restore();
  }

  /// 省名：只给点亮的省画，且避开城市标签。合并进主 painter 是为了与地图同一变换层，
  /// InteractiveViewer 缩放时文字随图放大，不会像独立图层那样错位。
  void _paintProvinceLabels(Canvas canvas) {
    for (final v in labelViews) {
      if (!v.visited) continue;
      final center = _centroidOf(v.rings);
      if (center == null) continue;
      final box = projectBbox(v.rings);
      if (box != null && (box.width < 62 || box.height < 40)) continue;

      final tp = TextPainter(
        text: TextSpan(
          text: v.shortName,
          style: TextStyle(
            fontSize: v.selected ? 13 : 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: v.selected
                ? Colors.white
                : (dark ? Colors.white.withAlpha(225) : const Color(0xFF1B3A4B)),
            shadows: [
              Shadow(
                  color: dark ? Colors.black.withAlpha(200) : Colors.white,
                  blurRadius: 4),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // 就近环绕搜索：之前只会一味往下挪，最多 102px ——
      // 山东中部济南/淄博/泰安挤在一起，省名被推到很远的地方，
      // 于是出现"泰安"两个字离它的亮点非常远。现在按距离从小到大试多个方位。
      final anchor = center;
      final candidates = <Offset>[];
      for (final d in _labelOffsets) {
        candidates.add(anchor + Offset(d.dx * tp.width, d.dy * tp.height) -
            Offset(tp.width / 2, tp.height / 2));
      }
      // 兜底：允许小幅上下偏移，但仍限制在锚点附近
      for (var k = 1; k <= 3; k++) {
        candidates
          ..add(anchor - Offset(tp.width / 2, tp.height / 2 + k * 14))
          ..add(anchor - Offset(tp.width / 2, tp.height / 2 - k * 14));
      }

      var drawn = false;
      for (final cand in candidates) {
        final r = cand & Size(tp.width, tp.height);
        if (labelAvoid.any((a) => a.overlaps(r.inflate(2)))) continue;
        tp.paint(canvas, cand);
        drawn = true;
        break;
      }
      if (!drawn) {
        // 实在放不下就不画 —— 宁可少一个字，也不要飘到别处误导用户
        continue;
      }
    }
  }

  /// 相对锚点的候选方位（按视觉优先级排序，均为文字宽高倍数）。
  static const List<Offset> _labelOffsets = [
    Offset(0, 0), // 正中
    Offset(0, -1.15),
    Offset(0, 1.15),
    Offset(-1.1, 0),
    Offset(1.1, 0),
    Offset(-1.0, -1.1),
    Offset(1.0, -1.1),
    Offset(-1.0, 1.1),
    Offset(1.0, 1.1),
  ];

  /// 底色：让国境线以外的区域保持页面背景色，视觉上即"只有中国"。
  void _paintOcean(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [const Color(0xFF0B1220), const Color(0xFF0E1A2B)]
              : [const Color(0xFFF4F8FB), const Color(0xFFEAF1F7)],
        ).createShader(Offset.zero & size),
    );
  }

  void _paintProvince(Canvas canvas, ProvinceStatView s) {
    final fill = Paint()..color = s.fillColor;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.selected ? 1.8 : 0.9
      ..color = s.strokeColor;

    for (final ring in s.rings) {
      if (ring.length < 3) continue;
      final path = Path()..moveTo(ring.first.dx, ring.first.dy);
      for (var i = 1; i < ring.length; i++) {
        path.lineTo(ring[i].dx, ring[i].dy);
      }
      path.close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }

    // 高亮档加一层外发光，让"去过很多次"一眼看出
    if (s.glow) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..color = s.strokeColor.withAlpha(70)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      for (final ring in s.rings) {
        if (ring.length < 3) continue;
        final path = Path()..moveTo(ring.first.dx, ring.first.dy);
        for (var i = 1; i < ring.length; i++) {
          path.lineTo(ring[i].dx, ring[i].dy);
        }
        path.close();
        canvas.drawPath(path, glow);
      }
    }
  }

  void _paintTrack(Canvas canvas) {
    final path = Path()..moveTo(trackPoints.first.dx, trackPoints.first.dy);
    for (var i = 1; i < trackPoints.length; i++) {
      path.lineTo(trackPoints[i].dx, trackPoints[i].dy);
    }
    // 三层叠加做出"发光航线"
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF35D0FF).withAlpha(34));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF7FE0FF).withAlpha(110));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withAlpha(215));
  }

  void _paintCities(Canvas canvas) {
    // 圆点先全部画完，再统一排文字 —— 否则后画的点会被先画的字压住。
    for (final d in cityDots) {
      canvas.drawCircle(
          d.center,
          11,
          Paint()
            ..shader = RadialGradient(colors: [
              const Color(0xFFA8F0FF).withAlpha(120),
              const Color(0xFFA8F0FF).withAlpha(0),
            ]).createShader(Rect.fromCircle(center: d.center, radius: 11)));
      canvas.drawCircle(d.center, 4.4, Paint()..color = const Color(0xFFEAFBFF));
      canvas.drawCircle(
          d.center,
          4.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = const Color(0xFF1E9BD8));
    }

    // 山东半岛那种"淄博/济南/泰安/青岛"挤在一起的情况，
    // 固定偏移会让文字完全叠成黑块，所以逐个找不冲突的落点。
    final placed = <Rect>[];
    // 按 y 排序，让上方城市优先拿到自己正下方的位置，视觉更稳定。
    final ordered = [...cityDots]
      ..sort((a, b) => a.center.dy.compareTo(b.center.dy));

    for (final d in ordered) {
      if (!d.showLabel) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: d.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: dark ? Colors.white : const Color(0xFF12313F),
            shadows: [
              Shadow(
                  color: dark ? Colors.black.withAlpha(220) : Colors.white,
                  blurRadius: 3.5),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final w = tp.width, h = tp.height;
      final c = d.center;
      // 候选：下、右下、左下、右、左、上（避开圆点本身）
      final candidates = <Offset>[
        Offset(c.dx - w / 2, c.dy + 7),
        Offset(c.dx + 8, c.dy + 2),
        Offset(c.dx - w - 8, c.dy + 2),
        Offset(c.dx + 8, c.dy - h / 2),
        Offset(c.dx - w - 8, c.dy - h / 2),
        Offset(c.dx - w / 2, c.dy - h - 8),
        Offset(c.dx - w / 2, c.dy + 22),
      ];
      var chosen = candidates.first;
      for (final cand in candidates) {
        final rect = (cand & Size(w, h)).inflate(2);
        if (!placed.any((p) => p.overlaps(rect))) {
          chosen = cand;
          break;
        }
      }
      placed.add(chosen & Size(w, h));
      tp.paint(canvas, chosen);
    }
  }

  void _paintPlane(Canvas canvas, Offset at) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate((planeBearingDeg ?? 0) * math.pi / 180);
    final body = Path()
      ..moveTo(0, -11)
      ..quadraticBezierTo(2.4, -4.4, 2.4, 1.5)
      ..lineTo(9.6, 6)
      ..lineTo(9.6, 8.4)
      ..lineTo(2.2, 6.6)
      ..lineTo(1.8, 10.2)
      ..lineTo(4.4, 12.8)
      ..lineTo(3.4, 13.8)
      ..lineTo(0, 12)
      ..lineTo(-3.4, 13.8)
      ..lineTo(-4.4, 12.8)
      ..lineTo(-1.8, 10.2)
      ..lineTo(-2.2, 6.6)
      ..lineTo(-9.6, 8.4)
      ..lineTo(-9.6, 6)
      ..lineTo(-2.4, 1.5)
      ..quadraticBezierTo(-2.4, -4.4, 0, -11)
      ..close();
    canvas.drawCircle(Offset.zero, 15,
        Paint()..color = const Color(0x33A8F0FF));
    canvas.drawPath(body, Paint()..color = const Color(0xFFEAFBFF));
    canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF1E9BD8));
    canvas.restore();
  }

  /// 飞机机头朝向（度，0 = 朝北）。由外部按当前航段方位角设置。
  double? planeBearingDeg;

  @override
  bool shouldRepaint(covariant ChinaMapPainter old) =>
      old.projection.size != projection.size ||
      old.stats != stats ||
      old.cityDots != cityDots ||
      old.trackPoints != trackPoints ||
      old.planeAt != planeAt ||
      old.planeBearingDeg != planeBearingDeg ||
      old.selectedProvince != selectedProvince ||
      old.dark != dark ||
      old.showTrack != showTrack;
}

/// 一个省份的可绘制视图（已投影）。
class ProvinceStatView {
  const ProvinceStatView({
    required this.shortName,
    required this.fullName,
    required this.rings,
    required this.fillColor,
    required this.strokeColor,
    required this.visited,
    required this.visitCount,
    required this.cities,
    this.glow = false,
    this.selected = false,
  });

  final String shortName;
  final String fullName;

  /// 已投影成屏幕坐标的多边形环。
  final List<List<Offset>> rings;

  final Color fillColor;
  final Color strokeColor;
  final bool visited;
  final int visitCount;
  final List<String> cities;
  final bool glow;
  final bool selected;
}

/// 一个城市亮点的可绘制视图。
class CityDotView {
  const CityDotView({
    required this.center,
    required this.label,
    required this.cityName,
    this.showLabel = true,
  });

  final Offset center;
  final String label;

  /// 原始城市名，用于点击后回查数据。
  final String cityName;
  final bool showLabel;

  /// 命中半径（逻辑像素）。比可见圆点略大，手指才好点中。
  static const double hitRadius = 16;

  bool hitTest(Offset p) => (p - center).distance <= hitRadius;
}

/// 把省界几何投影为可绘制视图。
List<ProvinceStatView> projectProvinces(
  List<ProvinceShape> shapes,
  MapProjection proj, {
  required Color Function(ProvinceShape s) fill,
  required Color Function(ProvinceShape s) stroke,
  required bool Function(ProvinceShape s) visited,
  required int Function(ProvinceShape s) count,
  required List<String> Function(ProvinceShape s) cities,
  required bool Function(ProvinceShape s) glow,
  String? selectedShortName,
}) {
  final out = <ProvinceStatView>[];
  for (final s in shapes) {
    if (s.isBoundaryLine) continue;
    final rings = <List<Offset>>[];
    for (final ring in s.polygons) {
      rings.add([
        for (final p in ring) proj.project(p.latitude, p.longitude)
      ]);
    }
    if (rings.isEmpty) continue;
    out.add(ProvinceStatView(
      shortName: s.shortName,
      fullName: s.name,
      rings: rings,
      fillColor: fill(s),

      strokeColor: stroke(s),
      visited: visited(s),
      visitCount: count(s),
      cities: cities(s),
      glow: glow(s),
      selected: selectedShortName == s.shortName,
    ));
  }
  return out;
}

/// 射线法判断点是否落在某条环内（用于点击省份）。
bool pointInRings(Offset p, List<List<Offset>> rings) {
  var inside = false;
  for (final ring in rings) {
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      final intersect = ((a.dy > p.dy) != (b.dy > p.dy)) &&
          (p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx);
      if (intersect) inside = !inside;
    }
  }
  return inside;
}

/// 中国陆域主体范围（不含南海深部）。
///
/// 【为什么把南海拆出去】若把曾母暗沙(3.9°N)算进 bbox，geoH 被撑到 ~52°，
/// 竖屏下地图按宽铺满后垂直方向大片空白，中国缩成中间一条、显得又小又扁。
/// 标准中国地图的做法是：陆域主体正常画，南海诸岛+九段线放右下角附图。
const LatLngBounds kChinaMainland = LatLngBounds(17.5, 72.5, 54.5, 135.5);

/// 南海诸岛附图的地理范围（投影到右下角小块区域）。
const LatLngBounds kSouthChinaSeaInset = LatLngBounds(3.5, 106.5, 21.5, 122.0);

/// 兼容旧引用名。
const LatLngBounds kChinaBounds = kChinaMainland;

/// 计算"南海附图"专用投影：把 [kSouthChinaSeaInset] 映射到画布右下角的
/// [origin] 起、边长 [insetSide] 的小方块内。返回的投影直接产出绝对屏幕坐标。
MapProjection? southSeaInsetProjection(
    Size canvasSize, double insetSide, Offset origin) {
  if (canvasSize.width < insetSide * 2.4 || canvasSize.height < 320) return null;
  return MapProjection(
    bounds: kSouthChinaSeaInset,
    size: Size(insetSide, insetSide),
    padding: 4,
    originShift: origin,
  );
}



/// 一组环的整体包围盒（用于判断省份在屏幕上是否太小）。
Rect? projectBbox(List<List<Offset>> rings) {
  double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
  var any = false;
  for (final r in rings) {
    for (final p in r) {
      any = true;
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
  }
  return any ? Rect.fromLTRB(minX, minY, maxX, maxY) : null;
}

/// 收集九段线/南海诸岛边界要素（isBoundaryLine），用给定投影转成屏幕环。
///
/// 【为什么单独收集】主图 bounds 收紧到陆域后，南海深部不在视野内；
/// 但九段线是中国地图的必要组成，不能因为"只显示中国"就把它裁掉。
/// 标准做法是右下角附图：这里给它一个独立小投影，painter 再平移到角落。
List<List<Offset>> projectSouthSeaLines(
    List<ProvinceShape> shapes, MapProjection insetProj) {
  final out = <List<Offset>>[];
  for (final s in shapes) {
    if (!s.isBoundaryLine) continue;
    for (final ring in s.polygons) {
      if (ring.length < 2) continue;
      // 只保留落在南海附图范围内的点，避免把别的边界要素画进来
      final pts = [
        for (final p in ring)
          if (p.latitude >= kSouthChinaSeaInset.south - 1 &&
              p.latitude <= kSouthChinaSeaInset.north + 1 &&
              p.longitude >= kSouthChinaSeaInset.west - 1 &&
              p.longitude <= kSouthChinaSeaInset.east + 1)
            insetProj.project(p.latitude, p.longitude)
      ];
      if (pts.length >= 2) out.add(pts);
    }
  }
  return out;
}

/// 标注锚点：优先取包围盒中心，但必须落在省份轮廓内。
///
/// 【为什么必须做包含性校验】内蒙古是极狭长的东西向条带，
/// 包围盒中心会掉进河北/辽宁那侧的"凹口"里 —— 实测标签直接画到了省外。
/// 甘肃、宁夏、黑龙江同理。所以中心点无效时，退回到最接近中心的真实顶点。
Offset? _centroidOf(List<List<Offset>> rings) {
  if (rings.isEmpty) return null;
  // 选面积最大的那个多边形作为定位依据（而不是点数最多，两者不等价）
  List<Offset>? main;
  double bestArea = -1;
  for (final r in rings) {
    final a = _polygonArea(r);
    if (a > bestArea) {
      bestArea = a;
      main = r;
    }
  }
  final poly = main;
  if (poly == null || poly.length < 3) return null;

  double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
  for (final p in poly) {
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);

  // 中心在轮廓内 → 直接用
  if (_pointInPolygon(center, poly)) return center;

  // 否则找轮廓上离中心最近的顶点，保证标签一定压在省份自己身上
  Offset best = poly.first;
  var bestD = double.infinity;
  for (final p in poly) {
    final d = (p - center).distanceSquared;
    if (d < bestD) {
      bestD = d;
      best = p;
    }
  }
  return best;
}

double _polygonArea(List<Offset> ring) {
  if (ring.length < 3) return 0;
  var s = 0.0;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    s += (ring[j].dx + ring[i].dx) * (ring[j].dy - ring[i].dy);
  }
  return s.abs() / 2;
}

bool _pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    final hit = ((a.dy > p.dy) != (b.dy > p.dy)) &&
        (p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx);
    if (hit) inside = !inside;
  }
  return inside;
}

