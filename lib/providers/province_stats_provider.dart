import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/footprint_model.dart';
import '../models/province_shape.dart';
import '../providers/footprint_provider.dart';
import '../utils/geo_naming.dart';

/// 到访次数分档。按用户指定的四级：0 / 1-3 / 4-6 / >6。
enum VisitTier {
  none(0, '0次'),
  light(1, '1-3次'),
  mid(2, '4-6次'),
  high(3, '6次以上');

  const VisitTier(this.level, this.label);
  final int level;
  final String label;

  static VisitTier of(int count) {
    if (count <= 0) return VisitTier.none;
    if (count <= 3) return VisitTier.light;
    if (count <= 6) return VisitTier.mid;
    return VisitTier.high;
  }
}

/// 单个省份的统计结果。
class ProvinceStat {
  const ProvinceStat({
    required this.shape,
    required this.visitCount,
    required this.cities,
  });

  final ProvinceShape shape;

  /// 该省到访总次数 = 省内各城市 visitCount 之和。
  final int visitCount;

  /// 省内去过的城市名。
  final List<String> cities;

  VisitTier get tier => VisitTier.of(visitCount);
  bool get visited => visitCount > 0;
}

/// 省级填色配置：不同档位用不同亮度。
/// 深色底图下"亮"意味着更饱和更不透明，未去过的省几乎不可见。
class ProvinceFill {
  const ProvinceFill({required this.color, required this.stroke});
  final Color color;
  final Color stroke;
}

/// 把足迹按省聚合。
class ProvinceStats {
  ProvinceStats({required this.byShortName, required this.total});

  /// 简称 → 统计（含未去过的省，值为 visitCount 0）
  final Map<String, ProvinceStat> byShortName;
  final List<ProvinceStat> total;

  int get visitedProvinces => total.where((s) => s.visited).length;
  int get provinceCount => total.where((s) => !s.shape.isBoundaryLine).length;

  /// 暗色主题下的四级亮度。
  static ProvinceFill fillFor(VisitTier tier, {bool dark = true}) {
    if (dark) {
      switch (tier) {
        case VisitTier.none:
          return const ProvinceFill(color: Color(0x14FFFFFF), stroke: Color(0x33A8C8E8));
        case VisitTier.light:
          return const ProvinceFill(color: Color(0x5935D0FF), stroke: Color(0x997FE0FF));
        case VisitTier.mid:
          return const ProvinceFill(color: Color(0x9928B4FF), stroke: Color(0xCC8CE8FF));
        case VisitTier.high:
          return const ProvinceFill(color: Color(0xCC12E0FF), stroke: Color(0xFFFFFFFF));
      }
    }
    // 浅色主题：改用主色深浅表达，避免白底上看不清
    switch (tier) {
      case VisitTier.none:
        return const ProvinceFill(color: Color(0x0A000000), stroke: Color(0x22000000));
      case VisitTier.light:
        return const ProvinceFill(color: Color(0x334A7FB5), stroke: Color(0x664A7FB5));
      case VisitTier.mid:
        return const ProvinceFill(color: Color(0x663A6FA8), stroke: Color(0x993A6FA8));
      case VisitTier.high:
        return const ProvinceFill(color: Color(0x992F5E9E), stroke: Color(0xCC2F5E9E));
    }
  }
}

/// 省界几何（异步加载一次）。
final chinaProvincesProvider = FutureProvider<ChinaProvinces>((ref) async {
  return ChinaProvinces.load();
});

final _footprintsForProvince = Provider<List<Footprint>>(
    (ref) => ref.watch(footprintListProvider).valueOrNull ?? const []);

/// 核心：把每个城市归到省份，累加到访次数。
///
/// 【归属判定顺序】
/// 1. 优先用 geo_naming 从"河南洛阳"这类文本直接剥出省名
/// 2. 剥不出省名的（如只写了"济阳"），查 kProvinceCities 反查表
/// 3. 仍无法归属的城市计入 unassigned，界面如实提示，不硬塞给某省
final provinceStatsProvider = Provider<ProvinceStats>((ref) {
  final provinces = ref.watch(chinaProvincesProvider).valueOrNull;
  final footprints = ref.watch(_footprintsForProvince);

  if (provinces == null || provinces.isEmpty) {
    return ProvinceStats(byShortName: const {}, total: const []);
  }

  // 城市 → 省计数
  final cityCount = <String, int>{};
  final citiesOf = <String, Set<String>>{};
  for (final f in footprints) {
    final prov = _provinceOf(f.cityName);
    if (prov == null) continue;
    cityCount[prov] = (cityCount[prov] ?? 0) + f.visitCount;
    (citiesOf[prov] ??= {}).add(cityOf(f.cityName) ?? f.cityName);
  }

  final list = <ProvinceStat>[];
  final map = <String, ProvinceStat>{};
  for (final shape in provinces.list) {
    if (shape.isBoundaryLine) continue;
    final stat = ProvinceStat(
      shape: shape,
      visitCount: cityCount[shape.shortName] ?? 0,
      cities: (citiesOf[shape.shortName] ?? const {}).toList(),
    );
    list.add(stat);
    map[shape.shortName] = stat;
  }
  return ProvinceStats(byShortName: map, total: list);
});

/// 无法归属到省的城市名（界面提示用）。
final unassignedCitiesProvider = Provider<List<String>>((ref) {
  final footprints = ref.watch(_footprintsForProvince);
  final out = <String>[];
  for (final f in footprints) {
    if (_provinceOf(f.cityName) == null) out.add(f.cityName);
  }
  return out;
});

String? _provinceOf(String cityName) {
  // 1) 文本里带省名
  final direct = provinceOf(cityName);
  if (direct != null) return stripProvinceSuffix(direct);
  // 2) 反查表
  final c = cityOf(cityName);
  if (c == null) return null;
  for (final e in kProvinceCities.entries) {
    if (e.value.contains(c)) return stripProvinceSuffix(e.key);
  }
  return null;
}
