import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/trip_provider.dart';
import '../../providers/footprint_provider.dart';
import '../../providers/achievement_provider.dart';
import '../../core/router/app_router.dart';
import 'widgets/stats_card.dart';
import 'widgets/achievement_tile.dart';
import 'expense_section.dart';
import '../../services/achievement_flow.dart';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) runAchievementCheck(ref, context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 统计卡片
            Consumer(
              builder: (context, ref, _) {
                final tripsAsync = ref.watch(tripListProvider);
                final fpAsync = ref.watch(footprintListProvider);

                return tripsAsync.when(
                  data: (trips) {
                    return fpAsync.when(
                      data: (footprints) {
                        final totalDays = trips.fold<int>(0, (sum, t) {
                          return sum + t.endDate.difference(t.startDate).inDays + 1;
                        });
                        final countries = footprints.map((f) => f.country).toSet().length;

                        return Row(
                          children: [
                            Expanded(child: StatsCard(
                              icon: '🏙️',
                              label: '已点亮城市',
                              value: '${footprints.length}',
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: StatsCard(
                              icon: '🌍',
                              label: '到访国家',
                              value: '$countries',
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: StatsCard(
                              icon: '📅',
                              label: '旅行天数',
                              value: '$totalDays',
                            )),
                          ],
                        );
                      },
                      loading: () => const SizedBox(),
                      error: (_, __) => const SizedBox(),
                    );
                  },
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                );
              },
            ),
            const SizedBox(height: 20),

            // 年度回顾入口
            Card(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('📅', style: TextStyle(fontSize: 24)),
                ),
                title: const Text('年度旅行回顾'),
                subtitle: Text('${DateTime.now().year} 年', style: TextStyle(color: colorScheme.outline)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pushNamed(context, AppRouter.yearReview, arguments: {
                    'year': DateTime.now().year,
                  });
                },
              ),
            ),
            const SizedBox(height: 20),

            // 旅行消费
            const ExpenseSection(),
            const SizedBox(height: 20),

            // 成就
            Row(
              children: [
                Text('成就', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, AppRouter.achievement),
                  child: const Text('查看全部'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Consumer(
              builder: (context, ref, _) {
                final achievementsAsync = ref.watch(achievementListProvider);
                return achievementsAsync.when(
                  data: (achievements) {
                    if (achievements.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.emoji_events_outlined, size: 48, color: colorScheme.outline),
                                const SizedBox(height: 8),
                                Text('还没有解锁成就', style: TextStyle(color: colorScheme.outline)),
                                const SizedBox(height: 4),
                                Text('继续旅行，解锁更多成就！', style: TextStyle(color: colorScheme.outline, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.85,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: achievements.length > 6 ? 6 : achievements.length,
                      itemBuilder: (context, index) {
                        return AchievementTile(achievement: achievements[index]);
                      },
                    );
                  },
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}