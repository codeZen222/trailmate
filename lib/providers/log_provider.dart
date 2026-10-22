import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart' as db;
import '../models/log_model.dart';
import 'database_provider.dart';

final logsByTripProvider = StreamProvider.family<List<Log>, int>((ref, tripId) {
  final database = ref.watch(databaseProvider);
  return database.watchLogsByTrip(tripId).map((rows) => rows.map((r) => Log(
    id: r.id,
    tripId: r.tripId,
    date: r.date,
    title: r.title,
    content: r.content,
    weather: r.weather,
    moodTag: r.moodTag,
    rating: r.rating,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  )).toList());
});

final logByIdProvider = FutureProvider.family<Log?, int>((ref, id) async {
  final database = ref.watch(databaseProvider);
  final r = await database.getLogById(id);
  if (r == null) return null;
  return Log(
    id: r.id,
    tripId: r.tripId,
    date: r.date,
    title: r.title,
    content: r.content,
    weather: r.weather,
    moodTag: r.moodTag,
    rating: r.rating,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );
});

Future<int> createLog(WidgetRef ref, {
  required int tripId,
  required DateTime date,
  String? title,
  required String content,
  String? weather,
  String? moodTag,
  int? rating,
}) async {
  final database = ref.read(databaseProvider);
  final now = DateTime.now();
  return await database.insertLog(db.LogsCompanion(
    tripId: Value(tripId),
    date: Value(date),
    title: Value(title),
    content: Value(content),
    weather: Value(weather),
    moodTag: Value(moodTag),
    rating: Value(rating),
    createdAt: Value(now),
    updatedAt: Value(now),
  ));
}

Future<void> updateLog(WidgetRef ref, Log log) async {
  final database = ref.read(databaseProvider);
  final changed = await database.updateLog(log.id, db.LogsCompanion(
    tripId: Value(log.tripId),
    date: Value(log.date),
    title: Value(log.title),
    content: Value(log.content),
    weather: Value(log.weather),
    moodTag: Value(log.moodTag),
    rating: Value(log.rating),
    updatedAt: Value(DateTime.now()),
  ));
  if (changed == 0) {
    throw StateError('未找到要更新的日志（id=${log.id}）');
  }
}

Future<void> deleteLog(WidgetRef ref, int logId) async {
  final database = ref.read(databaseProvider);
  // images / locations 声明了随日志级联，但老库可能建于外键开启之前；
  // 显式删一遍保证行为一致，并顺带清理磁盘上的图片文件。
  final imgs = await database.getImagesByLogOrdered(logId);
  await database.deleteLog(logId);
  for (final path in imgs.map((i) => i.filePath)) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
