import 'package:flutter/foundation.dart';
import '../database/app_database.dart' as db;
import '../utils/city_extractor.dart';
import '../utils/geo_coder.dart';

/// 把历史足迹里的区县级条目并入所属地级市。
///
/// 【为什么需要】早期 `CityExtractor` 词表不含"泰安""济阳"这类名字，
/// 于是"济阳"作为独立城市写进了 footprints，坐标又查不到 => (0,0)。
/// 结果：地图上多出一个不该显示的城市、定位乱飞、连线漏掉真正的目的地。
/// 词表修正只影响**之后**创建的旅程，老数据必须在这里归并一次。
Future<void> normalizeFootprintCities(db.AppDatabase database) async {
  final all = await database.getAllFootprints();
  if (all.length < 2) return;

  // 归一化后的城市名 -> 该名的所有足迹（按首访时间升序）
  final groups = <String, List<db.Footprint>>{};
  for (final f in all) {
    final canonical = CityExtractor.extract(f.cityName).city;
    (groups[canonical] ??= []).add(f);
  }

  for (final e in groups.entries) {
    final list = e.value..sort((a, b) => a.firstVisitedAt.compareTo(b.firstVisitedAt));
    if (list.length < 2) continue;

    final keeper = _pickKeeper(list);
    var mergedAny = false;
    for (final f in list) {
      if (f.id == keeper.id) continue;
      final ok = await database.mergeFootprintInto(f.id, keeper.id);
      mergedAny = mergedAny || ok;
    }
    if (mergedAny) {
      debugPrint('footprint 归并: ${e.key} <- '
          '${list.where((x) => x.id != keeper.id).map((x) => x.cityName).join(', ')}');
    }
  }

  // 归并后可能仍有 (0,0)：再跑一次离线词表解析（高德兜底由调用方负责）
  final left = await database.getFootprintsWithoutCoords();
  for (final f in left) {
    final coords = GeoCoder.lookup(CityExtractor.extract(f.cityName).city);
    if (coords == null) continue;
    await database.setFootprintCoords(f.id, coords.lat, coords.lon);
  }
}

/// 组内保留哪一条：优先有坐标的，其次名字已经是规范城市名的，最后取最早那条。
db.Footprint _pickKeeper(List<db.Footprint> list) {
  db.Footprint? best;
  int score(db.Footprint f) {
    var s = 0;
    if (f.latitude != 0 || f.longitude != 0) s += 100;
    if (f.cityName == CityExtractor.extract(f.cityName).city) s += 50;
    s += f.visitCount; // 次数多的更能代表这个城市
    return s;
  }

  for (final f in list) {
    if (best == null || score(f) > score(best)) best = f;
  }
  return best!;
}
