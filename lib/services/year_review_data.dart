import '../database/app_database.dart' as db;
import '../models/expense_model.dart';
import '../models/mood_type.dart';
import '../models/trip_model.dart';
import '../utils/geo_naming.dart';

/// 某个月份的出行概况。
class MonthStat {
  const MonthStat({required this.month, this.days = 0, this.places = const []});

  final int month; // 1..12
  final int days;
  final List<String> places;

  bool get hasTrip => days > 0;
}

/// 年度回顾的全部聚合结果。一次算完，页面各卡片只读不算。
class YearReviewData {
  const YearReviewData({
    required this.year,
    required this.trips,
    required this.totalDays,
    required this.logCount,
    required this.photoCount,
    required this.cities,
    required this.newCities,
    required this.months,
    required this.highlights,
    required this.longest,
    required this.shortest,
    required this.expenseCents,
    required this.expenseByCategory,
    required this.moodCounts,
    required this.photoWall,
    required this.tagCounts,
    required this.unlockedAchievements,
    required this.coverPhoto,
    required this.totalPhotosEver,
  });

  final int year;
  final List<Trip> trips;
  final int totalDays;
  final int logCount;
  final int photoCount;

  /// 该年出现过的城市（GPS 定位 + 旅程目的地合并去重）。
  final List<String> cities;

  /// 其中"首次到访"落在该年的城市。
  final List<String> newCities;

  final List<MonthStat> months;

  /// 按评分排序的高光旅程（最多 3 个）。
  final List<Trip> highlights;
  final Trip? longest;
  final Trip? shortest;

  final int expenseCents;
  final Map<ExpenseCategory, int> expenseByCategory;

  /// 日志心情分布（次数）。
  final Map<MoodType, int> moodCounts;

  /// 照片墙素材（最多 12 张）。
  final List<String> photoWall;

  /// 标签使用频次，降序。
  final List<MapEntry<String, int>> tagCounts;

  final List<db.Achievement> unlockedAchievements;

  /// 封面大图：优先取评分最高旅程的封面。
  final String? coverPhoto;

  /// 历史总照片数（用于"今年占了多少"的对比语）。
  final int totalPhotosEver;

  bool get isEmpty => trips.isEmpty && logCount == 0 && photoCount == 0;

  /// 出行最集中的月份。
  MonthStat? get busiestMonth {
    final active = months.where((m) => m.days > 0).toList();
    if (active.isEmpty) return null;
    return active.reduce((a, b) => a.days >= b.days ? a : b);
  }

  /// 日均花费（按该年出行天数）。
  int get dailySpendCents =>
      totalDays <= 0 ? 0 : (expenseCents / totalDays).round();

