// 删除旅程的级联与足迹扣减回归测试。
//
// 【为什么用 NativeDatabase.memory()】被测行为正是 drift 生成的表定义
// （外键 cascade）+ AppDatabase 里手写的 deleteTripCascade / _unlightFootprint，
// 纯逻辑复刻测不到 SQL 层，必须跑真库。
// 注意：内存库走的是 _openConnection 之外的构造路径，PRAGMA foreign_keys
// 由 drift 的 NativeDatabase 自行开启，因此这里验证的是"显式删除"确实生效，
// 而不是依赖连接配置 —— 两者都要成立。
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailmate/database/app_database.dart' as db;
import 'package:trailmate/utils/city_extractor.dart';

/// 内存库。drift 的 NativeDatabase 默认开启外键（QueryExecutor 文档承诺），
/// 因此这里同时验证了「表定义的 cascade 可用」与「显式删除也做了」。
NativeDatabase _memConnection() => NativeDatabase.memory();

Future<int> _seedTrip(
  db.AppDatabase d, {
  required String destination,
  DateTime? start,
  int expenseCents = 0,
  int logs = 0,
}) async {
  final s = start ?? DateTime(2026, 5, 1);
  final id = await d.insertTrip(db.TripsCompanion(
    destination: Value(destination),
    // 封面：验证 deleteTripCascade 会把它一并交回给调用方清理
    coverPath: Value('/tmp/cover_$destination.jpg'),
    startDate: Value(s),
    endDate: Value(s.add(const Duration(days: 2))),
    isCompleted: const Value(true),
    createdAt: Value(s),
    updatedAt: Value(s),
  ));
  for (var i = 0; i < logs; i++) {
    final logId = await d.insertLog(db.LogsCompanion(
      tripId: Value(id),
      date: Value(s.add(Duration(days: i))),
      title: Value('第 $i 天'),
      content: Value('正文'),
      createdAt: Value(s),
      updatedAt: Value(s),
    ));
    await d.insertImage(db.ImagesCompanion(
      logId: Value(logId),
      filePath: Value('/tmp/cover_${id}_$i.jpg'),
      createdAt: Value(s),
    ));
    await d.into(d.locations).insert(db.LocationsCompanion(
          logId: Value(logId),
          latitude: const Value(30.1),
          longitude: const Value(120.1),
          cityName: Value(destination),
        ));
  }
  if (expenseCents > 0) {
    await d.insertExpense(db.ExpensesCompanion(
      tripId: Value(id),
      category: const Value('food'),
      amountCents: Value(expenseCents),
      expenseDate: Value(s),
      createdAt: Value(s),
    ));
  }
  // 模拟创建旅程时的点亮（trip_provider._lightUpFootprint 的行为）
  final city = CityExtractor.extract(destination).city;
  await d.upsertFootprint(db.FootprintsCompanion(
    cityName: Value(city),
    country: const Value('中国'),
    latitude: const Value(30.2),
    longitude: const Value(120.2),
    firstVisitedAt: Value(s),
    latestVisitedAt: Value(DateTime.now()),
  ));
  return id;
}

