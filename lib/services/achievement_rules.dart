import 'dart:math' as math;

import '../database/app_database.dart' as db;
import '../models/mood_type.dart';
import '../utils/geo_naming.dart';

/// 成就指标集合。所有成就的判定都只读这里，
/// 新增成就通常只需加一条定义，不必改判定代码。
class AchievementMetrics {
  const AchievementMetrics({required this.values});

  /// 指标名 → 数值。
  final Map<String, double> values;

  double of(String metric) => values[metric] ?? 0;

  bool has(String metric) => values.containsKey(metric);

  static const empty = AchievementMetrics(values: {});

  /// 从数据库计算全部指标。
  static Future<AchievementMetrics> compute(
    db.AppDatabase db, {
    Map<String, dynamic>? profileJson,
  }) async {
    final trips = await db.getAllTrips();
    final footprints = await db.getAllFootprints();
    final logs = await db.getAllLogs();
    final expenses = await db.getAllExpenses();
    final photoCount = await db.getImageCount();

    final values = <String, double>{};

    // ---------- 基础量 ----------
    values['trips'] = trips.length.toDouble();
    values['photos'] = photoCount.toDouble();
    values['logs'] = logs.length.toDouble();

    // 城市：footprints 与旅程目的地都归一化后去重
    final citySet = <String>{};
    for (final f in footprints) {
      final c = cityOf(f.cityName);
      if (c != null && c.isNotEmpty) citySet.add(c);
    }
    for (final t in trips) {
      final c = cityOf(t.destination);
      if (c != null && c.isNotEmpty) citySet.add(c);
    }
    values['cities'] = citySet.length.toDouble();

    // 省份
    final provSet = <String>{};
    for (final c in citySet) {
      final p = provinceOf(c);
      if (p != null) provSet.add(p);
    }
    for (final t in trips) {
      final p = provinceOf(t.destination);
      if (p != null) provSet.add(p);
    }
    values['provinces'] = provSet.length.toDouble();

    // 总天数
    var totalDays = 0;
    for (final t in trips) {
      final d = t.endDate.difference(t.startDate).inDays + 1;
      if (d > 0) totalDays += d;
    }
    values['days'] = totalDays.toDouble();

    // ---------- 时间维度 ----------
    // 最长连续记录天数（同一天多篇算一天）
    final logDays = logs
        .map((l) => DateTime(l.date.year, l.date.month, l.date.day))
        .toSet()
        .toList()
      ..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in logDays) {
      if (prev != null && d.difference(prev).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      best = math.max(best, run);
      prev = d;
    }
    values['streak_days'] = best.toDouble();

    // 活跃年份数
    final years = <int>{};
    for (final t in trips) {
      years.add(t.startDate.year);
    }
    for (final l in logs) {
      years.add(l.date.year);
    }
    values['years'] = years.length.toDouble();

    // 深夜笔耕：23:00–05:00 创建的日志
    var lateNight = 0;
    for (final l in logs) {
      final h = l.createdAt.hour;
      if (h >= 23 || h < 5) lateNight++;
    }
    values['late_night_logs'] = lateNight.toDouble();

    // 跨年旅程（起止不在同一年）
    values['new_year_trips'] =
        trips.where((t) => t.startDate.year != t.endDate.year).length.toDouble();

    // ---------- 情绪维度 ----------
    final moods = <String>{};
    var rainyMood = 0, contrast = 0;
    final moodByTripDay = <String, String>{};
    for (final l in logs) {
      final m = MoodType.fromKey(l.moodTag);
      if (m == null) continue;
      moods.add(m.key);
      if (m == MoodType.rain) rainyMood++;
      // 反差：天气晴好但心情在下雨
      final w = l.weather ?? '';
      if (m == MoodType.rain && w.contains('晴')) contrast++;
      moodByTripDay['${l.tripId}-${l.date.day}'] = m.key;
    }
    values['mood_variety'] = moods.length.toDouble();
    values['rain_mood'] = rainyMood.toDouble();
    values['mood_contrast'] = contrast.toDouble();

    // 连续 3 篇同心情
    var sameRun = 0, bestSame = 0;
    String? lastMood;
    final orderedLogs = [...logs]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final l in orderedLogs) {
      final m = MoodType.fromKey(l.moodTag);
      if (m == null) {
        sameRun = 0;
        lastMood = null;
        continue;
      }
      if (lastMood == m.key) {
        sameRun++;
      } else {
        sameRun = 1;
        lastMood = m.key;
      }
      bestSame = math.max(bestSame, sameRun);
    }
    values['same_mood_streak'] = bestSame.toDouble();

