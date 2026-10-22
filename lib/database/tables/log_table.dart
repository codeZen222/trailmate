import 'package:drift/drift.dart';

import 'trip_table.dart';

class Logs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tripId => integer().references(Trips, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get date => dateTime()();
  TextColumn get title => text().nullable()();
  TextColumn get content => text()();
  TextColumn get weather => text().nullable()();
  /// 心情标签（存 MoodType.key，如 'rain'）；null 表示未选心情。
  TextColumn get moodTag => text().nullable()();
  IntColumn get rating => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}