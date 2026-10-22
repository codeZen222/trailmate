import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/footprint_model.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/footprint_provider.dart';
import '../../../services/location_service.dart';
import '../../../utils/geo_coder.dart';

/// 给坐标缺失的城市手动补坐标。
///
/// 【为什么需要】离线坐标表只收录了约 240 个地名，
/// 不在表里的目的地（冷门县城、境外小镇）会被写成 (0,0)，
/// 于是**永远不会出现在地图上**。这里提供一个零成本的补救入口
/// （用户此前决定不接高德 Web 服务 geocode）。
class FixCoordsSheet extends ConsumerStatefulWidget {
  const FixCoordsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const FixCoordsSheet(),
    );
  }

  @override
  ConsumerState<FixCoordsSheet> createState() => _FixCoordsSheetState();
}

class _FixCoordsSheetState extends ConsumerState<FixCoordsSheet> {
  List<Footprint> _pending = const [];
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(databaseProvider).getFootprintsWithoutCoords();
    if (!mounted) return;
    setState(() {
      _pending = rows.map((r) => Footprint(
            id: r.id,
            cityName: r.cityName,
            country: r.country,
            latitude: r.latitude,
            longitude: r.longitude,
            visitCount: r.visitCount,
            firstVisitedAt: r.firstVisitedAt,
            latestVisitedAt: r.latestVisitedAt,
          )).toList();
      _loading = false;
    });
  }

  Future<void> _apply(int id, double lat, double lon, String city) async {
    setState(() => _working = true);
    await ref.read(databaseProvider).setFootprintCoords(id, lat, lon);
    // 标记"补过坐标"（成就「坐标修复师」）
    await ref.read(databaseProvider).markAchievementFlag('fixed_coords');
    ref.invalidate(footprintListProvider);
    if (!mounted) return;
    setState(() => _working = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$city 坐标已补全，现在会出现在地图上了')),
    );
    _load();
  }

  Future<void> _pickFor(Footprint fp) async {
    final result = await showModalBottomSheet<_CoordPick>(
      context: context,
      builder: (_) => _CitySearchSheet(city: fp.cityName),
    );
    if (result == null) return;
    await _apply(fp.id, result.lat, result.lon, fp.cityName);
  }

  Future<void> _useCurrentLocation(Footprint fp) async {
    setState(() => _working = true);
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没拿到定位，请检查定位权限')),
          );
        }
        return;
      }
      await _apply(fp.id, pos.latitude, pos.longitude, fp.cityName);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('补全城市坐标',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('这些城市当初没能解析出坐标，所以地图上看不到',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
            const SizedBox(height: 14),
            if (_loading || _pending.isEmpty)
                SizedBox(
                  height: 140,
                  child: Center(
                    child: _loading
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 34, color: cs.primary),
                              const SizedBox(height: 8),
                              Text('所有城市都有坐标了',
                                  style: theme.textTheme.bodyMedium),
                            ],
                          ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _pending.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: cs.outlineVariant.withAlpha(70)),
                    itemBuilder: (context, i) {
                      final fp = _pending[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.location_off_outlined, size: 20),
                        title: Text(fp.cityName),
                        subtitle: Text('到访 ${fp.visitCount} 次',
                            style: theme.textTheme.bodySmall),
                        trailing: _working
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right),
                        onTap: _working ? null : () => _pickFor(fp),
                      );
                    },
                  ),
                ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pending.isEmpty || _working
                        ? null
                        : () => _useCurrentLocation(_pending.first),
                    icon: const Icon(Icons.my_location, size: 16),
                    label: Text('用当前定位补第一个'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordPick {
  const _CoordPick(this.lat, this.lon);
  final double lat;
  final double lon;
}

/// 在离线地名表里搜索，选中即返回坐标。
class _CitySearchSheet extends StatefulWidget {
  const _CitySearchSheet({required this.city});

  final String city;

  @override
  State<_CitySearchSheet> createState() => _CitySearchSheetState();
}

class _CitySearchSheetState extends State<_CitySearchSheet> {
  late final TextEditingController _input = TextEditingController(text: widget.city);
  var _results = const <({String name, double lat, double lon})>[];

  @override
  void initState() {
    super.initState();
    _search(widget.city);
    // 表里没有时，先给一个直接命中尝试
    if (_results.isEmpty) {
      final hit = GeoCoder.lookup(widget.city);
      if (hit != null) {
        _results = [
          (name: widget.city, lat: hit.lat, lon: hit.lon)
        ];
      }
    }
  }

  void _search(String q) {
    setState(() => _results = GeoCoder.search(q));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('为「${widget.city}」选择坐标',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: _input,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索地名',
                prefixIcon: const Icon(Icons.search, size: 18),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            if (_results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('离线词表里没有这个地名，试试别的写法',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final r = _results[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined, size: 18),
                      title: Text(r.name),
                      subtitle: Text(
                          '${r.lat.toStringAsFixed(3)}, ${r.lon.toStringAsFixed(3)}',
                          style: theme.textTheme.bodySmall),
                      onTap: () => Navigator.pop(context, _CoordPick(r.lat, r.lon)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
