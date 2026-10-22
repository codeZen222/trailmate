import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/trip_provider.dart';
import '../../providers/log_provider.dart';
import '../../providers/database_provider.dart';
import '../../database/app_database.dart' as db2;
import '../../models/trip_model.dart';
import '../../models/log_model.dart';
import '../../core/router/app_router.dart';
import '../../utils/date_utils.dart' as date_utils;
import 'widgets/trip_header.dart';
import 'widgets/timeline_tile.dart';
import '../../widgets/expense/trip_expense_strip.dart';

class TripDetailPage extends ConsumerStatefulWidget {
  final int tripId;

  const TripDetailPage({super.key, required this.tripId});

  @override
  ConsumerState<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends ConsumerState<TripDetailPage> {
  /// 手动切换「已完成 / 进行中」。
  ///
  /// 【为什么保留这个入口】老数据里"没填归期"与"当天往返的一日行程"
  /// 在 endDate 上完全同形，回填脚本只能一律按已完成处理；
  /// 真属于前者的少数记录由用户在这里一键改回。
  Future<void> _toggleCompleted(Trip trip) async {
    try {
      final database = ref.read(databaseProvider);
      await database.updateTrip(
        trip.id,
        db2.TripsCompanion(isCompleted: Value(!trip.isCompleted)),
      );
      ref.invalidate(tripByIdProvider(trip.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(!trip.isCompleted ? '已标记为完成' : '已标记为进行中')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      bottomNavigationBar: _buildBottomBar(context, widget.tripId),
      body: Consumer(
        builder: (context, ref, _) {
          final tripAsync = ref.watch(tripByIdProvider(widget.tripId));
          return tripAsync.when(
            data: (trip) {
              if (trip == null) {
                return const Center(child: Text('旅程不存在'));
              }
              return _buildBody(context, colorScheme, trip);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败: $e')),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme, Trip trip) {
    return CustomScrollView(
      slivers: [
        TripHeader(
          trip: trip,
          onBack: () => Navigator.pop(context),
          onEdit: () {
            Navigator.pushNamed(
              context,
              AppRouter.tripCreate,
              arguments: {'tripId': trip.id},
            );
          },
          onDelete: () => _confirmDelete(context, trip),
          onShare: () {
            Navigator.pushNamed(
              context,
              AppRouter.shareCard,
              arguments: {'tripId': trip.id},
            );
          },
          onRatingChanged: (rating) async {
            final updated = trip.copyWith(rating: rating);
            try {
              await updateTrip(ref, updated);
              // 详情页是 FutureProvider，不失效会显示旧分数
              ref.invalidate(tripByIdProvider(trip.id));
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('评分保存失败：$e')),
              );
            }
          },
          onCoverTap: () {},
          onToggleCompleted: () => _toggleCompleted(trip),
        ),
        // 本旅程消费条
        SliverToBoxAdapter(
          child: TripExpenseStrip(tripId: widget.tripId, tripDays: trip.durationDays),
        ),
        // 日志时间线
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: Consumer(
            builder: (context, ref, _) {
              final theme = Theme.of(context);
              final logsAsync = ref.watch(logsByTripProvider(widget.tripId));
              return logsAsync.when(
                data: (logs) {
                  if (logs.isEmpty) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_note_outlined, size: 64, color: colorScheme.outline),
                            const SizedBox(height: 16),
                            Text('还没有日志', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text('开始记录你的旅程点滴', style: TextStyle(color: colorScheme.outline)),
                          ],
                        ),
                      ),
                    );
                  }
                  // 按日期分组
                  final grouped = <String, List<Log>>{};
                  for (final log in logs) {
                    final key = date_utils.formatDate(log.date);
                    grouped.putIfAbsent(key, () => []).add(log);
                  }
                  final sortedDates = grouped.keys.toList()
                    ..sort((a, b) => b.compareTo(a));

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final dateKey = sortedDates[index];
                        final dayLogs = grouped[dateKey]!;
                        return TimelineTile(
                          dateKey: dateKey,
                          logs: dayLogs,
                          onLogTap: (log) {
                            Navigator.pushNamed(
                              context,
                              AppRouter.logDetail,
                              arguments: {
                                'logId': log.id,
                                'tripId': widget.tripId,
                              },
                            );
                          },
                        );
                      },
                      childCount: sortedDates.length,
                    ),
                  );
                },
                loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => SliverFillRemaining(
                  child: Center(child: Text('加载失败: $e')),
                ),
              );
            },
          ),
        ),
        // 底部空间
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

  void _confirmDelete(BuildContext context, Trip trip) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除旅程'),
        content: Text('确定要删除「${trip.destination}」吗？\n所有相关日志和图片也将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final destination = trip.destination;
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              // 等删除真正完成再关对话框：失败时保留界面并如实提示，
              // 而不是先弹"已删除"再留下没删干净的数据。
              try {
                await deleteTrip(ref, trip.id);
              } catch (e) {
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                messenger.showSnackBar(SnackBar(content: Text('删除失败：$e')));
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text('已删除「$destination」')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, int tripId) {
    final defaultDate = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRouter.logEditor,
                  arguments: {
                    'tripId': tripId,
                    'date': defaultDate,
                  },
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('添加日志'),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRouter.shareCard,
                arguments: {'tripId': tripId},
              );
            },
            icon: const Icon(Icons.share),
            label: const Text('分享'),
          ),
        ],
      ),
    );
  }
}