import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/footprint_model.dart';
import '../../providers/footprint_provider.dart';
import '../../providers/province_stats_provider.dart';
import '../../utils/geo_naming.dart';
import 'widgets/city_detail_sheet.dart';

/// 足迹清单页：按省分组的到访列表。
///
/// 【为什么现在才有内容】之前这页只有一句占位文案"已整合到足迹地图页"，
/// 但地图页 FAB「已点亮 N 省」和年度回顾页都会跳转进来——两个入口都通向
/// 死胡同。地图适合"看形状"，清单适合"挨个看细节、找城市、点进详情"，
/// 两者是互补关系，不是重复。
///
/// 交互：
/// - 点省份行 → pop 回传省简称，地图页联动高亮该省
/// - 点城市 chip → 弹城市详情（CityDetailSheet）
class FootprintListPage extends ConsumerWidget {
  const FootprintListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final stats = ref.watch(provinceStatsProvider);
    final footprints =
        ref.watch(footprintListProvider).valueOrNull ?? const <Footprint>[];
    final unassigned = ref.watch(unassignedCitiesProvider);

    final visited = stats.total.where((s) => s.visited).toList()
      ..sort((a, b) => b.visitCount.compareTo(a.visitCount));

    // 展示名 -> 足迹对象。stat.cities / unassigned 存的可能是剥掉
    // 省名的展示名（如"济阳"），点击时要用它找回完整足迹。
    final byLabel = <String, Footprint>{
      for (final f in footprints) (cityOf(f.cityName) ?? f.cityName): f,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('足迹清单'),
      ),
      body: footprints.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined,
                      size: 56, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('还没有足迹', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text('记录旅程后，走过的省份会点亮在这里',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                _SummaryHeader(
                  theme: theme,
                  provinces: stats.visitedProvinces,
                  total: stats.provinceCount,
                  cities: footprints.length,
                ),
                const SizedBox(height: 12),
                for (final s in visited)
                  _ProvinceCard(
                    theme: theme,
                    dark: dark,
                    stat: s,
                    byLabel: byLabel,
                    onLocate: () =>
                        Navigator.pop(context, s.shape.shortName),
                    onCity: (f) => CityDetailSheet.show(context, f),
                  ),
                if (unassigned.isNotEmpty)
                  _UnassignedCard(
                    theme: theme,
                    names: unassigned,
                    byLabel: byLabel,
                    onCity: (f) => CityDetailSheet.show(context, f),
                  ),
              ],
            ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.theme,
    required this.provinces,
    required this.total,
    required this.cities,
  });

  final ThemeData theme;
  final int provinces;
  final int total;
  final int cities;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(90),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.travel_explore, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '已点亮 $provinces / $total 个省 · $cities 座城市',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProvinceCard extends StatelessWidget {
  const _ProvinceCard({
    required this.theme,
    required this.dark,
    required this.stat,
    required this.byLabel,
    required this.onLocate,
    required this.onCity,
  });

  final ThemeData theme;
  final bool dark;
  final ProvinceStat stat;
  final Map<String, Footprint> byLabel;
  final VoidCallback onLocate;
  final void Function(Footprint f) onCity;

  @override
  Widget build(BuildContext context) {
    final fill = ProvinceStats.fillFor(stat.tier, dark: dark);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 省份头行：点击回地图定位高亮
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: onLocate,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: fill.color,
                      border: Border.all(color: fill.stroke, width: 1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(stat.shape.shortName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: fill.color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${stat.visitCount} 次 · ${stat.cities.length} 城',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: '回地图定位',
                    child: IconButton(
                      icon: Icon(Icons.my_location_outlined,
                          size: 18, color: theme.colorScheme.primary),
                      onPressed: onLocate,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 城市 chips
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final c in stat.cities)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(c),
                    onPressed: () {
                      final f = byLabel[c];
                      if (f != null) onCity(f);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 无法归属到省的城市，如实列出而不是硬塞进某省。
class _UnassignedCard extends StatelessWidget {
  const _UnassignedCard({
    required this.theme,
    required this.names,
    required this.byLabel,
    required this.onCity,
  });

  final ThemeData theme;
  final List<String> names;
  final Map<String, Footprint> byLabel;
  final void Function(Footprint f) onCity;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFFFC85C).withAlpha(140)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline,
                  size: 16, color: Color(0xFFE0A63D)),
              const SizedBox(width: 6),
              Text('以下 ${names.length} 城暂无法归到省',
                  style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final n in names)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(cityOf(n) ?? n),
                  onPressed: () {
                    final f = byLabel[cityOf(n) ?? n];
                    if (f != null) onCity(f);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
