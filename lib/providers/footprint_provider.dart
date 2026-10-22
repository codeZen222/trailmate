import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/footprint_model.dart';
import 'database_provider.dart';

final footprintListProvider = StreamProvider<List<Footprint>>((ref) {
  final database = ref.watch(databaseProvider);
  return database.watchAllFootprints().map((rows) => rows.map((r) => Footprint(
    id: r.id,
    cityName: r.cityName,
    country: r.country,
    latitude: r.latitude,
    longitude: r.longitude,
    firstVisitedAt: r.firstVisitedAt,
    visitCount: r.visitCount,
    latestVisitedAt: r.latestVisitedAt,
  )).toList());
});