import 'package:drift/drift.dart';

class Footprints extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cityName => text()();
  TextColumn get country => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  DateTimeColumn get firstVisitedAt => dateTime()();
  IntColumn get visitCount => integer().withDefault(const Constant(1))();
  DateTimeColumn get latestVisitedAt => dateTime()();
}