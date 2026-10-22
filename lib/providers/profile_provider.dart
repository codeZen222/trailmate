import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile_model.dart';
import 'database_provider.dart';

/// 档案在 settings 表中的键。
const String profileSettingKey = 'user_profile';

/// 个人旅行档案：单条记录，以 JSON 存于 settings 表（避免额外数据库迁移）。
class ProfileNotifier extends StateNotifier<Profile?> {
  ProfileNotifier(this._ref) : super(null) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final raw = await _ref.read(databaseProvider).getSetting(profileSettingKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        final p = Profile.fromJson(map);
        if (!p.isEmpty) state = p;
      }
    } catch (_) {
      // 数据损坏时保持 null，界面会引导重新填写
    }
  }

  Future<void> save(Profile profile) async {
    final toSave = profile.copyWith(updatedAt: DateTime.now());
    state = toSave;
    await _ref
        .read(databaseProvider)
        .setSetting(profileSettingKey, jsonEncode(toSave.toJson()));
  }

  Future<void> clear() async {
    state = null;
    await _ref.read(databaseProvider).setSetting(profileSettingKey, '');
  }
}

final profileProvider =
    StateNotifierProvider<ProfileNotifier, Profile?>((ref) => ProfileNotifier(ref));

/// 自动汇总的旅行统计。
final profileStatsProvider = FutureProvider<ProfileStats>((ref) async {
  final db = ref.watch(databaseProvider);
  final trips = await db.getAllTrips();
  final cities = await db.getAllFootprints();
  final photos = await db.getImageCount();
  final logs = await db.getLogCount();
  final unlocked = await db.getUnlockedCount();
  final total = await db.getAchievementCount();

  // 旅程天数按起止日期累加，并对重叠区间做同日去重以外的简单求和。
  var days = 0;
  for (final t in trips) {
    final d = t.endDate.difference(t.startDate).inDays + 1;
    if (d > 0) days += d;
  }

  return ProfileStats(
    cities: cities.length,
    trips: trips.length,
    totalDays: days,
    photos: photos,
    logs: logs,
    achievementsUnlocked: unlocked,
    achievementsTotal: total,
  );
});