    // ---------- 消费维度 ----------
    final expenseTripIds = expenses.map((e) => e.tripId).toSet();
    values['expense_trips'] = expenseTripIds.length.toDouble();
    values['expense_count'] = expenses.length.toDouble();
    final totalSpend = expenses.fold<int>(0, (s, e) => s + e.amountCents);
    values['expense_cents'] = totalSpend.toDouble();
    values['expense_categories'] =
        expenses.map((e) => e.category).toSet().length.toDouble();

    var maxTripSpend = 0;
    var cheapestDaily = double.infinity;
    for (final id in expenseTripIds) {
      final sum = expenses
          .where((e) => e.tripId == id)
          .fold<int>(0, (s, e) => s + e.amountCents);
      maxTripSpend = math.max(maxTripSpend, sum);
      final trip = trips.where((t) => t.id == id).firstOrNull;
      if (trip != null) {
        final d = trip.endDate.difference(trip.startDate).inDays + 1;
        if (d > 0) cheapestDaily = math.min(cheapestDaily, sum / d);
      }
    }
    values['max_trip_spend'] = maxTripSpend.toDouble();
    values['cheapest_daily'] =
        cheapestDaily.isInfinite ? 0 : cheapestDaily.toDouble();

    // ---------- 地理维度 ----------
    final lats = footprints.where((f) => f.latitude != 0).map((f) => f.latitude).toList();
    values['lat_span'] =
        lats.isEmpty ? 0 : (lats.reduce(math.max) - lats.reduce(math.min)).toDouble();

    // 单次旅程跨多城（按该旅程日志的 GPS 城市数）
    var maxCitiesInTrip = 0;
    for (final t in trips) {
      final cs = await db.getCitiesByTrip(t.id);
      final norm = cs.map((c) => cityOf(c) ?? c).toSet();
      maxCitiesInTrip = math.max(maxCitiesInTrip, norm.length);
    }
    values['max_cities_in_trip'] = maxCitiesInTrip.toDouble();

    // ---------- 评价维度 ----------
    values['five_star_trips'] = trips.where((t) => t.rating >= 5).length.toDouble();
    values['rated_trips'] = trips.where((t) => t.rating > 0).length.toDouble();
    // 全部旅程都评过分（至少 3 趟，避免只有一趟时轻易达成）
    final rated = trips.where((t) => t.rating > 0).length;
    values['all_rated'] = (trips.length >= 3 && rated == trips.length) ? 1 : 0;

    // ---------- 行为标记（由具体功能写入 settings）----------
    values['flag_sprite_expense'] = await _flag(db, 'ach_flag_sprite_expense');
    values['flag_year_review'] = await _flag(db, 'ach_flag_year_review');
    values['flag_poster_shared'] = await _flag(db, 'ach_flag_poster_shared');
    values['flag_footprint_route'] = await _flag(db, 'ach_flag_footprint_route');
    values['flag_fixed_coords'] = await _flag(db, 'ach_flag_fixed_coords');

    // 档案完整度（0..6 项）
    var complete = 0.0;
    if (profileJson != null) {
      String s(String k) => (profileJson[k] ?? '').toString().trim();
      if (s('nickname').isNotEmpty) complete++;
      if (s('homeCity').isNotEmpty) complete++;
      if (s('bio').isNotEmpty) complete++;
      if ((profileJson['travelStyles'] as List?)?.isNotEmpty ?? false) complete++;
      if ((profileJson['bucketList'] as List?)?.isNotEmpty ?? false) complete++;
      if (s('photoPath').isNotEmpty || s('avatarPath').isNotEmpty) complete++;
    }
    values['profile_complete'] = complete;

    return AchievementMetrics(values: values);
  }

  static Future<double> _flag(db.AppDatabase db, String key) async {
    final v = await db.getSetting(key);
    return v == '1' ? 1 : 0;
  }
}

/// 一条成就规则：`metric>=target` 或 `metric==target`。
class AchievementRule {
  const AchievementRule(this.metric, this.gte, this.target);

  final String metric;
  final bool gte; // true: >= ，false: ==
  final double target;