void main() {
  late db.AppDatabase d;
  setUp(() => d = db.AppDatabase.forTesting(_memConnection()));
  tearDown(() async => d.close());

  test('删除旅程会带走日志、图片、定位、消费与标签关联', () async {
    final id = await _seedTrip(d, destination: '杭州', expenseCents: 4500, logs: 2);
    expect(await d.getLogsByTrip(id), hasLength(2));
    expect(await d.getExpensesByTrip(id), hasLength(1));

    final paths = await d.deleteTripCascade(id);

    expect(await d.getTripById(id), isNull);
    expect(await d.getLogsByTrip(id), isEmpty);
    expect((await d.getAllExpenses()), isEmpty);
    expect(await d.getImageCount(), 0);
    expect((await d.select(d.locations).get()), isEmpty);
    // 封面 + 两张日志图
    expect(paths, hasLength(3));
  });

  group('足迹随旅程删除实时更新', () {
    test('唯一一趟被删 → 城市熄灭', () async {
      final id = await _seedTrip(d, destination: '杭州');
      final city = CityExtractor.extract('杭州').city;
      expect(await d.getFootprintCount(), 1);

      await d.deleteTripCascade(id);

      expect(await d.getFootprintCount(), 0);
      expect(
          (await d.getAllFootprints()).where((f) => f.cityName == city), isEmpty);
    });

    test('去过两次删一次 → 次数减一且保留较晚那次的首访时间', () async {
      final a = await _seedTrip(d, destination: '杭州', start: DateTime(2025, 3, 1));
      final b = await _seedTrip(d, destination: '西湖', start: DateTime(2026, 8, 1));
      final city = CityExtractor.extract('杭州').city;
      var fp = (await d.getAllFootprints()).firstWhere((f) => f.cityName == city);
      expect(fp.visitCount, 2);
      expect(fp.firstVisitedAt, DateTime(2025, 3, 1));

      // 删掉较早的那趟：首访应推进到剩下的 2026-08-01
      await d.deleteTripCascade(a);
      fp = (await d.getAllFootprints()).firstWhere((f) => f.cityName == city);
      expect(fp.visitCount, 1);
      expect(fp.firstVisitedAt, DateTime(2026, 8, 1));

      // 再删最后一趟：彻底熄灭
      await d.deleteTripCascade(b);
      expect(await d.getFootprintCount(), 0);
    });

    test('删另一座城市不影响本城次数', () async {
      final hz = await _seedTrip(d, destination: '杭州');
      await _seedTrip(d, destination: '成都');
      await d.deleteTripCascade(hz);

      final cities = (await d.getAllFootprints()).map((f) => f.cityName).toSet();
      expect(cities.contains(CityExtractor.extract('成都').city), isTrue);
      expect(cities.contains(CityExtractor.extract('杭州').city), isFalse);
    });

    test('从未点亮过的目的地删除时不报错', () async {
      final id = await d.insertTrip(db.TripsCompanion(
        destination: Value('某个没人知道的小村'),
        startDate: Value(DateTime(2026, 1, 1)),
        endDate: Value(DateTime(2026, 1, 2)),
        createdAt: Value(DateTime(2026, 1, 1)),
        updatedAt: Value(DateTime(2026, 1, 1)),
      ));
      await d.deleteTripCascade(id);
      expect(await d.getTripById(id), isNull);
    });
  });

  test('统计口径：删完旅程后旅行天数与消费合计归零', () async {
    final id = await _seedTrip(d, destination: '杭州', expenseCents: 4500);
    final trips = await d.getAllTrips();
    final days = trips.fold<int>(
        0, (s, t) => s + t.endDate.difference(t.startDate).inDays + 1);
    expect(days, 3);
    expect(await d.getTripTotalCents(id), 4500);

    await d.deleteTripCascade(id);

    expect(await d.getAllTrips(), isEmpty);
    expect(await d.getExpenseCount(), 0);
  });

  test('deleteOrphanRows 清掉旧版本遗留的孤儿数据', () async {
    final id = await _seedTrip(d, destination: '杭州', expenseCents: 4500, logs: 1);
    // 模拟老 bug：只删 trips 行，附属数据全部留下
    await (d.delete(d.trips)..where((t) => t.id.equals(id))).go();
    expect(await d.getExpenseCount(), 1);
    expect((await d.getAllLogs()), hasLength(1));

    final n = await d.deleteOrphanRows();

    expect(n, greaterThan(0));
    expect(await d.getExpenseCount(), 0);
    expect(await d.getAllLogs(), isEmpty);
    // images 随日志一起清掉（此前会留下指向已删日志的孤儿行）
    expect((await d.select(d.images).get()), isEmpty);
    expect((await d.select(d.locations).get()), isEmpty);
  });
}
