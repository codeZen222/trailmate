import 'package:drift/drift.dart';

import 'trip_table.dart';
import 'tag_table.dart';

class TripTags extends Table {
  IntColumn get tripId => integer().references(Trips, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId => integer().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {tripId, tagId};
}