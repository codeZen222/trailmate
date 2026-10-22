import 'package:drift/drift.dart';

import 'log_table.dart';
import 'trip_table.dart';

/// 旅行消费记录。
///
/// 金额一律以「分」为单位的整数存储（amountCents）：
/// SQLite 的 REAL 是二进制浮点，累加上千笔会出现分位误差且难以排查，
/// 存整数分可保证求和永远精确，仅在输入/显示时与元互转。
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属旅程（必填：本功能只记旅行消费）。删旅程时级联删除其消费记录。
  IntColumn get tripId =>
      integer().references(Trips, #id, onDelete: KeyAction.cascade)();

  /// 可选关联到某篇日志。日志删除时置空，不影响消费记录本身。
  IntColumn get logId =>
      integer().nullable().references(Logs, #id, onDelete: KeyAction.setNull)();

  /// 分类 key，见 ExpenseCategory。
  TextColumn get category => text().withLength(min: 1, max: 24)();

  IntColumn get amountCents => integer()();

  TextColumn get note => text().nullable()();

  DateTimeColumn get expenseDate => dateTime()();

  DateTimeColumn get createdAt => dateTime()();
}