  /// 解析失败返回 null（旧数据里 condition 是中文描述，解析不出即忽略）。
  static AchievementRule? parse(String? source) {
    if (source == null || source.isEmpty) return null;
    final s = source.trim();
    final ge = RegExp(r'^([a-z_]+)\s*>=\s*(\d+(?:\.\d+)?)$').firstMatch(s);
    if (ge != null) {
      return AchievementRule(ge.group(1)!, true, double.parse(ge.group(2)!));
    }
    // 允许规则里带数字（如 max_trip_spend）
    final ge2 = RegExp(r'^([a-z_0-9]+)\s*>=\s*(\d+(?:\.\d+)?)$').firstMatch(s);
    if (ge2 != null) {
      return AchievementRule(ge2.group(1)!, true, double.parse(ge2.group(2)!));
    }
    final eq = RegExp(r'^([a-z_0-9]+)\s*==\s*(\d+(?:\.\d+)?)$').firstMatch(s);
    if (eq != null) {
      return AchievementRule(eq.group(1)!, false, double.parse(eq.group(2)!));
    }
    final flag = RegExp(r'^([a-z_0-9]+)$').firstMatch(s);
    if (flag != null) {
      return AchievementRule(flag.group(1)!, true, 1);
    }
    return null;
  }

  bool test(AchievementMetrics m) {
    final v = m.of(metric);
    return gte ? v >= target : v == target;
  }

  /// 进度 0..1，用于进度条。
  double progress(AchievementMetrics m) {
    if (target <= 0) return 1;
    return (m.of(metric) / target).clamp(0.0, 1.0);
  }

  String get display => gte ? '$metric>=$target' : '$metric==$target';
}

/// 指标名 → 中文标签，用于把规则串翻译成人能看懂的进度说明。
const Map<String, String> kMetricLabels = {
  'trips': '旅程',
  'cities': '城市',
  'provinces': '省份',
  'days': '旅行天数',
  'logs': '日志',
  'photos': '照片',
  'streak_days': '连续记录天数',
  'years': '记录年份',
  'late_night_logs': '深夜日志',
  'new_year_trips': '跨年旅程',
  'mood_variety': '心情种类',
  'rain_mood': '心在下雨',
  'mood_contrast': '晴雨反差',
  'same_mood_streak': '连续同心情',
  'expense_count': '消费笔数',
  'expense_trips': '记账旅程',
  'expense_cents': '消费总额',
  'expense_categories': '消费分类',
  'max_trip_spend': '单趟消费',
  'cheapest_daily': '最省日均',
  'flag_sprite_expense': '精灵记账',
  'flag_year_review': '年度报告',
  'flag_poster_shared': '分享成果',
  'flag_footprint_route': '连线回看',
  'flag_fixed_coords': '补全坐标',
  'lat_span': '南北跨度',
  'max_cities_in_trip': '单趟跨城',
  'five_star_trips': '满分旅程',
  'rated_trips': '已评分旅程',
  'all_rated': '全部评分',
  'profile_complete': '档案完整度',
};

/// 把规则串翻译为中文进度描述，如「城市 7/10」。
String ruleToHint(AchievementRule rule, double current) {
  final label = kMetricLabels[rule.metric] ?? rule.metric;
  final t = rule.target;
  final fmtT = t == t.roundToDouble() ? t.toInt().toString() : t.toString();
  final fmtC = current == current.roundToDouble()
      ? current.toInt().toString()
      : current.toStringAsFixed(1);
  return '$label $fmtC/$fmtT';
}

/// 成就稀有度。
enum Rarity {
  common('common', '普通', 0xFF9E9E9E),
  rare('rare', '稀有', 0xFF4A7FB5),
  epic('epic', '史诗', 0xFF7B5EA7),
  legend('legend', '传说', 0xFFD4A017);

  const Rarity(this.key, this.label, this.colorValue);
  final String key;
  final String label;
  final int colorValue;

  static Rarity fromKey(String? k) =>
      values.firstWhere((r) => r.key == k, orElse: () => Rarity.common);
}

/// 一个成就定义。数据库里存 name/description/icon/condition/rarity，
/// 这里的定义用于**首次播种**与**规则同步**（改规则只需改这张表）。
class AchievementDef {
  const AchievementDef({
    required this.name,
    required this.description,
    required this.icon,
    required this.rarity,
    required this.rule,
    required this.hint,
    this.series = '其他',
  });

  final String name;
  final String description;
  final String icon;
  final Rarity rarity;

  /// 可求值规则串。
  final String rule;
  /// 给人看的达成提示。
  final String hint;
  /// 所属系列，仅用于界面分组展示（不入库）。
  final String series;
}

/// 系列顺序与图标。
const List<(String, String)> kSeriesOrder = [
  ('🚶 行者之路', '行者之路'),
  ('📅 坚持之光', '坚持之光'),
  ('🎭 情绪诗人', '情绪诗人'),
  ('💰 理性账本', '理性账本'),
  ('🗺 地图征服', '地图征服'),
  ('✨ 收藏彩蛋', '收藏彩蛋'),
];

