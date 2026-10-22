import 'package:drift/drift.dart';

class Trips extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get destination => text()();
  TextColumn get coverPath => text().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  IntColumn get rating => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}