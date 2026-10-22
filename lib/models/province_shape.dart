import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 轻量经纬度值对象。
///
/// 【为什么自己定义】原先借用 latlong2 的 LatLng，但那个包只是为地图 SDK 引入的；
/// 省界数据现在由自绘 CustomPaint 消费，没必要为一个双字段结构留依赖。
class GeoLatLng {
  const GeoLatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// 一个省级行政区的边界几何。
///
/// GeoJSON 的 MultiPolygon 结构是 `[多边形][环][点]`（嵌套三层），
/// 解析时必须按这个深度走，少一层就会把经度当成坐标对。
class ProvinceShape {
  ProvinceShape({
    required this.adcode,
    required this.name,
    required this.polygons,
    this.isBoundaryLine = false,
  });

  final String adcode;
  final String name;

  /// 每个 polygon 是若干 ring；第一个 ring 是外轮廓，其余为洞。
  /// 高德 Polygon 只吃"面"，这里统一只取外环绘制。
  final List<List<GeoLatLng>> polygons;

  /// 九段线等边界指示要素：不填色，单独处理。
  final bool isBoundaryLine;

  /// 简称："浙江省" → "浙江"，"内蒙古自治区" → "内蒙古"。
  String get shortName => stripProvinceSuffix(name);

  static ProvinceShape fromFeature(Map<String, dynamic> f) {
    final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final geom = f['geometry'];
    final adcode = (props['adcode'] ?? '').toString();
    final name = (props['name'] ?? '').toString();
    final isLine = props['isBoundaryLine'] == true || adcode.endsWith('_JD');

    final polys = <List<GeoLatLng>>[];
    if (geom is Map && geom['coordinates'] is List) {
      // 【必须按 type 分支】34 个省是 MultiPolygon（[多边形][环][点]，三层），
      // 但内蒙古是 Polygon（[环][点]，只有两层）。之前一律按三层解析，
      // 结果把内蒙古的坐标对 [lon,lat] 当成"环"来遍历，轮廓直接画废。
      final coords = geom['coordinates'] as List;
      if (geom['type'] == 'Polygon') {
        // coordinates = [ring, ring...]，第一个 ring 是外轮廓
        if (coords.isNotEmpty && coords.first is List) {
          final ring = _toLatLngs(coords.first as List);
          if (ring.length >= 3) polys.add(ring);
        }
      } else {
        for (final polygon in coords) {
          if (polygon is! List || polygon.isEmpty) continue;
          final outer = polygon.first;
          if (outer is! List) continue;
          final ring = _toLatLngs(outer);
          if (ring.length >= 3) polys.add(ring);
        }
      }
    }
    return ProvinceShape(
      adcode: adcode,
      name: name,
      polygons: polys,
      isBoundaryLine: isLine,
    );
  }

  static List<GeoLatLng> _toLatLngs(List ring) {
    final out = <GeoLatLng>[];
    for (final pt in ring) {
      if (pt is List && pt.length >= 2) {
        final lon = (pt[0] as num).toDouble();
        final lat = (pt[1] as num).toDouble();
        out.add(GeoLatLng(lat, lon)); // GeoJSON 是 [经度, 纬度]
      }
    }
    return out;
  }
}

/// 去掉省级行政区全称的后缀，得到简称。
String stripProvinceSuffix(String name) {
  const suffixes = [
    '维吾尔自治区', '壮族自治区', '回族自治区', '自治区',
    '特别行政区', '藏族羌族自治州', '土家族苗族自治州',
    '省', '市', '自治区',
  ];
  var n = name.trim();
  for (final s in suffixes) {
    if (n.endsWith(s) && n.length > s.length) {
      return n.substring(0, n.length - s.length);
    }
  }
  return n;
}

/// 省界数据的内存索引。启动时异步加载一次。
class ChinaProvinces {
  ChinaProvinces._(this.list);

  final List<ProvinceShape> list;

  /// 简称 → 形状，用于按到访城市反查所属省。
  late final Map<String, ProvinceShape> byShortName = {
    for (final p in list)
      if (!p.isBoundaryLine) p.shortName: p,
  };

  bool get isEmpty => list.isEmpty;

  static ChinaProvinces? _cache;

  /// 从 APK 资产加载。失败返回空集合（地图会退回无填色状态，不会崩）。
  static Future<ChinaProvinces> load() async {
    if (_cache != null) return _cache!;
    try {
      final raw = await rootBundle.loadString('assets/geo/china_provinces.json');
      final decoded = jsonDecode(raw);
      final features =
          ((decoded as Map)['features'] as List? ?? const []).cast<dynamic>();
      final shapes = features
          .map((f) => ProvinceShape.fromFeature(
              (f as Map).cast<String, dynamic>()))
          .where((s) => s.isBoundaryLine || s.polygons.isNotEmpty)
          .toList();
      _cache = ChinaProvinces._(shapes);
      return _cache!;
    } catch (_) {
      _cache = ChinaProvinces._([]);
      return _cache!;
    }
  }

  /// 测试用：注入已解析结果。
  static ChinaProvinces fromList(List<ProvinceShape> shapes) =>
      ChinaProvinces._(shapes);
}
