import 'package:drift/drift.dart';

import 'log_table.dart';

class Locations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get logId => integer().references(Logs, #id, onDelete: KeyAction.cascade).unique()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get cityName => text().nullable()();
  TextColumn get placeName => text().nullable()();
  TextColumn get address => text().nullable()();
}