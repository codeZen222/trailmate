import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/footprint_model.dart';
import '../../models/footprint_route.dart';
import '../../models/province_shape.dart';
import '../../providers/database_provider.dart';
import '../../providers/footprint_provider.dart';
import '../../providers/journey_provider.dart';
import '../../providers/province_stats_provider.dart';
import '../../core/router/app_router.dart';
import '../../utils/geo_naming.dart';
import '../../widgets/footprint/china_map_painter.dart';
import '../../widgets/footprint/stacked_photo_viewer.dart';
import 'widgets/city_detail_sheet.dart';
import 'widgets/fix_coords_sheet.dart';

/// 足迹地图：**纯自绘**，不依赖任何地图 SDK 或瓦片服务。
///
/// 【为什么自绘】用户要求"只保留中国区域、境外全部去掉"。
/// 地图服务的底图是全球瓦片，竖屏下要横向容纳中国 62° 经度，
/// 纵向必然溢出到西伯利亚与印尼——调 zoom 治不了，这是投影几何决定的。
/// 自绘则天然只画中国轮廓。
///
/// 【定位依然准确】城市经纬度存在数据库 footprints 表里（由高德 Web 服务
/// 地理编码或离线词表算得），那是**数据**，与用什么渲染无关。
/// 这里只是把这些坐标线性投影到屏幕上，精度与原实现完全一致。
class ProvinceMapPage extends ConsumerStatefulWidget {
  const ProvinceMapPage({super.key});

  @override
  ConsumerState<ProvinceMapPage> createState() => _ProvinceMapPageState();
}

