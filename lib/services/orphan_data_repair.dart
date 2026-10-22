import 'package:flutter/foundation.dart';
import '../database/app_database.dart' as db;

/// 一次性清理历史孤儿数据。
///
/// 【为什么需要】SQLite 的 `PRAGMA foreign_keys` 默认关闭且按连接生效，
/// 而本项目此前从未开启 —— 表定义里的 onDelete: cascade 实际从未生效。
/// 于是删除旅程只删了 trips 一行：日志、消费记录留在库里继续参与统计，
/// 图片行指向已不存在的日志。这正是用户看到的「删了旅程但旅行消费没更新」。
///
/// 现在连接层已开启外键、删除也改为显式级联（AppDatabase.deleteTripCascade），
/// 本方法只负责把**旧版本已经造成的存量脏数据**清掉，跑一次即可。
Future<int> repairOrphanData(db.AppDatabase database) async {
  const flagKey = 'orphan_data_repaired_v1';
  if (await database.getSetting(flagKey) == '1') return 0;

  var removed = 0;
  try {
    removed = await database.deleteOrphanRows();
    await database.setSetting(flagKey, '1');
    if (removed > 0) debugPrint('孤儿数据清理 $removed 行');
  } catch (e) {
    debugPrint('repairOrphanData 跳过: $e'); // 不写标记，下次启动可重试
  }
  return removed;
}