/// 系列 → 成员成就名。集中一处维护，避免逐条改 37 个定义时出错。
const Map<String, List<String>> kSeriesMembers = {
  '行者之路': ['初次出发', '小步慢行', '旅行家', '探险家', '纵横四海', '寰宇行者'],
  '坚持之光': ['提笔记录', '三日之约', '七日不辍', '月度笔耕', '深夜笔耕', '跨年之旅', '岁月留痕'],
  '情绪诗人': ['第一种心情', '心在下雨', '反差萌', '情绪共鸣', '六色情绪', '十二情绪'],
  '理性账本': ['第一笔账', '会算账', '挥金如土', '精打细算', '全类目收藏', '精灵记账'],
  '地图征服': ['首次远行', '三省游侠', '九州纵横', '一线多城', '纵横南北', '轨迹回看'],
  '收藏彩蛋': [
    '影像收藏家', '满分旅程', '全部评过分', '年度报告',
    '晒过足迹', '档案达人', '坐标修复师',
  ],
};

final Map<String, String> _nameToSeries = {
  for (final e in kSeriesMembers.entries)
    for (final n in e.value) n: e.key,
};

/// 按名字查所属系列；未归类的落到「收藏彩蛋」。
String seriesOf(String name) => _nameToSeries[name] ?? '收藏彩蛋';