class _ProvinceMapPageState extends ConsumerState<ProvinceMapPage>
    with TickerProviderStateMixin {
  String? _selectedProvince;
  bool _showTrack = true;

  String? _trackTrip;

  bool _flying = false;
  Timer? _flyTimer;
  double _flyProgress = 0;

  final List<double> _cumLen = [];
  double _totalLen = 0;

  /// 地图缩放与平移（矢量重绘，不是位图拉伸）。
  double _scale = 1.0;
  Offset _pan = Offset.zero;
  static const double _minScale = 1.0;
  static const double _maxScale = 6.0;

  // ==================== 缩放 / 平移 ====================

  /// 双击 / 按钮触发的视图动画；手势操作会 stop 它（手势优先）。
  late final AnimationController _viewAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 240));
  double _animFromScale = 1.0;
  double _animToScale = 1.0;
  Offset _animFromPan = Offset.zero;
  Offset _animToPan = Offset.zero;

  /// 双击按下点。onDoubleTap 时取用。
  Offset? _doubleTapPos;

  double _scaleStart = 1.0;
  Offset _panStart = Offset.zero;
  Offset _scaleAnchor = Offset.zero;

  @override
  void initState() {
    super.initState();
    _viewAnim.addListener(_tickViewAnim);
  }

  @override
  void dispose() {
    _flyTimer?.cancel();
    _viewAnim.dispose();
    super.dispose();
  }

  /// 投影锚点（中国几何中心的屏幕落点）。只由画布尺寸决定，与 scale 无关。
  Offset _projectionAnchor(Size sz) => MapProjection(
        bounds: kChinaBounds,
        size: sz,
        scale: 1.0,
      ).anchor;

  /// 缩放公共公式：让 [focus] 焦点下的地点缩放后仍停在焦点处。
  ///
  /// 推导：屏幕点 = anchor + 地理向量*k*scale + pan。
  /// 焦点 F0 对应的地理向量 v 满足 F0 = anchor + v*scaleOld + panOld，
  /// 缩放后要求同一点落在 F：F = anchor + v*scaleNew + panNew，
  /// 消去 v 即得 panNew = F - anchor - (F0-anchor-panOld)*grow。
  ///
  /// 【旧实现为什么漂移】把公式里的 F0 写成了"当前焦点"，双指不在地图
  /// 中心时每帧都在累积误差，捏合越久偏得越远。
  Offset _panAfterZoom(double nextScale,
      {required Offset focusFrom, required Offset focusTo, required Size sz}) {
    final anchor = _projectionAnchor(sz);
    final grow = nextScale / _scale;
    return focusTo -
        anchor -
        (focusFrom - anchor - _pan) * grow;
  }

  /// 双击缩放。
  ///
  /// 【旧实现为什么是坏的】onDoubleTapDown 里放大、onDoubleTap 里复位，
  /// 两个回调必定先后触发（down 在前、up 在后），净效果 = 放大又被立刻
  /// 按回去，双击缩放从未真正生效过。现在 down 只记位置，up 才执行。
  void _onDoubleTap(Size sz) {
    final pos = _doubleTapPos;
    if (pos == null) return;
    if (_scale > 1.05) {
      _animateView(1.0, Offset.zero);
    } else {
      const target = 2.5;
      final pan =
          _panAfterZoom(target, focusFrom: pos, focusTo: pos, sz: sz);
      _animateView(target, _clampPanValue(pan, sz, target));
    }
  }

  /// 加减按钮：围绕屏幕中心缩放一档。
  void _zoomBy(double factor, Size sz) {
    final target = (_scale * factor).clamp(_minScale, _maxScale);
    if ((target - _scale).abs() < 0.01) return;
    final center = Offset(sz.width / 2, sz.height / 2);
    final pan = _panAfterZoom(target,
        focusFrom: center, focusTo: center, sz: sz);
    _animateView(target, _clampPanValue(pan, sz, target));
  }

  void _resetView() => _animateView(1.0, Offset.zero);

  void _animateView(double toScale, Offset toPan) {
    _animFromScale = _scale;
    _animToScale = toScale;
    _animFromPan = _pan;
    _animToPan = toPan;
    _viewAnim.forward(from: 0);
  }

  void _tickViewAnim() {
    if (!_viewAnim.isAnimating || !mounted) return;
    final t = Curves.easeOutCubic.transform(_viewAnim.value);
    setState(() {
      _scale = _animFromScale + (_animToScale - _animFromScale) * t;
      _pan = Offset.lerp(_animFromPan, _animToPan, t)!;
    });
  }

  void _onScaleStart(ScaleStartDetails d, Size sz) {
    _viewAnim.stop(); // 手势接管，自动动画立即让位
    _scaleStart = _scale;
    _panStart = _pan;
    _scaleAnchor = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size sz) {
    final next = (_scaleStart * d.scale).clamp(_minScale, _maxScale);
    final grow = next / _scaleStart;
    final anchor = _projectionAnchor(sz);
    final f = d.localFocalPoint;
    setState(() {
      // 与 _panAfterZoom 同一条公式，焦点随手势移动（F0 = 起始焦点，F = 当前焦点）
      _pan = f - anchor - (_scaleAnchor - anchor - _panStart) * grow;
      _scale = next;
      _clampPan(sz);
    });
  }

  /// 平移上限必须按"地图实际绘制尺寸"算，而不是按屏幕一半。
  /// 之前用 ±屏宽/2 作为余量，等于允许把中国整个推出画面还回不来。
  void _clampPan(Size sz) => _pan = _clampPanValue(_pan, sz, _scale);

  Offset _clampPanValue(Offset pan, Size sz, double scale) {
    final proj = MapProjection(
        bounds: kChinaBounds,
        size: sz,
        scale: scale,
        originShift: Offset.zero);
    // 地图中心相对默认位置最多偏离半个地图自身尺寸，保证主体始终可见。
    final limX = math.max(40.0, proj.drawnW / 2);
    final limY = math.max(40.0, proj.drawnH / 2);
    return Offset(pan.dx.clamp(-limX, limX), pan.dy.clamp(-limY, limY));
  }

  // ==================== 轨迹点（屏幕坐标）====================

  /// 当前回溯范围内的原始经纬度点列：全部历史，或单条旅程。
  List<(double lat, double lon)> _activeRawPoints(ChinaProvinces provinces) {
    if (_trackTrip != null) return _rawForTrip(_trackTrip!);
    final full = ref.read(journeyTrackProvider);
    return [
      for (final p in full.points) (p.latitude, p.longitude),
    ];
  }

  List<(double lat, double lon)> _rawForTrip(String destination) {
    final routes =
        ref.read(tripRoutesProvider).valueOrNull ?? const <TripRoute>[];
    final hit = routes.where((r) => r.destination == destination).firstOrNull;
    if (hit == null) return const [];
    return [
      for (final p in hit.points) (p.latitude, p.longitude),
    ];
  }

  /// 累计弧长表（公里），用于匀速飞行。
  void _rebuildLengths(List<(double, double)> pts) {
    _cumLen.clear();
    _totalLen = 0;
    if (pts.isEmpty) return;
    _cumLen.add(0);
    for (var i = 1; i < pts.length; i++) {
      _totalLen += _haversine(pts[i - 1], pts[i]);
      _cumLen.add(_totalLen);
    }
  }

  double _haversine((double, double) a, (double, double) b) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(b.$2 - a.$2);
    final dLon = rad(b.$1 - a.$1);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(a.$2)) * math.cos(rad(b.$2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
  }

  /// 进度 -> 原始点序列中的浮点下标（按弧长换算，保证视觉匀速）。
  double _indexAtProgress(double progress, int pointCount) {
    if (pointCount < 2) return 0;
    if (progress <= 0) return 0;
    if (progress >= 1) return (pointCount - 1).toDouble();
    if (_cumLen.length < 2 || _totalLen <= 0) return progress * (pointCount - 1);
    final target = _totalLen * progress;
    for (var seg = 0; seg + 1 < _cumLen.length; seg++) {
      final s0 = _cumLen[seg], s1 = _cumLen[seg + 1];
      final isLast = seg == _cumLen.length - 2;
      if (target > s1 && !isLast) continue;
      final within = s1 <= s0 ? 0.0 : ((target - s0) / (s1 - s0)).clamp(0.0, 1.0);
      return (seg + within).clamp(0.0, (pointCount - 1).toDouble());
    }
    return (pointCount - 1).toDouble();
  }

  /// 由浮点下标得到插值后的经纬度。
  (double lat, double lon) _lerpPoint(
      List<(double, double)> pts, double idx) {
    final i = idx.floor().clamp(0, pts.length - 2);
    final t = idx - i;
    final a = pts[i], b = pts[i + 1];
    return (a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t);
  }

  Future<void> _startFly() async {
    final raw = _activeRawPoints(
        ref.read(chinaProvincesProvider).valueOrNull ?? ChinaProvinces.fromList(const []));
    if (raw.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个范围内不足 2 个定位点，无法回溯')),
      );
      return;
    }
    _rebuildLengths(raw);
    setState(() {
      _flying = true;
      _flyProgress = 0;
    });
    const totalMs = 9000;
    _flyTimer?.cancel();
    _flyTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _flyProgress += 40 / totalMs;
        if (_flyProgress >= 1) _flyProgress = 1;
      });
      if (_flyProgress >= 1) {
        _flyTimer?.cancel();
        _flyTimer = null;
        setState(() => _flying = false);
      }
    });
  }

  void _stopFly() {
    _flyTimer?.cancel();
    _flyTimer = null;
    if (mounted) setState(() => _flying = false);
  }

  // ==================== 交互 ====================

  Future<void> _onCityTap(Footprint f) async {
    final prov = _provOf(f.cityName);
    if (prov != null) setState(() => _selectedProvince = prov);

    final paths = await ref
        .read(databaseProvider)
        .getRecentCoverImagesByCity(f.cityName, limit: 6);
    if (!mounted) return;

    if (paths.isEmpty) {
      CityDetailSheet.show(context, f);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${f.cityName} 还没有照片，已打开城市详情')),
      );
      return;
    }
    StackedPhotoViewer.open(context,
        paths: paths,
        title: cityOf(f.cityName) ?? f.cityName,
        subtitle: _statLine(f),
        onDetails: () => CityDetailSheet.show(context, f));
  }

  String _statLine(Footprint f) {
    final prov = provinceOf(f.cityName);
    final times = f.visitCount > 1 ? ' · 去过 ${f.visitCount} 次' : '';
    final first =
        '${f.firstVisitedAt.year}.${f.firstVisitedAt.month.toString().padLeft(2, '0')} 首访';
    return '${prov == null ? '' : '${stripProvinceSuffix(prov)} · '}$first$times';
  }

  String? _provOf(String cityName) {
    final direct = provinceOf(cityName);
    if (direct != null) return stripProvinceSuffix(direct);
    final c = cityOf(cityName);
    if (c == null) return null;
    for (final e in kProvinceCities.entries) {
      if (e.value.contains(c)) return stripProvinceSuffix(e.key);
    }
    return null;
  }

  void _onTapUp(
      TapUpDetails d, List<ProvinceStatView> views, List<CityDotView> dots) {
    // 城市点更小更难瞄，优先命中它 —— 直接看照片是主用途
    for (final dot in dots) {
      if (!dot.hitTest(d.localPosition)) continue;
      final fp = _footprintByCity[dot.cityName];
      if (fp != null) {
        _onCityTap(fp);
        return;
      }
    }
    for (final v in views) {
      if (!pointInRings(d.localPosition, v.rings)) continue;
      setState(() => _selectedProvince = v.shortName);
      return;
    }
    // 空白处点击收起面板
    if (_selectedProvince != null) setState(() => _selectedProvince = null);
  }

  /// 城市名 -> 足迹对象，供点击回查。build 中重建。
  Map<String, Footprint> _footprintByCity = const {};

  // ==================== 渲染 ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final provincesAsync = ref.watch(chinaProvincesProvider);
    final stats = ref.watch(provinceStatsProvider);
    final footprints = ref.watch(footprintListProvider).valueOrNull ?? const [];
    final unassigned = ref.watch(unassignedCitiesProvider);
    final unresolvedCount =
        ref.watch(unresolvedFootprintsProvider).valueOrNull?.length ?? 0;
    final litCount = stats.visitedProvinces;

    return Scaffold(
      appBar: AppBar(
        title: const Text('足迹地图'),
        actions: [
          IconButton(
            icon: Icon(_showTrack ? Icons.route : Icons.route_outlined),
            tooltip: _showTrack ? '隐藏时间轨迹' : '显示时间轨迹',
            onPressed: () => setState(() => _showTrack = !_showTrack),
          ),
        ],
      ),
      body: provincesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Notice(
            icon: Icons.cloud_off, title: '省界数据加载失败', detail: '$e'),
        data: (provinces) {
          if (provinces.isEmpty) {
            return const _Notice(
              icon: Icons.public,
              title: '省界数据缺失',
              detail: 'assets/geo/china_provinces.json 未打包进应用',
            );
          }

          return LayoutBuilder(builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            // scale/pan 进入投影 => 每次都是矢量重算，放大不糊
            final proj = MapProjection(
              bounds: kChinaBounds,
              size: size,
              scale: _scale,
              originShift: _pan,
            );

            final views = projectProvinces(
              provinces.list,
              proj,
              fill: (s) {
                final st = stats.byShortName[s.shortName];
                final tier = st?.tier ?? VisitTier.none;
                return ProvinceStats.fillFor(tier, dark: dark).color;
              },
              stroke: (s) {
                final st = stats.byShortName[s.shortName];
                final tier = st?.tier ?? VisitTier.none;
                return ProvinceStats.fillFor(tier, dark: dark).stroke;
              },
              visited: (s) => (stats.byShortName[s.shortName]?.visitCount ?? 0) > 0,
              count: (s) => stats.byShortName[s.shortName]?.visitCount ?? 0,
              cities: (s) => stats.byShortName[s.shortName]?.cities ?? const [],
              glow: (s) =>
                  (stats.byShortName[s.shortName]?.tier ?? VisitTier.none) ==
                  VisitTier.high,
              selectedShortName: _selectedProvince,
            );

            final dots = [
              for (final f in footprints)
                if (!(f.latitude == 0 && f.longitude == 0))
                  CityDotView(
                    center: proj.project(f.latitude, f.longitude),
                    label: cityOf(f.cityName) ?? f.cityName,
                    cityName: f.cityName,
                  ),
            ];
            _footprintByCity = {
              for (final f in footprints) f.cityName: f,
            };

            // 城市标签占位（painter 里画在点下方约 y+7、高 ~13）
            final cityLabelRects = [
              for (final d in dots)
                Rect.fromLTWH(d.center.dx - 26, d.center.dy + 6, 52, 15),
            ];

            final rawPts = _activeRawPoints(provinces);
            final trackOffsets = [
              for (final p in rawPts) proj.project(p.$1, p.$2),
            ];

            // 飞机位置与拖尾共用同一个下标，二者才不会脱节
            List<Offset> visibleTrack;
            Offset? planePos;
            double? planeBearing;
            if (_showTrack && rawPts.length >= 2) {
              final idx = _flying || _flyProgress > 0
                  ? _indexAtProgress(_flyProgress, rawPts.length)
                  : (rawPts.length - 1).toDouble();
              final cut = idx.round().clamp(1, rawPts.length);
              visibleTrack = trackOffsets.sublist(0, cut + 1);
              if (_flying || _flyProgress > 0) {
                final lp = _lerpPoint(rawPts, idx);
                planePos = proj.project(lp.$1, lp.$2);
                planeBearing = _bearingOf(rawPts, idx);
              }
            } else {
              visibleTrack = const [];
            }

            // 南海诸岛附图：主图收紧到陆域后，九段线画在右下角小块区域。
            // 位置要避开精灵、"未归类"提示与 FAB —— 它们都堆在右下。
            const insetSide = 92.0;
            final insetOrigin = Offset(
              size.width - insetSide - 12,
              (size.height - insetSide - 250).clamp(0.0, size.height - insetSide),
            );
            final insetProj =
                southSeaInsetProjection(size, insetSide, insetOrigin);
            final southSeaLines = insetProj == null
                ? const <List<Offset>>[]
                : projectSouthSeaLines(provinces.list, insetProj);
            final insetRect = Rect.fromLTWH(
                insetOrigin.dx, insetOrigin.dy, insetSide, insetSide);

            final painter = ChinaMapPainter(
              projection: proj,
              stats: views,
              cityDots: dots,
              trackPoints: visibleTrack,
              planeAt: planePos,
              selectedProvince: _selectedProvince,
              dark: dark,
              showTrack: _showTrack,
              labelViews: views,
              labelAvoid: cityLabelRects,
              southSeaLines: southSeaLines,
              southSeaInsetRect: southSeaLines.isEmpty ? null : insetRect,
            )..planeBearingDeg = planeBearing;

            return Stack(
              children: [
                Positioned.fill(
                  // 【为什么不用 InteractiveViewer】它是对已渲染位图做矩阵缩放，
                  // 放大后文字与圆点会一起被拉伸发虚（真机上出现过整屏糊成色块）。
                  // 这里只保存 scale/pan 状态，交给投影重新计算矢量坐标，
                  // 于是放大 = 用更大比例重画，任何倍率下都保持清晰。
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
                    onDoubleTap: () => _onDoubleTap(size),
                    onTapUp: (d) => _onTapUp(d, views, dots),
                    onScaleStart: (d) => _onScaleStart(d, size),
                    onScaleUpdate: (d) => _onScaleUpdate(d, size),
                    child: CustomPaint(painter: painter, size: size),
                  ),
                ),

                // 右侧缩放控件：+/− 固定显示，发生过缩放或拖动时附"看全图"。
                // 【为什么加】双击缩放修复前基本不可用，单指用户没有任何
                // 缩放入口；双指捏合修复前又会漂移，放大靠运气。
                Positioned(
                  top: 62,
                  right: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ZoomStepButton(
                          icon: Icons.add, onTap: () => _zoomBy(1.5, size)),
                      const SizedBox(height: 6),
                      _ZoomStepButton(
                          icon: Icons.remove,
                          onTap: () => _zoomBy(1 / 1.5, size)),
                      if (_scale > 1.02 || _pan != Offset.zero) ...[
                        const SizedBox(height: 6),
                        _ResetZoomButton(onTap: _resetView),
                      ],
                    ],
                  ),
                ),

                Positioned(
                  top: 8,
                  left: 12,
                  right: 12,
                  child: _SummaryBar(
                    visited: stats.visitedProvinces,
                    total: stats.provinceCount,
                    cities: footprints.length,
                  ),
                ),

                // 回溯入口：只留一个播放按钮（原来的"全部旅程/按旅程"整行已按要求移除）
                if (_showTrack && rawPts.length >= 2)
                  Positioned(
                    top: 62,
                    left: 12,
                    child: _ReplayButton(
                      flying: _flying,
                      onToggle: () => _flying ? _stopFly() : _startFly(),
                    ),
                  ),

                Positioned(
                  bottom: _selectedProvince != null ? 150 : 92,
                  left: 12,
                  child: _Legend(dark: dark),
                ),

                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: 12,
                  right: 12,
                  bottom: _selectedProvince == null ? -170 : 20,
                  child: _selectedProvince == null
                      ? const SizedBox.shrink()
                      : _ProvincePanel(
                          stat: stats.byShortName[_selectedProvince],
                          onClose: () =>
                              setState(() => _selectedProvince = null),
                        ),
                ),

                if (unassigned.isNotEmpty)
                  Positioned(
                    bottom: 92,
                    right: 12,
                    child: _UnassignedChip(
                      count: unassigned.length,
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('这些城市暂无法归到省'),
                          content: SizedBox(
                            width: 300,
                            child: Text(unassigned.join('、'),
                                style: const TextStyle(height: 1.7)),
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('知道了')),
                          ],
                        ),
                      ),
                    ),
                  ),

                if (unresolvedCount > 0)
                  Positioned(
                    // 下移避开右侧缩放控件列（+/− + 看全图，约 176px 高）
                    top: 184,
                    right: 12,
                    child: _FixCoordsChip(
                      count: unresolvedCount,
                      onTap: () async {
                        await FixCoordsSheet.show(context);
                        ref.invalidate(footprintListProvider);
                        ref.invalidate(unresolvedFootprintsProvider);
                      },
                    ),
                  ),
              ],
            );
          });
        },
      ),
      floatingActionButton: litCount == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                // 清单页点省份行会回传简称，地图联动高亮该省
                final sel = await Navigator.pushNamed(
                    context, AppRouter.footprintList);
                if (!mounted || sel is! String) return;
                setState(() => _selectedProvince = sel);
              },
              icon: const Icon(Icons.list_alt),
              label: Text('已点亮 $litCount 省'),
            ),
    );
  }

  /// 机头朝向：取当前分段的前方方向，避免单点抖动导致乱转。
  double _bearingOf(List<(double, double)> pts, double idx) {
    if (pts.length < 2) return 0;
    final i = idx.floor().clamp(0, pts.length - 2);
    final a = pts[i], b = pts[i + 1];
    double rad(double d) => d * math.pi / 180.0;
    final y = math.sin(rad(b.$2 - a.$2)) * math.cos(rad(b.$1));
    final x = math.cos(rad(a.$1)) * math.sin(rad(b.$1)) -
        math.sin(rad(a.$1)) * math.cos(rad(b.$1)) * math.cos(rad(b.$2 - a.$2));
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}

