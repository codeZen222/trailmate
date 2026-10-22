import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../database/app_database.dart' as db;
import '../../../models/expense_model.dart';
import '../../../models/footprint_model.dart';
import '../../../providers/database_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../utils/date_utils.dart' as date_utils;
import '../../../utils/geo_naming.dart';

class CityDetailSheet extends ConsumerWidget {
  final Footprint footprint;

  const CityDetailSheet({super.key, required this.footprint});

  /// 统一入口：从底部弹出城市详情。
  static Future<void> show(BuildContext context, Footprint fp) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CityDetailSheet(footprint: fp),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部拖拽条
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: 32, height: 4,
              decoration: BoxDecoration(color: theme.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  footprint.cityName.substring(0, 1),
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(footprint.cityName, style: theme.textTheme.titleLarge),
                    Text(
                      () {
                        final prov = provinceOf(footprint.cityName);
                        return prov == null
                            ? footprint.country
                            : '$prov · ${footprint.country}';
                      }(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _InfoBox(theme: theme, label: '首次到访', value: '${footprint.firstVisitedAt.year}年${footprint.firstVisitedAt.month}月'),
              const SizedBox(width: 12),
              _InfoBox(theme: theme, label: '到访次数', value: '${footprint.visitCount} 次'),
              const SizedBox(width: 12),
              // 该城消费合计（目的地含此城市名的所有旅程）
              FutureBuilder<int>(
                future: ref.read(databaseProvider).getExpenseCentsByCity(footprint.cityName),
                builder: (context, snap) => _InfoBox(
                  theme: theme,
                  label: '花费',
                  value: snap.hasData && snap.data! > 0
                      ? Money.format(snap.data!)
                      : '未记账',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Phase 2.3：关联旅程列表
          Text('相关旅程', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Flexible(
            child: FutureBuilder<List<db.Trip>>(
              future: ref.read(databaseProvider).getTripsByCity(footprint.cityName),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final trips = snap.data!;
                if (trips.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('暂无关联旅程', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    ),
                  );
                }
                return SingleChildScrollView(
                  child: Column(
                    children: trips.map((t) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.luggage_outlined, color: theme.colorScheme.primary),
                      title: Text(t.destination),
                      subtitle: Text(date_utils.formatDateRange(t.startDate, t.endDate)),
                      trailing: Text('${t.endDate.difference(t.startDate).inDays + 1}天', style: theme.textTheme.bodySmall),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, AppRouter.tripDetail, arguments: {'tripId': t.id});
                      },
                    )).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final ThemeData theme;
  final String label;
  final String value;
  const _InfoBox({required this.theme, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