/// 30 个成就定义，分六大系列。
const List<AchievementDef> kAchievements = [
  // —— 🚶 行者之路 ——
  AchievementDef(name: '初次出发', description: '完成你的第一次旅行', icon: '🚀', rarity: Rarity.common, rule: 'trips>=1', hint: '创建第一个旅程'),
  AchievementDef(name: '小步慢行', description: '点亮 3 座城市', icon: '👣', rarity: Rarity.common, rule: 'cities>=3', hint: '让 3 个城市出现在足迹里'),
  AchievementDef(name: '旅行家', description: '点亮 5 座城市', icon: '🌍', rarity: Rarity.common, rule: 'cities>=5', hint: '再走 2 座就达成了'),
  AchievementDef(name: '探险家', description: '点亮 10 座城市', icon: '🌏', rarity: Rarity.rare, rule: 'cities>=10', hint: '足迹覆盖 10 城'),
  AchievementDef(name: '纵横四海', description: '点亮 20 座城市', icon: '🧭', rarity: Rarity.epic, rule: 'cities>=20', hint: '走过 20 座城'),
  AchievementDef(name: '寰宇行者', description: '点亮 50 座城市', icon: '🛰️', rarity: Rarity.legend, rule: 'cities>=50', hint: '50 座城的男人/女人'),

  // —— 📅 坚持之光 ——
  AchievementDef(name: '提笔记录', description: '写下第一篇日志', icon: '✍️', rarity: Rarity.common, rule: 'logs>=1', hint: '写第一篇'),
  AchievementDef(name: '三日之约', description: '连续 3 天记录', icon: '📅', rarity: Rarity.common, rule: 'streak_days>=3', hint: '连着三天都写'),
  AchievementDef(name: '七日不辍', description: '连续 7 天记录', icon: '🔥', rarity: Rarity.rare, rule: 'streak_days>=7', hint: '一整周不断更'),
  AchievementDef(name: '月度笔耕', description: '连续 30 天记录', icon: '🏮', rarity: Rarity.epic, rule: 'streak_days>=30', hint: '坚持一个月'),
  AchievementDef(name: '深夜笔耕', description: '在 23 点后写过日志', icon: '🌙', rarity: Rarity.common, rule: 'late_night_logs>=1', hint: '夜里赶一篇'),
  AchievementDef(name: '跨年之旅', description: '有一次旅程跨越了新年', icon: '🎇', rarity: Rarity.rare, rule: 'new_year_trips>=1', hint: '安排一次跨年出行'),
  AchievementDef(name: '岁月留痕', description: '在 3 个不同年份留下记录', icon: '📚', rarity: Rarity.rare, rule: 'years>=3', hint: '坚持记三年'),

  // —— 🎭 情绪诗人 ——
  AchievementDef(name: '第一种心情', description: '第一次给日志标上心情', icon: '🎭', rarity: Rarity.common, rule: 'mood_variety>=1', hint: '写日志时点个心情'),
  AchievementDef(name: '心在下雨', description: '记录过一次「心在下雨」', icon: '🌧️', rarity: Rarity.common, rule: 'rain_mood>=1', hint: '允许自己低落一次'),
  AchievementDef(name: '反差萌', description: '天气晴朗但心情下雨', icon: '☀️🌧️', rarity: Rarity.rare, rule: 'mood_contrast>=1', hint: '晴天下起心里的雨'),
  AchievementDef(name: '情绪共鸣', description: '连续 3 篇同一心情', icon: '💞', rarity: Rarity.rare, rule: 'same_mood_streak>=3', hint: '连着三篇一个情绪'),
  AchievementDef(name: '六色情绪', description: '用过 6 种不同心情', icon: '🎨', rarity: Rarity.epic, rule: 'mood_variety>=6', hint: '体验过六种心情'),
  AchievementDef(name: '十二情绪', description: '集齐全部 12 种心情', icon: '🌌', rarity: Rarity.legend, rule: 'mood_variety>=12', hint: '把 12 种都试一遍'),

  // —— 💰 理性账本 ——
  AchievementDef(name: '第一笔账', description: '记下第一笔旅行消费', icon: '🧾', rarity: Rarity.common, rule: 'expense_count>=1', hint: '记一笔开销'),
  AchievementDef(name: '会算账', description: '5 趟旅程都记了账', icon: '📊', rarity: Rarity.rare, rule: 'expense_trips>=5', hint: '连续几趟都记'),
  AchievementDef(name: '挥金如土', description: '单趟消费破一千', icon: '💸', rarity: Rarity.rare, rule: 'max_trip_spend>=100000', hint: '一趟花过 ¥1,000'),
  AchievementDef(name: '精打细算', description: '有一趟日均低于 50', icon: '🪙', rarity: Rarity.epic, rule: 'cheapest_daily>=0.01', hint: '穷游也能很开心'),
  AchievementDef(name: '全类目收藏', description: '消费覆盖 6 个分类', icon: '🗂️', rarity: Rarity.epic, rule: 'expense_categories>=6', hint: '交通住宿餐饮都记过'),
  AchievementDef(name: '精灵记账', description: '用旅行精灵记过一笔', icon: '🧚', rarity: Rarity.rare, rule: 'flag_sprite_expense>=1', hint: '对精灵说「午餐45」'),

  // —— 🗺 地图征服 ——
  AchievementDef(name: '首次远行', description: '走过 2 个省份', icon: '🛣️', rarity: Rarity.common, rule: 'provinces>=2', hint: '出一次省'),
  AchievementDef(name: '三省游侠', description: '点亮 3 个省份', icon: '⛰️', rarity: Rarity.rare, rule: 'provinces>=3', hint: '走过三个省'),
  AchievementDef(name: '九州纵横', description: '点亮 5 个省份', icon: '🗺️', rarity: Rarity.epic, rule: 'provinces>=5', hint: '五个省以上'),
  AchievementDef(name: '一线多城', description: '一次旅程走过 3 座城', icon: '🚌', rarity: Rarity.rare, rule: 'max_cities_in_trip>=3', hint: '一趟玩三个地方'),
  AchievementDef(name: '纵横南北', description: '足迹南北跨度超 15 度', icon: '🧊', rarity: Rarity.legend, rule: 'lat_span>=15', hint: '从哈尔滨到三亚那种'),
  AchievementDef(name: '轨迹回看', description: '用连线模式看过路线', icon: '🧵', rarity: Rarity.common, rule: 'flag_footprint_route>=1', hint: '足迹页切到「连线」'),

  // —— ✨ 收藏彩蛋 ——
  AchievementDef(name: '影像收藏家', description: '累计 100 张照片', icon: '📷', rarity: Rarity.rare, rule: 'photos>=100', hint: '拍够一百张'),
  AchievementDef(name: '满分旅程', description: '给某趟旅行打了 5 星', icon: '⭐', rarity: Rarity.common, rule: 'five_star_trips>=1', hint: '旅程详情页点满星'),
  AchievementDef(name: '全部评过分', description: '至少 3 趟旅程，且每趟都打了分', icon: '🌟', rarity: Rarity.epic, rule: 'all_rated>=1', hint: '别落下任何一趟的评分'),
  AchievementDef(name: '年度报告', description: '打开过一次年度报告', icon: '📖', rarity: Rarity.common, rule: 'flag_year_review>=1', hint: '统计页进年报看看'),
  AchievementDef(name: '晒过足迹', description: '分享过一次地图或海报', icon: '📤', rarity: Rarity.common, rule: 'flag_poster_shared>=1', hint: '把成果分享出去'),
  AchievementDef(name: '档案达人', description: '旅行档案填满 6 项', icon: '🪪', rarity: Rarity.rare, rule: 'profile_complete>=6', hint: '设置页把档案填全'),
  AchievementDef(name: '坐标修复师', description: '手动补全过一个缺失坐标', icon: '🔧', rarity: Rarity.common, rule: 'flag_fixed_coords>=1', hint: '足迹页补一个城市坐标'),
];