  /// 出现最多的心情。
  MoodType? get topMood {
    if (moodCounts.isEmpty) return null;
    return moodCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// 花费最高的分类。
  MapEntry<ExpenseCategory, int>? get topCategory {
    if (expenseByCategory.isEmpty) return null;
    return expenseByCategory.entries.reduce((a, b) => a.value >= b.value ? a : b);
  }

  /// drift 行对象 → 模型 Trip（durationDays 等派生属性只在模型上有）。
  static Trip _toModel(db.Trip r) => Trip(
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

  /// 聚合指定年份的全部回顾数据。
  static Future<YearReviewData> build(db.AppDatabase database, int year) async {
    final allTrips =
        (await database.getAllTrips()).map(_toModel).toList();
    final yearTrips = allTrips.where((t) => t.startDate.year == year).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    final footprints = await database.getAllFootprints();
    final allExpenses = await database.getAllExpenses();
    final achievements = await database.getAchievements();
    final totalPhotos = await database.getImageCount();

    var totalDays = 0;
    var logCount = 0;
    var photoCount = 0;
    /// 归一化后的城市名集合（"泰安市"与"泰安"视为同一座）。
    final cities = <String>{};
    final photos = <String>[];
    final tagMap = <String, int>{};
    final moodMap = <MoodType, int>{};
    final monthDays = <int, int>{};
    final monthPlaces = <int, List<String>>{};

    // 【口径统一】年度报告以"该年出发的旅程"为唯一次元：
    // 这些旅程的日志、照片、城市全部计入，不再按各自日期二次筛选年份。
    // 之前 cities 取自旅程/日志、newCities 却取自 footprints 的首访年份，
    // 两个独立来源会导致"走过 3 座却有 4 座首访"这种不可能的结果。
    for (final t in yearTrips) {
      totalDays += t.durationDays;

      final logs = await database.getLogsByTrip(t.id);
      final images = await database.getImagesByTrip(t.id);
      final tripCities = await database.getCitiesByTrip(t.id);
      final tripTags = await database.getTagsByTrip(t.id);

      logCount += logs.length;
      photoCount += images.length;
      // 目的地与 GPS 城市名都归一化后入集合
      final destCity = cityOf(t.destination);
      if (destCity != null && destCity.isNotEmpty) cities.add(destCity);
      for (final c in tripCities) {
        final n = cityOf(c);
        if (n != null && n.isNotEmpty) cities.add(n);
      }

      for (final tag in tripTags) {
        tagMap[tag.name] = (tagMap[tag.name] ?? 0) + 1;
      }
      for (final img in images) {
        photos.add(img.filePath);
      }
      for (final l in logs) {
        // 不再按 l.date.year 二次筛选：属于该年旅程的日志就算这一年的
        monthDays[l.date.month] = (monthDays[l.date.month] ?? 0) + 1;
        final m = MoodType.fromKey(l.moodTag);
        if (m != null) moodMap[m] = (moodMap[m] ?? 0) + 1;
      }
      if (logs.isEmpty) {
        monthDays[t.startDate.month] = (monthDays[t.startDate.month] ?? 0) + t.durationDays;
      }
      final placeName = cityOf(t.destination) ?? t.destination;
      monthPlaces.putIfAbsent(t.startDate.month, () => []).add(placeName);
    }

    // 首次到访年份表（城市名同样归一化，并允许互相包含以匹配"泰安/泰安市"）
    final firstVisitYear = <String, int>{};
    for (final f in footprints) {
      final n = cityOf(f.cityName);
      if (n == null || n.isEmpty) continue;
      final prev = firstVisitYear[n];
      if (prev == null || f.firstVisitedAt.year < prev) firstVisitYear[n] = f.firstVisitedAt.year;
    }

    /// 该城市是否这一年首次到访；footprints 里查不到就按新城市算。
    bool isFirstVisit(String c) {
      int? y = firstVisitYear[c];
      if (y == null) {
        // 名称可能有"泰安 / 泰安市"这类差异，做双向包含匹配
        for (final e in firstVisitYear.entries) {
          if (c.contains(e.key) || e.key.contains(c)) {
            y = e.value;
            break;
          }
        }
      }
      if (y == null) return true;
      return y == year;
    }

    // 【保证 首访 ⊆ 走过】只在本年城市集合内判定，杜绝"走过3座/首访4座"
    final newCities = cities.where(isFirstVisit).toList();

    // 花费：同样以"该年的旅程"为口径，才能和 totalDays 一起算出有意义的日均
    final yearTripIds = yearTrips.map((t) => t.id).toSet();
    var expenseCents = 0;
    final expByCat = <ExpenseCategory, int>{};
    for (final e in allExpenses) {
      if (!yearTripIds.contains(e.tripId)) continue;
      expenseCents += e.amountCents;
      final c = ExpenseCategory.fromKey(e.category);
      expByCat[c] = (expByCat[c] ?? 0) + e.amountCents;
    }

    // 高光：按评分降序（未评分为 0，自然排最后），同分按天数
    final highlights = [...yearTrips]
      ..sort((a, b) {
        if (a.rating != b.rating) return b.rating.compareTo(a.rating);
        return b.durationDays.compareTo(a.durationDays);
      });

    Trip? longest, shortest;
    for (final t in yearTrips) {
      if (longest == null || t.durationDays > longest.durationDays) longest = t;
      if (shortest == null || t.durationDays < shortest.durationDays) shortest = t;
    }

    final months = [
      for (var m = 1; m <= 12; m++)
        MonthStat(
          month: m,
          days: monthDays[m] ?? 0,
          places: (monthPlaces[m] ?? const []).toSet().toList(),
        ),
    ];

    // 封面：优先高光旅程里有封面的
    String? cover;
    for (final t in highlights) {
      if ((t.coverPath ?? '').isNotEmpty) {
        cover = t.coverPath;
        break;
      }
    }
    cover ??= photos.isNotEmpty ? photos.first : null;

    return YearReviewData(
      year: year,
      trips: yearTrips,
      totalDays: totalDays,
      logCount: logCount,
      photoCount: photoCount,
      cities: cities.where((c) => c.isNotEmpty).toList(),
      newCities: newCities,
      months: months,
      highlights: highlights.take(3).toList(),
      longest: longest,
      shortest: yearTrips.length > 1 ? shortest : null,
      expenseCents: expenseCents,
      expenseByCategory: expByCat,
      moodCounts: moodMap,
      photoWall: photos.take(12).toList(),
      tagCounts: (tagMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(6)
          .toList(),
      unlockedAchievements: achievements
          .where((a) => a.unlockedAt != null && a.unlockedAt!.year == year)
          .toList(),
      coverPhoto: cover,
      totalPhotosEver: totalPhotos,
    );
  }
}
