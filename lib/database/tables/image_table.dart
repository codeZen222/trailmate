import 'package:drift/drift.dart';

import 'log_table.dart';

class Images extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get logId => integer().references(Logs, #id, onDelete: KeyAction.cascade)();
  TextColumn get filePath => text()();
  TextColumn get aiDescription => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}