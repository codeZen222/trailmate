import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/achievement_model.dart';
import '../../providers/achievement_provider.dart';
import '../../services/achievement_flow.dart';
import '../../services/achievement_rules.dart';
import '../../utils/date_utils.dart' as date_utils;

/// 成就页：按系列分组，显示稀有度与**真实进度**。
class AchievementPage extends ConsumerStatefulWidget {
  const AchievementPage({super.key});

  @override
  ConsumerState<AchievementPage> createState() => _AchievementPageState();
}

class _AchievementPageState extends ConsumerState<AchievementPage> {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _recheck();
  }

  Future<void> _recheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await runAchievementCheck(ref, context);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final async = ref.watch(achievementsWithProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('成就'),
        actions: [
          IconButton(
            icon: _checking
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            tooltip: '重新计算成就',
            onPressed: _recheck,
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (all) {
          if (all.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events_outlined, size: 64, color: cs.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('还没有成就数据'),
                ],
              ),
            );
          }

          final unlocked = all.where((a) => a.isUnlocked).length;
          final byName = {for (final a in all) a.name: a};

          return RefreshIndicator(
            onRefresh: _recheck,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _header(theme, cs, all.length, unlocked),
                const SizedBox(height: 20),
                for (final series in kSeriesOrder) ...[
                  _seriesHeader(theme, cs, series, byName),
                  const SizedBox(height: 10),
                  ..._seriesItems(theme, cs, series.$2, byName),
                  const SizedBox(height: 22),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(ThemeData theme, ColorScheme cs, int total, int unlocked) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primaryContainer, cs.tertiaryContainer],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$unlocked',
                  style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900, color: cs.onPrimaryContainer)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('/ $total 已解锁',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onPrimaryContainer.withAlpha(180))),
              ),
              const Spacer(),
              Text('${(unlocked / total * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : unlocked / total,
              minHeight: 7,
              backgroundColor: Colors.white.withAlpha(90),
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seriesHeader(
      ThemeData theme, ColorScheme cs, (String, String) series, Map<String, Achievement> byName) {
    final items = byName.values.where((a) => seriesOf(a.name) == series.$2).toList();
    final done = items.where((a) => a.isUnlocked).length;
    return Row(
      children: [
        Text(series.$1, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const Spacer(),
        Text('$done/${items.length}',
            style: theme.textTheme.labelMedium?.copyWith(
                color: done == items.length && items.isNotEmpty
                    ? cs.primary
                    : cs.outline,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  List<Widget> _seriesItems(ThemeData theme, ColorScheme cs, String series,
      Map<String, Achievement> byName) {
    final items = (byName.values.where((a) => seriesOf(a.name) == series).toList()
      ..sort((a, b) {
        // 已解锁的排前面，其次按稀有度
        if (a.isUnlocked != b.isUnlocked) return a.isUnlocked ? -1 : 1;
        return a.rarity.index.compareTo(b.rarity.index);
      }));
    return [for (final a in items) _row(theme, cs, a)];
  }

  Widget _row(ThemeData theme, ColorScheme cs, Achievement a) {
    final rarityColor = Color(a.rarity.colorValue);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: a.isUnlocked
              ? rarityColor.withAlpha(120)
              : cs.outlineVariant.withAlpha(80),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: a.isUnlocked
                    ? rarityColor.withAlpha(38)
                    : cs.surfaceContainerHighest,
                border: Border.all(
                  color: a.isUnlocked ? rarityColor.withAlpha(140) : cs.outlineVariant,
                ),
              ),
              child: Center(
                child: Opacity(
                  opacity: a.isUnlocked ? 1 : 0.35,
                  child: Text(a.icon, style: const TextStyle(fontSize: 21)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: a.isUnlocked
                                  ? cs.onSurface
                                  : cs.onSurface.withAlpha(150),
                            )),
                      ),
                      const SizedBox(width: 6),
                      _rarityChip(theme, rarityColor, a.rarity),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(a.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
                  if (!a.isUnlocked) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: a.progress,
                        minHeight: 5,
                        backgroundColor: cs.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(rarityColor.withAlpha(190)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(a.hint,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: rarityColor, fontWeight: FontWeight.w600)),
                  ] else if (a.unlockedAt != null)
                    Text('解锁于 ${date_utils.formatShortDate(a.unlockedAt!)}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.outlineVariant)),
                ],
              ),
            ),
            if (a.isUnlocked)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.verified, size: 18, color: rarityColor),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rarityChip(ThemeData theme, Color color, Rarity r) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(r.label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 9.5)),
    );
  }
}

/// 解锁横幅：顶部滑入，几秒后自动收起。
class AchievementUnlockBanner {
  AchievementUnlockBanner._();

  /// 用已捕获的 OverlayState 插入，避免跨异步间隙持有 BuildContext。
  static void showWith(OverlayState overlay, String name, String icon) {
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _Banner(
        name: name,
        icon: icon,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  static void show(BuildContext context, String name, String icon) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    showWith(overlay, name, icon);
  }
}

class _Banner extends StatefulWidget {
  const _Banner({required this.name, required this.icon, required this.onDone});

  final String name;
  final String icon;
  final VoidCallback onDone;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _anim =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    _c.forward();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _c.reverse().then((_) => widget.onDone());
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero)
            .animate(_anim),
        child: FadeTransition(
          opacity: _anim,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.inverseSurface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withAlpha(70),
                      blurRadius: 18,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: Row(
                children: [
                  Text(widget.icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('解锁成就',
                            style: TextStyle(
                                fontSize: 10.5,
                                letterSpacing: 1.6,
                                color: cs.onInverseSurface.withAlpha(170))),
                        Text(widget.name,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: cs.onInverseSurface)),
                      ],
                    ),
                  ),
                  Icon(Icons.emoji_events, size: 20, color: cs.onInverseSurface.withAlpha(180)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
