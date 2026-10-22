import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart' as db;
import '../models/trip_model.dart';
import '../services/amap_geocoding_service.dart';
import '../utils/city_extractor.dart';
import '../utils/geo_coder.dart';
import 'achievement_provider.dart';
import 'database_provider.dart';
import 'journey_provider.dart';
import 'profile_provider.dart';

// 使用 as db 前缀避免与模型类名冲突

final tripListProvider = StreamProvider<List<Trip>>((ref) {
  final database = ref.watch(databaseProvider);
  return database.watchAllTrips().map((rows) => rows.map((r) => Trip(
    id: r.id,
    destination: r.destination,
    coverPath: r.coverPath,
    startDate: r.startDate,
    endDate: r.endDate,
    rating: r.rating,
    notes: r.notes,
    isCompleted: r.isCompleted,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  )).toList());
});

final tripByIdProvider = FutureProvider.family<Trip?, int>((ref, id) async {
  final database = ref.watch(databaseProvider);
  final r = await database.getTripById(id);
  if (r == null) return null;
  return Trip(
    id: r.id,
    destination: r.destination,
    coverPath: r.coverPath,
    startDate: r.startDate,
    endDate: r.endDate,
    rating: r.rating,
    notes: r.notes,
    isCompleted: r.isCompleted,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );
});

Future<void> createTrip(WidgetRef ref, {
  required String destination,
  String? coverPath,
  required DateTime startDate,
  required DateTime endDate,
  String? notes,
  List<int> tagIds = const [],
  // 没选结束日期时传 false，旅程会显示为"进行中"而不是伪造一个归期。
  bool isCompleted = true,
}) async {
  final database = ref.read(databaseProvider);
  final now = DateTime.now();
  final id = await database.insertTrip(db.TripsCompanion(
    destination: Value(destination),
    coverPath: Value(coverPath),
    startDate: Value(startDate),
    endDate: Value(endDate),
    notes: Value(notes),
    isCompleted: Value(isCompleted),
    createdAt: Value(now),
    updatedAt: Value(now),
  ));
  if (tagIds.isNotEmpty) {
    await database.setTripTags(id, tagIds);
  }

  // Phase 2.1：新旅程自动点亮城市足迹
  await _lightUpFootprint(database, destination, startDate);
}

/// 从目的地解析城市并写入 footprints（已存在则 visitCount++）。
Future<void> _lightUpFootprint(
  db.AppDatabase database,
  String destination,
  DateTime visitedAt,
) async {
  final (:city, :country) = CityExtractor.extract(destination);
  if (city.isEmpty) return;
  var coords = GeoCoder.lookup(city);
  // 离线词表只有约 300 个地名，县级/新区会漏；漏了就交给高德 Web 服务。
  // 否则坐标写成 (0,0)，该城市既不上图也进不了连线（济阳当初就是这么丢的）。
  if (coords == null && country == '中国') {
    final p = await _amapLocate(database, city);
    if (p != null) coords = (lat: p.latitude, lon: p.longitude);
  }
  await database.upsertFootprint(db.FootprintsCompanion(
    cityName: Value(city),
    country: Value(country),
    latitude: Value(coords?.lat ?? 0),
    longitude: Value(coords?.lon ?? 0),
    firstVisitedAt: Value(visitedAt),
    latestVisitedAt: Value(DateTime.now()),
  ));
}

/// 借用地理编码服务，但不引入 provider（这里是过程式调用链）。
Future<({double latitude, double longitude})?> _amapLocate(
    db.AppDatabase database, String name) async {
  try {
    final svc = AmapGeocodingService(database);
    final p = await svc.locate(name);
    if (p == null) return null;
    return (latitude: p.latitude, longitude: p.longitude);
  } catch (_) {
    return null;
  }
}

Future<void> updateTrip(WidgetRef ref, Trip trip) async {
  final database = ref.read(databaseProvider);
  final changed = await database.updateTrip(trip.id, db.TripsCompanion(
    destination: Value(trip.destination),
    coverPath: Value(trip.coverPath),
    startDate: Value(trip.startDate),
    endDate: Value(trip.endDate),
    rating: Value(trip.rating),
    notes: Value(trip.notes),
    isCompleted: Value(trip.isCompleted),
    updatedAt: Value(DateTime.now()),
  ));
  if (changed == 0) {
    throw StateError('未找到要更新的旅程（id=${trip.id}），本次未保存任何内容');
  }
}

/// 删除旅程，并同步清掉它带来的一切痕迹：
/// 日志/图片/消费/标签关联（数据库层）+ 足迹点亮次数 + 磁盘上的图片文件。
///
/// 【为什么不能只删 trips 行】footprints 表与 trips 没有外键关系，
/// 城市是创建旅程时按目的地逐个点亮的；不显式扣减的话，
/// 删完旅程地图上城市还亮着、统计里的旅行消费也还在 —— 用户报的正是这个。
Future<void> deleteTrip(WidgetRef ref, int tripId) async {
  final database = ref.read(databaseProvider);
  final imagePaths = await database.deleteTripCascade(tripId);

  // StreamProvider 会随表变更自动重推数据；FutureProvider 不会，需手动失效。
  ref.invalidate(todayMemoryProvider);
  ref.invalidate(tripRoutesProvider);
  ref.invalidate(profileStatsProvider);
  ref.invalidate(achievementsWithProgressProvider);

  // 磁盘清理放在事务外：删失败不影响数据一致性，静默即可。
  for (final path in imagePaths) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

final searchQueryProvider = StateProvider<String>((ref) => '');

/// 「今日回忆」：历史上的今天（同月同日）的旅程，优先取往年的。
final todayMemoryProvider = FutureProvider<Trip?>((ref) async {
  final database = ref.watch(databaseProvider);
  final trips = await database.getAllTrips();
  if (trips.isEmpty) return null;
  final now = DateTime.now();
  final candidates = trips.where((t) {
    // 落在 [startDate, endDate] 区间内且不是今年
    final inRange = !now.isBefore(t.startDate) && !now.isAfter(t.endDate);
    return inRange && t.startDate.year != now.year;
  }).toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
  if (candidates.isNotEmpty) {
    return Trip(
      id: candidates.first.id,
      destination: candidates.first.destination,
      coverPath: candidates.first.coverPath,
      startDate: candidates.first.startDate,
      endDate: candidates.first.endDate,
      rating: candidates.first.rating,
      notes: candidates.first.notes,
      isCompleted: candidates.first.isCompleted,
      createdAt: candidates.first.createdAt,
      updatedAt: candidates.first.updatedAt,
    );
  }
  return null;
});

final searchResultsProvider = FutureProvider.family<List<Trip>, String>((ref, query) async {
  if (query.isEmpty) return [];
  final database = ref.watch(databaseProvider);
  final results = await database.searchTrips(query);
  return results.map((r) => Trip(
    id: r.id,
    destination: r.destination,
    coverPath: r.coverPath,
    startDate: r.startDate,
    endDate: r.endDate,
    rating: r.rating,
    notes: r.notes,
    isCompleted: r.isCompleted,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  )).toList();
});