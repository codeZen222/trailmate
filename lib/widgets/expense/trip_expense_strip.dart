import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/expense_model.dart';
import '../../providers/expense_provider.dart';
import 'quick_add_sheet.dart';

/// 旅程详情页顶部的「本旅程消费」条：总额 + 笔数 + 日均 + 记一笔入口。
class TripExpenseStrip extends ConsumerWidget {
  const TripExpenseStrip({super.key, required this.tripId, required this.tripDays});

  final int tripId;
  final int tripDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final expenses = ref.watch(expensesByTripProvider(tripId)).valueOrNull ?? const [];
    final total = expenses.fold<int>(0, (s, e) => s + e.amountCents);

    // 主要分类（花费最高的一类）
    String? topCategory;
    if (expenses.isNotEmpty) {
      final byCat = <String, int>{};
      for (final e in expenses) {
        byCat[e.category.key] = (byCat[e.category.key] ?? 0) + e.amountCents;
      }
      final best = byCat.entries.reduce((a, b) => a.value >= b.value ? a : b);
      topCategory = ExpenseCategory.fromKey(best.key).label;
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => QuickAddSheet.show(context, tripId: tripId),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.account_balance_wallet_outlined,
                    size: 20, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      total > 0 ? Money.format(total) : '还没记消费',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      expenses.isEmpty
                          ? '点这里记下这趟花了多少'
                          : '${expenses.length} 笔 · 日均 ${Money.format((total / (tripDays <= 0 ? 1 : tripDays)).round())}'
                              '${topCategory == null ? '' : ' · 大头是$topCategory'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => QuickAddSheet.show(context, tripId: tripId),
                child: const Text('记一笔'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