// ==================== 以下 UI 组件与地图实现无关，沿用原样式 ====================

class _SummaryBar extends StatelessWidget {
  const _SummaryBar(
      {required this.visited, required this.total, required this.cities});

  final int visited;
  final int total;
  final int cities;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(140),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.public, size: 16, color: Color(0xFF8FE0FF)),
          const SizedBox(width: 8),
          Text('中国地图 · 省级足迹',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withAlpha(230))),
          const Spacer(),
          Text('$visited/$total 省 · $cities 城',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFBFE8F5))),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(130),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tier in VisitTier.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: ProvinceStats.fillFor(tier, dark: dark).color,
                      border: Border.all(
                          color:
                              ProvinceStats.fillFor(tier, dark: dark).stroke,
                          width: 1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(tier.label,
                      style: const TextStyle(
                          fontSize: 10.5, color: Color(0xFFDCEEF6))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProvincePanel extends StatelessWidget {
  const _ProvincePanel({required this.stat, required this.onClose});

  final ProvinceStat? stat;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = stat;
    if (s == null) return const SizedBox.shrink();
    return Material(
      color: Colors.black.withAlpha(190),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(s.shape.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E9BD8).withAlpha(90),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${s.visitCount} 次',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFBDEFFF))),
                      ),
                    ],
                  ),
                  if (s.cities.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('去过：${s.cities.join(' · ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Colors.white.withAlpha(200))),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _UnassignedChip extends StatelessWidget {
  const _UnassignedChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(130),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFC85C).withAlpha(140)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline, size: 14, color: Color(0xFFFFC85C)),
            const SizedBox(width: 5),
            Text('$count 城未归类',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFFFFDC9C))),
          ],
        ),
      ),
    );
  }
}

