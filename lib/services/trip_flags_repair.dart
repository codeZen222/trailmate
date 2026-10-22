import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import '../database/app_database.dart' as db;

/// 一次性回填历史旅程的 isCompleted。
///
/// 【为什么必须做】isCompleted 列默认 false，而早期创建流程从未写入它 ——
/// 于是所有老旅程都是 false。若直接用 `!isCompleted` 判"进行中"，
/// 济南这种填了结束日期的旅程会被错误显示成"进行中"（正是用户报的 bug）。
///
/// 【判定依据】老数据里 endDate 始终由用户真实填写（未填时被写成 startDate），
/// 因此凡是 endDate >= startDate 的记录都视为"已有有效归期"→ 已完成。
/// 这会把极少数"当时确实没填归期"的老旅程也标成完成，
/// 但它们在数据上与一日行程无法区分；用户可在详情页菜单手动改回"进行中"。
Future<int> repairTripCompletionFlags(db.AppDatabase database) async {
  const flagKey = 'trip_completion_repaired_v2';
  if (await database.getSetting(flagKey) == '1') return 0;

  var repaired = 0;
  try {
    for (final t in await database.getAllTrips()) {
      if (t.isCompleted) continue;
      if (t.endDate.isBefore(t.startDate)) continue; // 异常数据不动
      await database.updateTrip(
        t.id,
        db.TripsCompanion(isCompleted: const Value(true)),
      );
      repaired++;
    }
    await database.setSetting(flagKey, '1');
    if (repaired > 0) debugPrint('旅程完成状态回填 $repaired 条');
  } catch (e) {
    debugPrint('repairTripCompletionFlags 跳过: $e'); // 不写标记，下次可重试
  }
  return repaired;
}
