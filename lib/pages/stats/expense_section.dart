import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/expense_model.dart';
import '../../providers/expense_provider.dart';
import '../../services/expense_stats.dart';
import '../../widgets/charts/bar_chart.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/expense/quick_add_sheet.dart';
import 'expense_list_page.dart';

/// 统计页内的「旅行消费」区块：总览 + 分类环形图 + 月度趋势 + 旅程排行。
class ExpenseSection extends ConsumerWidget {
  const ExpenseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final stats = ref.watch(expenseStatsProvider);
    final loading = ref.watch(expensesProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('💰 旅行消费', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: () => QuickAddSheet.show(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('记一笔'),
            ),
          ],
        ),
        Card(
          child: loading && stats.isEmpty
              ? const SizedBox(
                  height: 120, child: Center(child: CircularProgressIndicator()))
              : stats.isEmpty
                  ? _EmptyHint(onAdd: () => QuickAddSheet.show(context))
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _overview(theme, stats),
                          const Divider(height: 26),
                          _categoryBlock(theme, cs, stats),
                          const Divider(height: 26),
                          Text('近 6 个月', style: theme.textTheme.labelMedium),
                          const SizedBox(height: 8),
                          BarChart(
                            items: [
                              for (final b in stats.byMonth)
                                BarItem(label: b.label, value: b.cents / 100),
                            ],
                            valueFormatter: (v) => v <= 0 ? '' : v.round().toString(),
                          ),
                          if (stats.byTrip.length > 1) ...[
                            const Divider(height: 26),
                            Text('旅程花费排行', style: theme.textTheme.labelMedium),
                            const SizedBox(height: 10),
                            RankBars(
                              items: [
                                for (final b in stats.byTrip.take(5))
                                  BarItem(label: b.label, value: b.cents / 100),
                              ],
                              valueFormatter: (v) => Money.format((v * 100).round()),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ExpenseListPage()),
                              ),
                              child: const Text('查看全部明细 ›'),
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  /// 四格总览。
  Widget _overview(ThemeData theme, ExpenseStats s) {
    Widget cell(String label, String value, {String? sub}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary)),
              const SizedBox(height: 2),
              Text(label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              if (sub != null)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outlineVariant)),
            ],
          ),
        );

    final largest = s.largest;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cell('总支出', Money.format(s.totalCents)),
        cell('本月', Money.format(s.monthCents)),
        cell('日均', Money.format(s.dailyAverageCents), sub: '${s.activeDays} 天有消费'),
        cell('最大单笔', largest == null ? '—' : Money.format(largest.amountCents),
            sub: largest?.category.label),
      ],
    );
  }

  /// 环形图 + 图例。
  Widget _categoryBlock(ThemeData theme, ColorScheme cs, ExpenseStats s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DonutChart(
          size: 118,
          thickness: 20,
          centerTitle: '共 ${s.count} 笔',
          centerValue: Money.format(s.totalCents, withSymbol: true),
          slices: [
            for (final b in s.byCategory)
              DonutSlice(
                label: b.label,
                value: b.cents.toDouble(),
                color: b.category?.color ?? cs.primary,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final b in s.byCategory.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 9, height: 9,
                        decoration: BoxDecoration(
                          color: b.category?.color ?? cs.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(b.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                      ),
                      Text('${(b.cents / s.totalCents * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.outline)),
                      const SizedBox(width: 6),
                      Text(Money.format(b.cents),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 38, color: cs.outlineVariant),
          const SizedBox(height: 10),
          Text('还没有记过消费', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text('记下旅途中的每一笔，回头看看钱都花在哪了',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('记第一笔'),
          ),
        ],
      ),
    );
  }
}
