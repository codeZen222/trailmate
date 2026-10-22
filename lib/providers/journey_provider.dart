import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/footprint_model.dart';
import '../models/footprint_route.dart';
import '../models/province_shape.dart' show stripProvinceSuffix;
import '../providers/database_provider.dart';
import '../providers/footprint_provider.dart';
import '../utils/geo_naming.dart';

/// 轨迹上的一段：从一个城市到下一个城市。
class JourneySegment {
  const JourneySegment({
    required this.from,
    required this.to,
    required this.year,
    required this.order,
  });

  final Footprint from;
  final Footprint to;

  /// 该段发生的年份（取 to 的到访时间）。
  final int year;

  /// 全局序号，用于回溯动画定位。
  final int order;
}

/// 一条完整的时间轨迹（按首次到访时间串联所有有坐标的城市）。
class JourneyTrack {
  const JourneyTrack({required this.points, required this.segments});

  /// 有序城市点。
  final List<Footprint> points;
  final List<JourneySegment> segments;

  bool get isEmpty => points.length < 2;
  int get stopCount => points.length;

  List<int> get years {
    final s = <int>{};
    for (final p in points) {
      s.add(p.firstVisitedAt.year);
    }
    final l = s.toList()..sort();
    return l;
  }

  /// 按年份切片：只保留该年发生移动的段，并重建可连续飞行的点序列。
  JourneyTrack forYear(int year) {
    final pts = points.where((p) => p.firstVisitedAt.year == year).toList()
      ..sort((a, b) => a.firstVisitedAt.compareTo(b.firstVisitedAt));
    if (pts.length < 2) {
      // 单城不成线；仍返回点集供上层判断
      return JourneyTrack(points: pts, segments: const []);
    }
    return JourneyTrack(
      points: pts,
      segments: [
        for (var i = 0; i < pts.length - 1; i++)
          JourneySegment(from: pts[i], to: pts[i + 1], year: year, order: i),
      ],
    );
  }

  /// 按「旅程」分组：一次旅行的连续移动才是一条真实路线。
  ///
  /// 【为什么不能靠目的地匹配】一趟旅行往往经过多个城市，
  /// 用 trip.destination 去比对城市名只会命中同名那一座，
  /// 其余城市全被丢掉 → 常常只剩一个点，回溯直接"城市不足"。
  /// 正确来源是 logs → locations 的真实 GPS 轨迹（见 tripRoutesProvider）。
  @Deprecated('靠地名字符串匹配不可靠，改用 tripRoutesProvider')
  Map<String, List<Footprint>> groupedByTrip(List<TripLike> trips) {
    final out = <String, List<Footprint>>{};
    for (final t in trips) {
      final key = stripProvinceSuffix(t.destination);
      final matched = points
          .where((p) => _sameCity(key, p.cityName))
          .toList()
        ..sort((a, b) => a.firstVisitedAt.compareTo(b.firstVisitedAt));
      if (matched.isNotEmpty) out[t.destination] = matched;
    }
    return out;
  }

  static bool _sameCity(String a, String b) {
    final x = cityOf(a) ?? a;
    final y = cityOf(b) ?? b;
    if (x.isEmpty || y.isEmpty) return false;
    return x == y || x.contains(y) || y.contains(x);
  }
}

/// 只暴露需要的字段，避免 provider 依赖具体 DAO 行类型。
abstract class TripLike {
  String get destination;
  DateTime get startDate;
}

/// 轨迹数据来源：足迹 + 旅程名（用于按旅行分组）。
class TripInfo implements TripLike {
  const TripInfo(this.destination, this.startDate);
  @override
  final String destination;
  @override
  final DateTime startDate;
}

final journeyTrackProvider = Provider<JourneyTrack>((ref) {
  final all = ref.watch(footprintListProvider).valueOrNull ?? const <Footprint>[];
  // 只有拿到坐标的点才能连线，否则会把 (0,0) 画到几内亚湾
  final usable = all
      .where((f) => f.latitude != 0 && f.longitude != 0)
      .toList()
    ..sort((a, b) => a.firstVisitedAt.compareTo(b.firstVisitedAt));

  if (usable.length < 2) {
    return const JourneyTrack(points: [], segments: []);
  }
  return JourneyTrack(
    points: usable,
    segments: [
      for (var i = 0; i < usable.length - 1; i++)
        JourneySegment(
          from: usable[i],
          to: usable[i + 1],
          year: usable[i + 1].firstVisitedAt.year,
          order: i,
        ),
    ],
  );
});

/// 可选年份列表（供回溯范围选择）。
final journeyYearsProvider = Provider<List<int>>((ref) {
  final track = ref.watch(journeyTrackProvider);
  return track.years;
});

/// 每条旅程的真实移动路径（logs → locations 的 GPS 点）。
/// 这是"按旅程分段回溯"的唯一可靠数据源。
final tripRoutesProvider = FutureProvider<List<TripRoute>>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.getTripRoutes();
});

/// 待补坐标的城市数量（离线词表与高德都试过之后仍缺的）。
final unresolvedFootprintsProvider = FutureProvider<List<Footprint>>((ref) async {
  final db = ref.watch(databaseProvider);
  // DAO 返回的是 drift 行对象，需映射为模型 Footprint
  final rows = await db.getFootprintsWithoutCoords();
  return rows
      .map((r) => Footprint(
            id: r.id,
            cityName: r.cityName,
            country: r.country,
            latitude: r.latitude,
            longitude: r.longitude,
            firstVisitedAt: r.firstVisitedAt,
            visitCount: r.visitCount,
            latestVisitedAt: r.latestVisitedAt,
          ))
      .toList();
});
