import '../models/expense_model.dart';

/// 一个聚合单元：标签 + 金额（分）。
class StatBucket {
  const StatBucket(this.label, this.cents, {this.category});

  final String label;
  final int cents;
  final ExpenseCategory? category;
}

/// 消费统计结果。全部由内存中的消费列表聚合而来——
/// 个人旅行场景数据量小（通常几百条内），在 Dart 侧聚合比写 SQL 分组更直观，
/// 也便于单测。
class ExpenseStats {
  const ExpenseStats({
    required this.totalCents,
    required this.count,
    required this.monthCents,
    required this.byCategory,
    required this.byMonth,
    required this.byTrip,
    required this.activeDays,
    this.largest,
  });

  final int totalCents;
  final int count;

  /// 本月支出。
  final int monthCents;

  /// 分类占比，按金额降序。
  final List<StatBucket> byCategory;

  /// 近 6 个月趋势，时间正序。
  final List<StatBucket> byMonth;

  /// 旅程花费排行，降序。
  final List<StatBucket> byTrip;

  /// 有消费记录的自然日数（用于"日均"，比按旅程天数更真实）。
  final int activeDays;

  /// 最大单笔。
  final Expense? largest;

  static const empty = ExpenseStats(
    totalCents: 0,
    count: 0,
    monthCents: 0,
    byCategory: [],
    byMonth: [],
    byTrip: [],
    activeDays: 0,
  );

  bool get isEmpty => count == 0;

  /// 日均花费（分）；无记录时为 0。
  int get dailyAverageCents => activeDays == 0 ? 0 : (totalCents / activeDays).round();

  /// 从消费明细与「旅程 id → 名称」聚合。
  factory ExpenseStats.from(
    List<Expense> expenses, {
    Map<int, String> tripNames = const {},
    DateTime? now,
  }) {
    if (expenses.isEmpty) return empty;

    final reference = now ?? DateTime.now();
    var total = 0;
    var month = 0;
    final catMap = <String, int>{};
    final monthMap = <String, int>{};
    final tripMap = <int, int>{};
    final dayKeys = <String>{};
    Expense? largest;

    for (final e in expenses) {
      total += e.amountCents;

      if (e.expenseDate.year == reference.year &&
          e.expenseDate.month == reference.month) {
        month += e.amountCents;
      }

      catMap[e.category.key] = (catMap[e.category.key] ?? 0) + e.amountCents;

      final mk = '${e.expenseDate.year}-${e.expenseDate.month.toString().padLeft(2, '0')}';
      monthMap[mk] = (monthMap[mk] ?? 0) + e.amountCents;

      tripMap[e.tripId] = (tripMap[e.tripId] ?? 0) + e.amountCents;

      dayKeys.add(
          '${e.expenseDate.year}-${e.expenseDate.month}-${e.expenseDate.day}');

      if (largest == null || e.amountCents > largest.amountCents) largest = e;
    }

    // 分类：按 ExpenseCategory 声明顺序取，保证同额时顺序稳定
    final byCategory = <StatBucket>[
      for (final c in ExpenseCategory.all)
        if ((catMap[c.key] ?? 0) > 0)
          StatBucket(c.label, catMap[c.key]!, category: c)
    ]..sort((a, b) => b.cents.compareTo(a.cents));

    // 月度：补齐最近 6 个月的空档，否则柱状图会跳月
    final byMonth = <StatBucket>[];
    for (var i = 5; i >= 0; i--) {
      var y = reference.year;
      var m = reference.month - i;
      while (m <= 0) {
        m += 12;
        y -= 1;
      }
      final mk = '$y-${m.toString().padLeft(2, '0')}';
      byMonth.add(StatBucket('$m月', monthMap[mk] ?? 0));
    }

    final byTrip = <StatBucket>[
      for (final entry in tripMap.entries)
        StatBucket(tripNames[entry.key] ?? '未知旅程', entry.value)
    ]..sort((a, b) => b.cents.compareTo(a.cents));

    return ExpenseStats(
      totalCents: total,
      count: expenses.length,
      monthCents: month,
      byCategory: byCategory,
      byMonth: byMonth,
      byTrip: byTrip,
      activeDays: dayKeys.length,
      largest: largest,
    );
  }
}