class _FixCoordsChip extends StatelessWidget {
  const _FixCoordsChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(140),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF7FE0FF).withAlpha(150)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.my_location, size: 14, color: Color(0xFF8FE0FF)),
            const SizedBox(width: 5),
            Text('$count 城无坐标',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFFCFEFFB))),
          ],
        ),
      ),
    );
  }
}

/// 回溯播放按钮：只保留一个开关（"全部旅程/按旅程"整行已按要求移除）。
class _ReplayButton extends StatelessWidget {
  const _ReplayButton({required this.flying, required this.onToggle});

  final bool flying;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(150),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                flying ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                color: const Color(0xFF8FE0FF),
                size: 22,
              ),
              const SizedBox(width: 6),
              Text(flying ? '停止' : '回溯',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 加减缩放按钮：右侧一列，单指也能稳定缩放。
class _ZoomStepButton extends StatelessWidget {
  const _ZoomStepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(150),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Icon(icon, color: const Color(0xFF8FE0FF), size: 20),
        ),
      ),
    );
  }
}

/// 放大后的一键复位。
class _ResetZoomButton extends StatelessWidget {
  const _ResetZoomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(150),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.zoom_out, color: Color(0xFF8FE0FF), size: 18),
              SizedBox(width: 5),
              Text('看全图',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, this.detail});

  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleMedium),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ],
        ),
      ),
    );
  }
}
