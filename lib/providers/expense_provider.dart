import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart' as db;
import '../models/expense_model.dart';
import '../services/expense_stats.dart';
import 'database_provider.dart';
import 'trip_provider.dart';

db.ExpensesCompanion _toCompanion(Expense e) => db.ExpensesCompanion(
      id: Value(e.id),
      tripId: Value(e.tripId),
      logId: Value(e.logId),
      category: Value(e.category.key),
      amountCents: Value(e.amountCents),
      note: Value(e.note),
      expenseDate: Value(e.expenseDate),
      createdAt: Value(e.createdAt),
    );

Expense _fromRow(db.Expense r) => Expense(
      id: r.id,
      tripId: r.tripId,
      logId: r.logId,
      category: ExpenseCategory.fromKey(r.category),
      amountCents: r.amountCents,
      note: r.note,
      expenseDate: r.expenseDate,
      createdAt: r.createdAt,
    );

/// 全部消费（流式，界面自动刷新）。
final expensesProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(databaseProvider).watchAllExpenses().map((r) => r.map(_fromRow).toList());
});

/// 某旅程的消费。
final expensesByTripProvider = StreamProvider.family<List<Expense>, int>((ref, tripId) {
  return ref
      .watch(databaseProvider)
      .watchExpensesByTrip(tripId)
      .map((rows) => rows.map(_fromRow).toList());
});

/// 聚合统计：消费明细 + 旅程名称一起算。
final expenseStatsProvider = Provider<ExpenseStats>((ref) {
  final expenses = ref.watch(expensesProvider).valueOrNull ?? const [];
  final trips = ref.watch(tripListProvider).valueOrNull ?? const [];
  final names = {for (final t in trips) t.id: t.destination};
  return ExpenseStats.from(expenses, tripNames: names);
});

/// 某旅程的花费合计（分）。
final tripExpenseTotalProvider = Provider.family<int, int>((ref, tripId) {
  final list = ref.watch(expensesByTripProvider(tripId)).valueOrNull ?? const [];
  return list.fold<int>(0, (s, e) => s + e.amountCents);
});

/// 记一笔。金额以「分」传入，避免浮点误差。
Future<int> createExpense(
  WidgetRef ref, {
  required int tripId,
  required ExpenseCategory category,
  required int amountCents,
  required DateTime date,
  int? logId,
  String? note,
}) {
  final now = DateTime.now();
  return ref.read(databaseProvider).insertExpense(db.ExpensesCompanion(
        tripId: Value(tripId),
        logId: Value(logId),
        category: Value(category.key),
        amountCents: Value(amountCents),
        note: Value((note ?? '').trim().isEmpty ? null : note!.trim()),
        expenseDate: Value(date),
        createdAt: Value(now),
      ));
}

Future<void> updateExpense(WidgetRef ref, Expense e) async {
  final changed =
      await ref.read(databaseProvider).updateExpense(e.id, _toCompanion(e));
  if (changed == 0) {
    throw StateError('未找到要更新的消费记录（id=${e.id}）');
  }
}

Future<void> deleteExpense(WidgetRef ref, int id) =>
    ref.read(databaseProvider).deleteExpense(id);
