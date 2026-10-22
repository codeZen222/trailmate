import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart' as db;
import '../models/achievement_model.dart';
import '../services/achievement_rules.dart';
import 'database_provider.dart';

/// 把 drift 行 + 已算好的指标合成展示用成就对象。
Achievement _build(db.Achievement r, AchievementMetrics metrics) {
  final rule = AchievementRule.parse(r.condition);
  final unlocked = r.unlockedAt != null;
  final progress = rule == null
      ? (unlocked ? 1.0 : 0.0)
      : (unlocked ? 1.0 : rule.progress(metrics));

  String hint;
  if (unlocked) {
    hint = '已达成';
  } else if (rule == null) {
    hint = r.condition; // 老数据里的中文条件，原样展示
  } else {
    final cur = metrics.of(rule.metric);
    final left = (rule.target - cur).ceil();
    hint = left <= 0 ? '即将达成' : ruleToHint(rule, cur);
  }

  return Achievement(
    id: r.id,
    name: r.name,
    description: r.description,
    icon: r.icon,
    condition: r.condition,
    rarity: Rarity.fromKey(r.rarity),
    unlockedAt: r.unlockedAt,
    hint: hint,
    progress: progress,
  );
}

Map<String, dynamic>? _profileJson(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final d = jsonDecode(raw);
    return d is Map<String, dynamic> ? d : null;
  } catch (_) {
    return null;
  }
}

/// 已解锁成就（保留旧接口）。
final achievementListProvider = StreamProvider<List<Achievement>>((ref) {
  final database = ref.watch(databaseProvider);
  return database
      .watchUnlockedAchievements()
      .map((rows) => rows.map((r) => _build(r, AchievementMetrics.empty)).toList());
});

final allAchievementsProvider = StreamProvider<List<Achievement>>((ref) {
  final database = ref.watch(databaseProvider);
  return database
      .watchAllAchievements()
      .map((rows) => rows.map((r) => _build(r, AchievementMetrics.empty)).toList());
});

/// 带**真实进度**的全部成就。成就页用这个，
/// 才能显示"城市 7/10"而不是灰着一片。
final achievementsWithProgressProvider =
    FutureProvider<List<Achievement>>((ref) async {
  final database = ref.watch(databaseProvider);
  final rows = await database.getAchievements();
  final metrics = await AchievementMetrics.compute(
    database,
    profileJson: _profileJson(await database.getSetting('user_profile')),
  );
  return rows.map((r) => _build(r, metrics)).toList();
});
