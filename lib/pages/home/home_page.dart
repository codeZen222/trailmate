import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/trip_provider.dart';
import '../../providers/database_provider.dart';
import '../../models/trip_model.dart';
import '../../core/router/app_router.dart';
import '../../utils/date_utils.dart' as date_utils;
import '../footprint/province_map_page.dart';
import '../stats/stats_page.dart';
import '../settings/settings_page.dart';
import 'widgets/trip_card.dart';
import 'widgets/memory_card.dart';
import 'widgets/timeline_row.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final pages = [
      _buildHomeTab(context, colorScheme),
      const ProvinceMapPage(),
      const StatsPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: '足迹'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: '统计'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context, ColorScheme colorScheme) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: Consumer(
            builder: (context, ref, _) {
              final tripsAsync = ref.watch(tripListProvider);
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // 顶部标题栏
                  SliverAppBar(
                    pinned: true,
                    toolbarHeight: 64,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('我的旅程', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        Text('记录每一段走过的路', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
                      ],
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => showSearch(
                          context: context,
                          delegate: _TripSearchDelegate(ref),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.smart_toy_outlined),
                        tooltip: '旅行助手',
                        onPressed: () => Navigator.pushNamed(context, AppRouter.aiChat),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => Navigator.pushNamed(context, AppRouter.settings),
                      ),
                    ],
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    sliver: tripsAsync.when(
                      data: (trips) {
                        if (trips.isEmpty) {
                          return SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmptyState(context, colorScheme),
                          );
                        }
                        final memory = ref.watch(todayMemoryProvider).valueOrNull;
                        final items = <Widget>[
                          if (memory != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: MemoryCard(
                                destination: memory.destination,
                                year: memory.startDate.year,
                                description: memory.notes?.isNotEmpty == true
                                    ? memory.notes!
                                    : date_utils.formatDateRange(memory.startDate, memory.endDate),
                                onTap: () => Navigator.pushNamed(
                                  context, AppRouter.tripDetail,
                                  arguments: {'tripId': memory.id},
                                ),
                              ),
                            ),
                          ...List.generate(trips.length, (i) {
                            final t = trips[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TimelineRow(
                                isFirst: i == 0,
                                isLast: i == trips.length - 1,
                                dotColor: colorScheme.primary,
                                child: TripCard(
                                  trip: t,
                                  onTap: () => Navigator.pushNamed(
                                    context, AppRouter.tripDetail,
                                    arguments: {'tripId': t.id},
                                  ),
                                  onLongPress: () => _confirmDeleteTrip(context, t),
                                ),
                              ),
                            );
                          }),
                        ];
                        return SliverList(delegate: SliverChildListDelegate(items));
                      },
                      loading: () => const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => SliverFillRemaining(
                        child: Center(child: Text('加载失败: $e')),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRouter.tripCreate),
        icon: const Icon(Icons.add),
        label: const Text('新建旅程'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primaryContainer.withAlpha(90),
              ),
              child: Icon(
                Icons.travel_explore_outlined,
                size: 56,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '还没有旅程记录',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击下方按钮，开始记录你的旅行故事',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => Navigator.pushNamed(context, AppRouter.tripCreate),
              icon: const Icon(Icons.add),
              label: const Text('创建首个旅程'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTrip(BuildContext context, Trip trip) {
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
}

class _TripSearchDelegate extends SearchDelegate<String?> {
  final WidgetRef ref;

  _TripSearchDelegate(this.ref);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchList(context);

  Widget _buildSearchList(BuildContext context) {
    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('输入目的地搜索', style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
    }

    return FutureBuilder(
      future: ref.read(databaseProvider).searchTrips(query),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final results = snap.data!;
        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text('未找到「$query」相关旅程'),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final trip = results[index];
            return ListTile(
              leading: Icon(Icons.luggage, color: Theme.of(context).colorScheme.primary),
              title: Text(trip.destination),
              subtitle: Text(date_utils.formatDateRange(trip.startDate, trip.endDate)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                close(context, null);
                Navigator.pushNamed(
                  context,
                  AppRouter.tripDetail,
                  arguments: {'tripId': trip.id},
                );
              },
            );
          },
        );
      },
    );
  }
}