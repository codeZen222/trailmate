import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/achievement_rules.dart';
import '../utils/city_extractor.dart';
import '../utils/geo_coder.dart';
import 'tables/trip_table.dart';
import 'tables/log_table.dart';
import 'tables/image_table.dart';
import 'tables/location_table.dart';
import 'tables/tag_table.dart';
import 'tables/trip_tag_table.dart';
import 'tables/footprint_table.dart';
import 'tables/achievement_table.dart';
import 'tables/settings_table.dart';
import 'tables/expense_table.dart';
import '../models/footprint_route.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Trips,
    Logs,
    Images,
    Locations,
    Tags,
    TripTags,
    Footprints,
    Achievements,
    Settings,
    Expenses,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 测试专用：注入内存库等自定义执行器。
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _seedDefaultTags();
        await _seedDefaultAchievements();
      },
      onUpgrade: (m, from, to) async {
        // v1 → v2：logs 增加 moodTag 列。已有数据保留，旧记录该列为 NULL。
        if (from < 2) {
          await m.addColumn(logs, logs.moodTag);
        }
        // v2 → v3：新增 expenses 表（旅行消费）。纯建表，不动既有数据。
        if (from < 3) {
          await m.createTable(expenses);
        }
        // v3 → v4：achievements 加稀有度列，并播种扩展成就体系。
        // 已解锁的老成就靠 insertOnConflictUpdate 只更新展示字段，
        // 不触碰 unlockedAt，因此用户的进度不会被抹掉。
        if (from < 4) {
          await m.addColumn(achievements, achievements.rarity);
          await _seedDefaultAchievements();
        }
      },
    );
  }

  Future<void> _seedDefaultTags() async {
    final defaultTags = [
      ('度假', '🏖️'),
      ('出差', '💼'),
      ('徒步', '🥾'),
      ('亲子', '👨‍👩‍👧‍👦'),
      ('蜜月', '💕'),
      ('自驾', '🚗'),
      ('美食', '🍜'),
      ('风景', '🏔️'),
      ('文化', '🏛️'),
      ('购物', '🛍️'),
    ];
    for (final (name, icon) in defaultTags) {
      await into(tags).insertOnConflictUpdate(
        TagsCompanion(name: Value(name), icon: Value(icon)),
      );
    }
  }

  /// 按 name 幂等地写入成就定义：
  /// 已存在则只刷新展示字段与规则，**绝不触碰 unlockedAt**（用户进度不丢）；
  /// 不存在才插入。name 上没有唯一索引，所以不能用 insertOnConflictUpdate。
  Future<void> _seedDefaultAchievements() async {
    for (final def in kAchievements) {
      final existing = await (select(achievements)
            ..where((a) => a.name.equals(def.name)))
          .getSingleOrNull();
      if (existing == null) {
        await into(achievements).insert(AchievementsCompanion(
          name: Value(def.name),
          description: Value(def.description),
          icon: Value(def.icon),
          condition: Value(def.rule),
          rarity: Value(def.rarity.key),
        ));
      } else {
        await (update(achievements)..where((a) => a.id.equals(existing.id)))
            .write(AchievementsCompanion(
          description: Value(def.description),
          icon: Value(def.icon),
          // 规则串升级：旧的中文描述条件不参与计算，改为可求值规则
          condition: Value(def.rule),
          rarity: Value(def.rarity.key),
        ));
      }
    }
  }

  // ---- Trips ----

  Future<int> insertTrip(TripsCompanion trip) => into(trips).insert(trip);

  /// 局部更新旅程，返回受影响行数。id 必须显式传入。
  ///
  /// 【不要用 update(trips).replace(companion)】
  /// drift 的 `replace()` 要求**整行所有非默认列齐备**，缺任何一个
  /// （如 createdAt）会抛 InvalidDataException，导致保存彻底失败。
  /// 局部更新必须走 `update()..where().write()`，它只写传入的列。
  Future<int> updateTrip(int id, TripsCompanion companion) =>
      (update(trips)..where((t) => t.id.equals(id))).write(TripsCompanion(
        destination: companion.destination,
        coverPath: companion.coverPath,
        startDate: companion.startDate,
        endDate: companion.endDate,
        rating: companion.rating,
        notes: companion.notes,
        isCompleted: companion.isCompleted,
        updatedAt: companion.updatedAt,
      ));

  Future<void> deleteTrip(int id) =>
      (delete(trips)..where((t) => t.id.equals(id))).go();

  /// 删除旅程，并把该旅程在足迹上点亮的「一次到访」减回去。
  ///
  /// 【为什么要显式做两件事】
  /// 1. logs / expenses / trip_tags 的外键级联依赖连接开启 foreign_keys；
  ///    老用户的库可能创建于开启之前，这里显式删一遍，保证行为与连接配置无关。
  /// 2. footprints 与 trips **没有外键关系**：创建旅程时按目的地城市点亮一次
  ///    （visitCount++），删除旅程时若不做对应扣减，城市就会永远亮着、
  ///    次数也降不下来 —— 这正是用户报的 bug。
  ///
  /// 返回被删除旅程关联的图片文件路径（封面 + 日志配图），
  /// 由调用方决定何时清理磁盘文件（不能在事务里删，见下）。
  Future<List<String>> deleteTripCascade(int tripId) async {
    final trip = await getTripById(tripId);
    if (trip == null) return const [];

    // 先收集要扣足迹的城市与要清理的图片，再进事务。
    final city = CityExtractor.extract(trip.destination).city;
    // 排除本次旅程后该城市还剩哪些到访（用于重算首访/最近到访）。
    // 必须在删除前查：此刻 trips 行还在，但 excludeTripId 会跳过它。
    final remainingVisits = await _visitsOfCityExcluding(city, tripId);
    final logRows = await (select(logs)..where((l) => l.tripId.equals(tripId))).get();
    final logIds = logRows.map((l) => l.id).toList();
    final paths = <String>{
      if ((trip.coverPath ?? '').isNotEmpty) trip.coverPath!,
    };
    if (logIds.isNotEmpty) {
      final q = select(images)..where((i) => i.logId.isIn(logIds));
      for (final r in await q.get()) {
        paths.add(r.filePath);
      }
    }

    // 事务：旅程及其全部附属数据要么一起消失，要么都还在。
    await transaction(() async {
      if (logIds.isNotEmpty) {
        // locations 随日志级联；images 显式删，避免留下指向已删日志的孤儿行。
        await (delete(images)..where((i) => i.logId.isIn(logIds))).go();
        await (delete(locations)..where((l) => l.logId.isIn(logIds))).go();
        await (delete(logs)..where((l) => l.tripId.equals(tripId))).go();
      }
      await (delete(expenses)..where((e) => e.tripId.equals(tripId))).go();
      await (delete(tripTags)..where((t) => t.tripId.equals(tripId))).go();
      await (delete(trips)..where((t) => t.id.equals(tripId))).go();
      await _unlightFootprint(city, remainingVisits);
    });

    return paths.toList();
  }

  /// 扣掉一次到访：次数减一，归零则熄灭该城市。
  ///
  /// 【为什么只动一条候选记录】同一城市可能因历史脏数据存在多行
  /// （区县级未归并等），取最近更新的那条扣减即可 —— 足迹表本来就按
  /// 城市聚合、不记录来源旅程，无法精确知道哪次点亮出自这趟。
  ///
  /// 【必须在事务内调用】remainingVisits 是删除前查到的"其它旅程到访日"，
  /// 与本次删除同属一个原子操作；放到事务外会让扣减和删除脱节。
  Future<void> _unlightFootprint(
      String city, List<DateTime> remainingVisits) async {
    if (city.isEmpty || city == '未知') return;
    final fp = await (select(footprints)
          ..where((f) => f.cityName.equals(city))
          ..orderBy([(f) => OrderingTerm.desc(f.latestVisitedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (fp == null) return; // 从未点亮过（如词表升级前的老旅程），无需扣减

    final newCount = fp.visitCount - 1;
    if (newCount <= 0) {
      await (delete(footprints)..where((f) => f.id.equals(fp.id))).go();
      return;
    }

    // 首访/最近到访用剩余旅程重算，否则删掉最早那次后时间戳仍停在旧值。
    await (update(footprints)..where((f) => f.id.equals(fp.id))).write(
      FootprintsCompanion(
        visitCount: Value(newCount),
        firstVisitedAt: remainingVisits.isEmpty
            ? const Value.absent()
            : Value(remainingVisits.first),
        latestVisitedAt: remainingVisits.isEmpty
            ? const Value.absent()
            : Value(remainingVisits.last),
      ),
    );
  }

  /// 某城市全部旅程的开始日期（升序），排除 excludeTripId（自身）。
  /// 须在删除该旅程**之前**调用。
  Future<List<DateTime>> _visitsOfCityExcluding(
      String city, int? excludeTripId) async {
    if (city.isEmpty) return const [];
    final out = <DateTime>[];
    for (final t in await getAllTrips()) {
      if (excludeTripId != null && t.id == excludeTripId) continue;
      if (CityExtractor.extract(t.destination).city == city) {
        out.add(t.startDate);
      }
    }
    out.sort();
    return out;
  }

  Future<List<Trip>> getAllTrips() => (select(trips)
        ..orderBy([
          (t) => OrderingTerm.asc(t.startDate),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .get();

  /// 按开始日期**正序**（最早去过的在最前，像日记一样从头翻）。
  /// 同日再按 id 正序保证顺序稳定。
  /// 注意：此前没有任何 orderBy，返回的是 rowid（创建先后）顺序。
  /// 依赖"最近旅程在前"的调用方不要依赖本列表的位置，应自行按日期取最大值。
  Stream<List<Trip>> watchAllTrips() => (select(trips)
        ..orderBy([
          (t) => OrderingTerm.asc(t.startDate),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .watch();
  Future<Trip?> getTripById(int id) =>
      (select(trips)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Trip>> searchTrips(String query) {
    return (select(trips)
      ..where((t) => t.destination.contains(query) | t.notes.contains(query)))
      .get();
  }

  /// 目的地包含该城市名的旅程（用于城市详情关联列表）。
  Future<List<Trip>> getTripsByCity(String cityName) {
    return (select(trips)
      ..where((t) => t.destination.contains(cityName))
      ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
      .get();
  }

  /// 该城市可展示的照片：**旅程封面 + 各日志图片**合并去重，默认最多 6 张。
  ///
  /// 【为什么不只取日志首图】之前每篇日志只贡献第 1 张，且完全忽略旅程封面，
  /// 导致点城市看图时"只能看到日志里的、看不到另一些"。用户要求两类都要。
  /// 排序策略：先放旅程封面（最能代表这趟），再按日期倒序铺日志图。
  Future<List<String>> getRecentCoverImagesByCity(
    String cityName, {
    int limit = 6,
  }) async {
    final cityTrips = await getTripsByCity(cityName);
    if (cityTrips.isEmpty) return const [];

    final out = <String>[];
    final seen = <String>{};
    void add(String? path) {
      if (path == null || path.isEmpty) return;
      if (seen.contains(path)) return;
      seen.add(path);
      out.add(path);
    }

    // 1) 旅程封面优先
    for (final t in cityTrips) {
      if (out.length >= limit) break;
      add(t.coverPath);
    }

    // 2) 汇总该城市所有旅程下的日志
    final allLogs = <Log>[];
    for (final t in cityTrips) {
      allLogs.addAll(await (select(logs)..where((l) => l.tripId.equals(t.id))).get());
    }
    if (allLogs.isEmpty) return out;

    // 3) 全局按日志日期倒序（同一天再按创建时间倒序）
    allLogs.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });

    // 4) 逐篇把图片补进来；单篇最多取 2 张，避免一次连拍占满额度
    const perLogCap = 2;
    for (final log in allLogs) {
      if (out.length >= limit) break;
      final imgs = await (select(images)
            ..where((i) => i.logId.equals(log.id))
            ..orderBy([(i) => OrderingTerm.asc(i.orderIndex), (i) => OrderingTerm.asc(i.id)]))
          .get();
      for (var i = 0; i < imgs.length && i < perLogCap; i++) {
        if (out.length >= limit) break;
        add(imgs[i].filePath);
      }
    }
    return out;
  }

  // ---- Logs ----

  Future<int> insertLog(LogsCompanion log) => into(logs).insert(log);
  /// 局部更新日志，返回受影响行数。id 必须显式传入。
  /// 同 updateTrip：不能用 replace()，它要求整行齐备（含 createdAt），
  /// 缺列会抛 InvalidDataException 使保存静默失败。
  Future<int> updateLog(int id, LogsCompanion companion) =>
      (update(logs)..where((l) => l.id.equals(id))).write(LogsCompanion(
        tripId: companion.tripId,
        date: companion.date,
        title: companion.title,
        content: companion.content,
        weather: companion.weather,
        moodTag: companion.moodTag,
        rating: companion.rating,
        updatedAt: companion.updatedAt,
      ));

  Future<void> deleteLog(int id) =>
      (delete(logs)..where((l) => l.id.equals(id))).go();
  Future<List<Log>> getLogsByTrip(int tripId) =>
      (select(logs)..where((l) => l.tripId.equals(tripId))).get();
  Stream<List<Log>> watchLogsByTrip(int tripId) =>
      (select(logs)..where((l) => l.tripId.equals(tripId))).watch();
  Future<Log?> getLogById(int id) =>
      (select(logs)..where((l) => l.id.equals(id))).getSingleOrNull();

  /// 全部日志条数（档案统计用）。
  Future<int> getLogCount() async => (select(logs).get()).then((l) => l.length);

  /// 全部日志（成就指标计算用）。
  Future<List<Log>> getAllLogs() => select(logs).get();

  // ---- Images ----

  Future<int> insertImage(ImagesCompanion image) => into(images).insert(image);
  Future<List<Image>> getImagesByLog(int logId) =>
      (select(images)..where((i) => i.logId.equals(logId))).get();
  Future<void> deleteImage(int id) =>
      (delete(images)..where((i) => i.id.equals(id))).go();
  Future<int> getImageCount() => (select(images)).get().then((l) => l.length);

  /// 某旅程下的全部照片（跨日志），按时间升序。
  Future<List<Image>> getImagesByTrip(int tripId) async {
    final q = select(images).join([
      innerJoin(logs, logs.id.equalsExp(images.logId)),
    ])
      ..where(logs.tripId.equals(tripId))
      ..orderBy([OrderingTerm.asc(images.createdAt)]);
    return (await q.get()).map((r) => r.readTable(images)).toList();
  }

  /// 某旅程去重后的城市集合（来自日志的 GPS 定位记录）。
  Future<List<String>> getCitiesByTrip(int tripId) async {
    final q = select(locations).join([
      innerJoin(logs, logs.id.equalsExp(locations.logId)),
    ])
      ..where(logs.tripId.equals(tripId));
    final rows = await q.get();
    final set = <String>{};
    for (final r in rows) {
      final c = r.readTable(locations).cityName;
      if (c != null && c.trim().isNotEmpty) set.add(c.trim());
    }
    return set.toList();
  }

  /// 按展示顺序取某日志的图片。
  Future<List<Image>> getImagesByLogOrdered(int logId) => (select(images)
        ..where((i) => i.logId.equals(logId))
        ..orderBy([(i) => OrderingTerm.asc(i.orderIndex), (i) => OrderingTerm.asc(i.id)]))
      .get();

  /// 仅更新排序位，保留 aiDescription / 坐标等其它字段。
  Future<void> setImageOrder(int id, int order) =>
      (update(images)..where((i) => i.id.equals(id)))
          .write(ImagesCompanion(orderIndex: Value(order)));

  /// 按文件路径写入 AI 描述（同一张图可能出现在多篇日志，故逐行更新）。
  /// 供"描述图片"功能在编辑过程中即时保存，不依赖整篇日志的保存动作。
  Future<int> setImageDescriptionByPath(String path, String description) =>
      (update(images)..where((i) => i.filePath.equals(path)))
          .write(ImagesCompanion(aiDescription: Value(description)));

  /// 让某日志的图片顺序与编辑器列表一致：删除已移除的、新增未入库的、修正顺序。
  /// 返回处理条数（用于提示）。
  Future<void> syncLogImages(int logId, List<String> paths) async {
    final existing = await getImagesByLogOrdered(logId);
    final byPath = {for (final e in existing) e.filePath: e};

    // 1) 编辑器里已删除的 → 从数据库移除（不删磁盘文件，避免误删共享图）
    for (final e in existing) {
      if (!paths.contains(e.filePath)) await deleteImage(e.id);
    }

    // 2) 按当前顺序插入或纠正 orderIndex
    for (var i = 0; i < paths.length; i++) {
      final p = paths[i];
      final old = byPath[p];
      if (old == null) {
        await insertImage(ImagesCompanion(
          logId: Value(logId),
          filePath: Value(p),
          orderIndex: Value(i),
          createdAt: Value(DateTime.now()),
        ));
      } else if (old.orderIndex != i) {
        await setImageOrder(old.id, i);
      }
    }
  }

  // ---- Locations ----

  Future<int> insertLocation(LocationsCompanion location) =>
      into(locations).insert(location);
  Future<Location?> getLocationByLog(int logId) =>
      (select(locations)..where((l) => l.logId.equals(logId))).getSingleOrNull();

  /// 写入/更新某条日志的位置（logId 唯一）。传 null 坐标则不处理。
  Future<void> upsertLocationForLog({
    required int logId,
    required double latitude,
    required double longitude,
    String? cityName,
    String? placeName,
    String? address,
  }) async {
    await into(locations).insert(
      LocationsCompanion.insert(
        logId: logId,
        latitude: latitude,
        longitude: longitude,
        cityName: Value(cityName),
        placeName: Value(placeName),
        address: Value(address),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  // ---- Tags ----

  Future<int> insertTag(TagsCompanion tag) => into(tags).insert(tag);
  Future<List<Tag>> getAllTags() => select(tags).get();

  // ---- TripTags ----

  Future<void> setTripTags(int tripId, List<int> tagIds) async {
    await (delete(tripTags)..where((t) => t.tripId.equals(tripId))).go();
    for (final tagId in tagIds) {
      await into(tripTags).insert(TripTagsCompanion(
        tripId: Value(tripId),
        tagId: Value(tagId),
      ));
    }
  }

  Future<List<Tag>> getTagsByTrip(int tripId) {
    return (select(tags).join([
      innerJoin(tripTags, tripTags.tagId.equalsExp(tags.id)),
    ])..where(tripTags.tripId.equals(tripId)))
        .map((row) => row.readTable(tags))
        .get();
  }

  /// 按名字找标签，没有就创建（返回 id）。
  Future<int> findOrCreateTag(String name, {String? icon}) async {
    final existing = await (select(tags)..where((t) => t.name.equals(name))).getSingleOrNull();
    if (existing != null) return existing.id;
    return into(tags).insert(TagsCompanion(
      name: Value(name),
      icon: Value(icon ?? '🏷️'),
    ));
  }

  /// 把一组标签追加到旅程（去重，不清空已有）。
  Future<void> appendTripTags(int tripId, List<String> names) async {
    final current = await getTagsByTrip(tripId);
    final ids = current.map((t) => t.id).toSet();
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      final id = await findOrCreateTag(trimmed);
      ids.add(id);
    }
    await setTripTags(tripId, ids.toList());
  }

  // ---- Footprints ----

  Future<void> upsertFootprint(FootprintsCompanion footprint) async {
    final existing = await (select(footprints)
      ..where((f) => f.cityName.equals(footprint.cityName.value)))
        .getSingleOrNull();

    if (existing != null) {
      await update(footprints).replace(Footprint(
        id: existing.id,
        cityName: existing.cityName,
        country: existing.country,
        // 【不能无条件保留旧坐标】老记录可能当初查不到而写成 (0,0)，
        // 之后词表扩充或高德兜底已能解析，若仍沿用旧值就永远修不好。
        latitude: existing.latitude == 0 && footprint.latitude.value != 0
            ? footprint.latitude.value
            : existing.latitude,
        longitude: existing.longitude == 0 && footprint.longitude.value != 0
            ? footprint.longitude.value
            : existing.longitude,
        firstVisitedAt: existing.firstVisitedAt,
        visitCount: existing.visitCount + 1,
        latestVisitedAt: footprint.latestVisitedAt.value,
      ));
    } else {
      await into(footprints).insert(footprint);
    }
  }

  /// 把一条足迹改名并入另一条（区县级 -> 所属地级市），累加次数、取更早首访。
  /// 返回是否真的发生了合并。
  Future<bool> mergeFootprintInto(int fromId, int intoId) async {
    final rows = await (select(footprints)
          ..where((f) => f.id.isIn([fromId, intoId])))
        .get();
    if (rows.length != 2) return false;
    final from = rows.firstWhere((r) => r.id == fromId);
    final into = rows.firstWhere((r) => r.id == intoId);
    await (update(footprints)..where((f) => f.id.equals(intoId))).write(
      FootprintsCompanion(
        visitCount: Value(into.visitCount + from.visitCount),
        firstVisitedAt: Value(
            from.firstVisitedAt.isBefore(into.firstVisitedAt)
                ? from.firstVisitedAt
                : into.firstVisitedAt),
        latestVisitedAt: Value(from.latestVisitedAt.isAfter(into.latestVisitedAt)
            ? from.latestVisitedAt
            : into.latestVisitedAt),
        latitude: Value(into.latitude == 0 ? from.latitude : into.latitude),
        longitude: Value(into.longitude == 0 ? from.longitude : into.longitude),
      ),
    );
    await (delete(footprints)..where((f) => f.id.equals(fromId))).go();
    return true;
  }

  /// 清理孤儿行：外键长期未开启期间，删除旅程只删了 trips 一行，
  /// 日志 / 消费 / 图片 / 定位 / 标签关联留在库里继续参与统计。
  /// 返回删除的总行数。启动修复专用，自带事务。
  Future<int> deleteOrphanRows() => transaction(() async {
        // 不能用 `!liveTrips.contains(col)`：闭包里的列是 Expression，
        // contains 会走 Dart 的 Iterable 语义并返回 bool，drift 编译不过。
        // 先把主键读成集合，再用 isNotIn 过滤。
        final liveTrips = (await select(trips).get()).map((t) => t.id).toSet();
        // liveLogs 必须在删 logs 之前抓全：images / locations 的外键指向它。
        final liveLogIds = (await select(logs).get())
            .where((l) => liveTrips.contains(l.tripId))
            .map((l) => l.id)
            .toSet();

        var n = 0;
        // 【顺序要紧】先清叶子（消费、标签关联），再清 images/locations，
        // 最后才删 logs —— 开了外键的库若反过来删，会被直接拒绝。
        if (liveTrips.isNotEmpty) {
          n += await (delete(expenses)..where((e) => e.tripId.isNotIn(liveTrips.toList()))).go();
          n += await (delete(tripTags)..where((t) => t.tripId.isNotIn(liveTrips.toList()))).go();
        } else {
          n += await delete(expenses).go();
          n += await delete(tripTags).go();
        }
        if (liveLogIds.isNotEmpty) {
          n += await (delete(images)..where((i) => i.logId.isNotIn(liveLogIds.toList()))).go();
          n += await (delete(locations)..where((l) => l.logId.isNotIn(liveLogIds.toList()))).go();
        } else {
          n += await delete(images).go();
          n += await delete(locations).go();
        }
        n += await (delete(logs)..where((l) => l.id.isNotIn(liveLogIds.toList()))).go();
        return n;
      });

  Stream<List<Footprint>> watchAllFootprints() => select(footprints).watch();
  Future<List<Footprint>> getAllFootprints() => select(footprints).get();
  Future<int> getFootprintCount() =>
      select(footprints).get().then((l) => l.length);

  /// 坐标缺失（历史遗留：城市不在离线坐标表里）的足迹，供"补坐标"入口列出。
  Future<List<Footprint>> getFootprintsWithoutCoords() => (select(footprints)
        ..where((f) => f.latitude.equals(0) & f.longitude.equals(0))
        ..orderBy([(f) => OrderingTerm.desc(f.latestVisitedAt)]))
      .get();

  /// 手动修正某个足迹的坐标。
  Future<int> setFootprintCoords(int id, double lat, double lon) =>
      (update(footprints)..where((f) => f.id.equals(id))).write(
        FootprintsCompanion(
          latitude: Value(lat),
          longitude: Value(lon),
        ),
      );

  /// 用（可能已扩充的）离线词表回填此前写成 (0,0) 的足迹坐标。
  ///
  /// 【为什么需要】坐标是在创建旅程那一刻写死的。之后词表扩充了，
  /// 老记录却仍是 (0,0)，城市就永远上不了图。启动时跑一次可自愈。
  Future<int> backfillFootprintCoords() async {
    final rows = await (select(footprints)
          ..where((f) => f.latitude.equals(0) & f.longitude.equals(0)))
        .get();
    var fixed = 0;
    for (final f in rows) {
      final hit = GeoCoder.lookup(f.cityName);
      if (hit == null) continue;
      await setFootprintCoords(f.id, hit.lat, hit.lon);
      fixed++;
    }
    return fixed;
  }

  /// 每次旅程的真实移动路径（按日志日期顺序取其 GPS 点）。
  /// 只保留至少 2 个点的旅程，否则连不成线。
  Future<List<TripRoute>> getTripRoutes({int? year}) async {
    final ts = await getAllTrips();
    final routes = <TripRoute>[];
    for (final t in ts) {
      if (year != null && t.startDate.year != year) continue;
      final ls = await (select(logs)
            ..where((l) => l.tripId.equals(t.id))
            ..orderBy([(l) => OrderingTerm.asc(l.date)]))
          .get();
      final pts = <RoutePoint>[];
      for (final l in ls) {
        final loc = await getLocationByLog(l.id);
        if (loc == null) continue;
        if (loc.latitude == 0 && loc.longitude == 0) continue;
        final p = RoutePoint(loc.latitude, loc.longitude, loc.cityName ?? '');
        // 相邻重复坐标去重（同一天多次定位在同一点）
        if (pts.isEmpty || pts.last.key != p.key) pts.add(p);
      }
      if (pts.length >= 2) {
        routes.add(TripRoute(
          tripId: t.id,
          destination: t.destination,
          startDate: t.startDate,
          points: pts,
        ));
      }
    }
    return routes;
  }

  /// 某城市的消费合计（分）：目的地含该城市名的所有旅程之和。
  Future<int> getExpenseCentsByCity(String cityName) async {
    final cityTrips = await getTripsByCity(cityName);
    if (cityTrips.isEmpty) return 0;
    final ids = cityTrips.map((t) => t.id).toSet();
    final rows = await (select(expenses)
          ..where((x) => x.tripId.isIn(ids.toList())))
        .get();
    return rows.fold<int>(0, (s, x) => s + x.amountCents);
  }

  // ---- Achievements ----

  Stream<List<Achievement>> watchAllAchievements() =>
      select(achievements).watch();
  Stream<List<Achievement>> watchUnlockedAchievements() =>
      (select(achievements)..where((a) => a.unlockedAt.isNotNull())).watch();
  Future<int> getUnlockedCount() async =>
      (select(achievements)..where((a) => a.unlockedAt.isNotNull()))
          .get()
          .then((list) => list.length);

  /// 成就总数（档案卡「已解锁 x/y」用）。
  Future<int> getAchievementCount() async =>
      select(achievements).get().then((list) => list.length);

  /// 一次性取全部成就（含解锁时间），供年度回顾聚合用。
  Future<List<Achievement>> getAchievements() => select(achievements).get();

  /// 用规则引擎重算全部成就。返回**本次新解锁**的成就名，供界面做提示。
  ///
  /// 旧实现是一串硬编码 if + 中文 condition；现在 condition 存的是可求值规则串
  /// （如 `cities>=10`），新增成就只需往 kAchievements 加一条定义。
  Future<List<({String name, String icon})>> checkAchievements() async {
    final rows = await select(achievements).get();
    if (rows.isEmpty) return const [];

    final profileRaw = await getSetting('user_profile');
    Map<String, dynamic>? profileJson;
    if (profileRaw != null && profileRaw.isNotEmpty) {
      try {
        final d = jsonDecode(profileRaw);
        if (d is Map<String, dynamic>) profileJson = d;
      } catch (_) {
        profileJson = null;
      }
    }

    final metrics =
        await AchievementMetrics.compute(this, profileJson: profileJson);

    final newly = <({String name, String icon})>[];
    for (final a in rows) {
      if (a.unlockedAt != null) continue; // 已解锁不再重复判定
      final rule = AchievementRule.parse(a.condition);
      if (rule == null) continue; // 旧中文条件：跳过，等下次播种时被替换
      if (rule.test(metrics)) {
        await (update(achievements)..where((t) => t.id.equals(a.id)))
            .write(AchievementsCompanion(unlockedAt: Value(DateTime.now())));
        newly.add((name: a.name, icon: a.icon));
      }
    }
    return newly;
  }

  /// 各成就的当前进度（0..1）与"还差多少"文案，供成就页展示。
  Future<Map<int, ({double progress, String hint})>> achievementProgress() async {
    final rows = await select(achievements).get();
    final profileRaw = await getSetting('user_profile');
    Map<String, dynamic>? profileJson;
    if (profileRaw != null && profileRaw.isNotEmpty) {
      try {
        final d = jsonDecode(profileRaw);
        if (d is Map<String, dynamic>) profileJson = d;
      } catch (_) {}
    }
    final metrics =
        await AchievementMetrics.compute(this, profileJson: profileJson);

    final out = <int, ({double progress, String hint})>{};
    for (final a in rows) {
      final rule = AchievementRule.parse(a.condition);
      if (rule == null) {
        out[a.id] = (progress: 0.0, hint: a.condition);
        continue;
      }
      if (a.unlockedAt != null) {
        out[a.id] = (progress: 1.0, hint: '已达成');
        continue;
      }
      final cur = metrics.of(rule.metric);
      final left = (rule.target - cur).ceil();
      out[a.id] = (
        progress: rule.progress(metrics),
        hint: left <= 0 ? '即将达成' : '还差 $left',
      );
    }
    return out;
  }

  /// 记录一个行为标记成就（如"用精灵记过账"）。
  Future<void> markAchievementFlag(String key) => setSetting('ach_flag_$key', '1');

  // ---- Settings ----

  Future<void> setSetting(String key, String value) async {
    await into(settings).insert(
      SettingsCompanion(key: Value(key), value: Value(value)),
      mode: InsertMode.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final row = await (select(settings)
      ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  // ---- Expenses ----

  Future<int> insertExpense(ExpensesCompanion e) => into(expenses).insert(e);

  /// 局部更新消费记录（同 updateLog：不要用 replace()，它要求整行齐备）。
  Future<int> updateExpense(int id, ExpensesCompanion companion) =>
      (update(expenses)..where((e) => e.id.equals(id))).write(ExpensesCompanion(
        tripId: companion.tripId,
        logId: companion.logId,
        category: companion.category,
        amountCents: companion.amountCents,
        note: companion.note,
        expenseDate: companion.expenseDate,
      ));

  Future<void> deleteExpense(int id) =>
      (delete(expenses)..where((e) => e.id.equals(id))).go();

  Future<Expense?> getExpenseById(int id) =>
      (select(expenses)..where((e) => e.id.equals(id))).getSingleOrNull();

  /// 全部消费，按消费日期倒序（同日按创建时间倒序）。
  Future<List<Expense>> getAllExpenses() => (select(expenses)
        ..orderBy([
          (e) => OrderingTerm.desc(e.expenseDate),
          (e) => OrderingTerm.desc(e.id),
        ]))
      .get();

  Stream<List<Expense>> watchAllExpenses() => (select(expenses)
        ..orderBy([
          (e) => OrderingTerm.desc(e.expenseDate),
          (e) => OrderingTerm.desc(e.id),
        ]))
      .watch();

  Future<List<Expense>> getExpensesByTrip(int tripId) => (select(expenses)
        ..where((e) => e.tripId.equals(tripId))
        ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]))
      .get();

  Stream<List<Expense>> watchExpensesByTrip(int tripId) => (select(expenses)
        ..where((e) => e.tripId.equals(tripId))
        ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]))
      .watch();

  Future<int> getExpenseCount() =>
      select(expenses).get().then((l) => l.length);

  /// 某旅程的消费总额（分）。
  Future<int> getTripTotalCents(int tripId) async {
    final list = await getExpensesByTrip(tripId);
    return list.fold<int>(0, (s, e) => s + e.amountCents);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'trailmate.db'));
    // 【必须显式开启外键】SQLite 的 PRAGMA foreign_keys 是**按连接**生效、
    // 默认关闭。不打开它的话 logs / expenses / trip_tags 上声明的
    // onDelete: cascade 全是摆设 —— 删旅程只删了 trips 一行，
    // 日志和消费记录留在库里继续参与统计。
    return NativeDatabase(file, setup: (db) => db.execute('PRAGMA foreign_keys = ON;'));
  });
}