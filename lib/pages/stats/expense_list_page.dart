import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/expense_model.dart';
import '../../providers/expense_provider.dart';
import '../../providers/trip_provider.dart';
import '../../utils/date_utils.dart' as date_utils;
import '../../widgets/expense/quick_add_sheet.dart';

/// 消费明细页：按日期分组，左滑删除，下拉刷新。
class ExpenseListPage extends ConsumerWidget {
  const ExpenseListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final expensesAsync = ref.watch(expensesProvider);
    final trips = ref.watch(tripListProvider).valueOrNull ?? const [];
    final tripNames = {for (final t in trips) t.id: t.destination};

    return Scaffold(
      appBar: AppBar(
        title: const Text('消费明细'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '记一笔',
            onPressed: () => QuickAddSheet.show(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => QuickAddSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (list) {
          if (list.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(expensesProvider),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.3,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined, size: 44, color: cs.outlineVariant),
                          const SizedBox(height: 10),
                          Text('还没有消费记录',
                              style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // 按自然日分组（列表已按日期倒序）
          final groups = <DateTime, List<Expense>>{};
          for (final e in list) {
            final key = DateTime(e.expenseDate.year, e.expenseDate.month, e.expenseDate.day);
            groups.putIfAbsent(key, () => []).add(e);
          }
          final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(expensesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: days.length,
              itemBuilder: (context, di) {
                final day = days[di];
                final items = groups[day]!;
                final dayTotal = items.fold<int>(0, (s, e) => s + e.amountCents);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Row(
                        children: [
                          Text(date_utils.formatDateChinese(day),
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text('小计 ${Money.format(dayTotal)}',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: cs.outline)),
                        ],
                      ),
                    ),
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, indent: 62, color: cs.outlineVariant.withAlpha(70)),
                            _row(context, ref, items[i], tripNames),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, Expense e, Map<int, String> tripNames) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dismissible(
      key: ValueKey('expense-${e.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: cs.errorContainer,
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      onDismissed: (_) async {
        await deleteExpense(ref, e.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除：${e.category.label} ${Money.format(e.amountCents)}')),
          );
        }
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: e.category.color.withAlpha(34),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(child: Text(e.category.emoji, style: const TextStyle(fontSize: 17))),
        ),
        title: Text(
          (e.note ?? '').isEmpty ? e.category.label : e.note!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          tripNames[e.tripId] ?? '未知旅程',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
        ),
        trailing: Text(
          '-${Money.format(e.amountCents)}',
          style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700, color: e.category.color),
        ),
      ),
    );
  }
}
