import 'package:drift/drift.dart';

class Achievements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get icon => text()();
  TextColumn get condition => text()();
  /// 稀有度：common / rare / epic / legend。
  TextColumn get rarity => text().withDefault(const Constant('common'))();
  DateTimeColumn get unlockedAt => dateTime().nullable()();
}