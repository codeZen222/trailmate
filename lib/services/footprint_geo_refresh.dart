import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import '../database/app_database.dart' as db;
import '../utils/city_extractor.dart';
import 'amap_geocoding_service.dart';

/// 用第三方（高德 Web 服务）**重新确定**每条足迹的坐标。
///
/// 【为什么必须重查而不是只补空值】
/// 老数据里存在两类错：① 写成 (0,0)（离线词表没这个地名）；
/// ② **值本身就是错的** —— 例如"泰山"被解析到台湾南投，偏差 1300 公里。
/// 第 ② 类比第 ① 类更糟，因为它看起来"有坐标"，任何基于非空的判断都会放过它。
/// 所以这里对全部记录重查并覆盖。
///
/// 【配额控制】免费档 QPS 很低，AmapGeocodingService 内部已做 420ms 串行节流
/// 与结果持久缓存（settings 表 geo_<地名>），因此第二次运行几乎零请求。
class FootprintGeoRefresh {
  FootprintGeoRefresh(this._db, this._geo);

  final db.AppDatabase _db;
  final AmapGeocodingService _geo;

  /// 中国陆域大致范围。落在外面的坐标一律视为可疑并强制重查。
  static const double _cnSouth = 3.5, _cnNorth = 54.0;
  static const double _cnWest = 72.5, _cnEast = 136.5;

  /// 返回 (修正条数, 失败条数)。
  Future<({int fixed, int failed})> run({void Function(int done, int total)? onProgress}) async {
    final all = await _db.getAllFootprints();
    var fixed = 0, failed = 0;

    for (var i = 0; i < all.length; i++) {
      final f = all[i];
      onProgress?.call(i, all.length);

      // 归并后的规范名才是可安全查询的（"泰山"->"泰安"、"济阳"->"济南"）
      final canonical = CityExtractor.canonicalCity(f.cityName);
      final p = await _geo.locate(canonical);
      if (p == null) {
        failed++;
        continue;
      }

      // 明显不在中国境内的结果直接丢弃，宁可不改也不要写进错误坐标
      if (p.latitude < _cnSouth || p.latitude > _cnNorth ||
          p.longitude < _cnWest || p.longitude > _cnEast) {
        debugPrint('footprint 坐标越界，跳过: ${f.cityName} -> ${p.latitude},${p.longitude}');
        failed++;
        continue;
      }

      final moved = (p.latitude - f.latitude).abs() > 0.01 ||
          (p.longitude - f.longitude).abs() > 0.01;
      if (!moved) continue;

      await _db.setFootprintCoords(f.id, p.latitude, p.longitude);
      fixed++;
      debugPrint('footprint 坐标修正: ${f.cityName} '
          '(${f.latitude.toStringAsFixed(2)},${f.longitude.toStringAsFixed(2)}) '
          '-> (${p.latitude.toStringAsFixed(3)},${p.longitude.toStringAsFixed(3)})');
    }
    return (fixed: fixed, failed: failed);
  }
}

/// 两点球面距离（公里），供上层判断是否值得提示用户。
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180.0;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}
