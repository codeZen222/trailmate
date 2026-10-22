import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/expense_model.dart';
import '../../models/trip_model.dart';
import '../../providers/database_provider.dart';
import '../../services/year_review_data.dart';
import '../../utils/date_utils.dart' as date_utils;
import '../../widgets/charts/bar_chart.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../core/router/app_router.dart';

/// 年度回顾：滑动卡片式年报。
class YearReviewPage extends ConsumerStatefulWidget {
  final int? year;

  const YearReviewPage({super.key, this.year});

  @override
  ConsumerState<YearReviewPage> createState() => _YearReviewPageState();
}

class _YearReviewPageState extends ConsumerState<YearReviewPage> {
  late int _selectedYear;
  List<int> _availableYears = const [];
  YearReviewData? _data;
  bool _loading = true;
  String? _error;

  final PageController _pager = PageController();
  int _page = 0;
  final List<GlobalKey> _cardKeys = [];

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.year ?? DateTime.now().year;
    _loadYears();
    // 打开年报即标记（成就「年度报告」的数据来源）
    ref.read(databaseProvider).markAchievementFlag('year_review');
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _loadYears() async {
    final db = ref.read(databaseProvider);
    final trips = await db.getAllTrips();
    final years = trips.map((t) => t.startDate.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final now = DateTime.now().year;
    if (!years.contains(now)) years.insert(0, now);
    if (mounted) setState(() => _availableYears = years);
    _loadReview();
  }

  Future<void> _loadReview() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final data = await YearReviewData.build(db, _selectedYear);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _error = '$e\n$st';
        _loading = false;
      });
    }
  }

  void _selectYear(int y) {
    setState(() => _selectedYear = y);
    // 换年份必须回到第一页：否则停在上一年的第 N 张卡，
    // 看起来像"没从头开始"；新数据的卡片位置也可能对不上。
    _page = 0;
    if (_pager.hasClients) _pager.jumpToPage(0);
    _loadReview();
  }

  int get _cardCount => 9;

  GlobalKey _keyFor(int i) {
    while (_cardKeys.length <= i) {
      _cardKeys.add(GlobalKey());
    }
    return _cardKeys[i];
  }

  Future<void> _shareCurrent() async {
    try {
      final ctx = _keyFor(_page).currentContext;
      if (ctx == null) throw Exception('页面还没准备好');
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('无法截取');
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('编码失败');
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/trailmate_${_selectedYear}_${_page}_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await Share.shareXFiles([XFile(f.path)],
          text: '我的 $_selectedYear 年旅行报告', subject: 'TrailMate 年度回顾');
      await ref.read(databaseProvider).markAchievementFlag('poster_shared');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分享失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('年度旅行报告'),
        actions: [
          if (_data != null && !_data!.isEmpty)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: '分享这一页',
              onPressed: _shareCurrent,
            ),
        ],
      ),
      body: Column(
        children: [
          // 年份切换
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final y in _availableYears)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$y'),
                      selected: y == _selectedYear,
                      onSelected: (_) => _selectYear(y),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorView(message: _error!, onRetry: _loadReview)
                    : _data == null || _data!.isEmpty
                        ? _EmptyYear(year: _selectedYear)
                        : _buildPager(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildPager(ThemeData theme) {
    final d = _data!;
    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _pager,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              _wrap(0, _CoverCard(d: d)),
              _wrap(1, _NumbersCard(d: d)),
              _wrap(2, _MonthsCard(d: d)),
              _wrap(3, _CitiesCard(d: d)),
              _wrap(4, _HighlightsCard(d: d)),
              _wrap(5, _MoodsCard(d: d)),
              _wrap(6, _MoneyCard(d: d)),
              _wrap(7, _PhotosCard(d: d)),
              _wrap(8, _ClosingCard(d: d)),
            ],
          ),
        ),
        // 页点 + 提示
        Padding(
          padding: const EdgeInsets.only(bottom: 18, top: 6),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _cardCount; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text('左右滑动查看 · ${_page + 1}/$_cardCount',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wrap(int i, Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: RepaintBoundary(
        key: _keyFor(i),
        child: _CardFrame(child: child),
      ),
    );
  }
}

// ==================== 卡片外壳 ====================

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withAlpha(80)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(28),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 卡片标题区。
class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.kicker, required this.title, this.sub});

  final String kicker;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kicker,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.primary, letterSpacing: 2.4, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(title,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (sub != null) ...[
          const SizedBox(height: 6),
          Text(sub!, style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
        ],
      ],
    );
  }
}

// ==================== 1. 封面 ====================

class _CoverCard extends StatelessWidget {
  const _CoverCard({required this.d});

  final YearReviewData d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (d.coverPhoto != null && File(d.coverPhoto!).existsSync())
          Image.file(File(d.coverPhoto!), fit: BoxFit.cover, width: double.infinity,
              errorBuilder: (_, __, ___) => _fallback(cs))
        else
          _fallback(cs),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withAlpha(60), Colors.black.withAlpha(190)],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Spacer(),
                Text('${d.year}',
                    style: TextStyle(
                        fontSize: 68,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: Colors.white,
                        height: 1.0,
                        shadows: [Shadow(blurRadius: 18, color: Colors.black.withAlpha(120))])),
                const SizedBox(height: 6),
                Text('年 旅 行 报 告',
                    style: TextStyle(fontSize: 14, letterSpacing: 6, color: Colors.white.withAlpha(220))),
                const SizedBox(height: 22),
                Text(_summary(),
                    style: TextStyle(
                        fontSize: 15, height: 1.6, color: Colors.white.withAlpha(235))),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (final p in d.photoWall.take(3))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(p), width: 44, height: 44, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                  width: 44, height: 44, color: Colors.white24)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback(ColorScheme cs) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, cs.tertiary],
          ),
        ),
        child: const SizedBox.expand(),
      );

  String _summary() {
    final parts = <String>[
      if (d.trips.isNotEmpty) '出发 ${d.trips.length} 次',
      if (d.totalDays > 0) '在路上 ${d.totalDays} 天',
      if (d.cities.isNotEmpty) '走过 ${d.cities.length} 座城',
    ];
    return parts.isEmpty ? '这一年，你还没出发过' : parts.join(' · ');
  }
}

// ==================== 2. 数字 ====================

class _NumbersCard extends StatelessWidget {
  const _NumbersCard({required this.d});

  final YearReviewData d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(kicker: 'NUMBERS', title: '这一年的数字', sub: '每一个数字都是一段真实走过的路'),
          const SizedBox(height: 22),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.25,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _cell(theme, '${d.trips.length}', '次出发'),
              _cell(theme, '${d.totalDays}', '天在路上'),
              _cell(theme, '${d.cities.length}', '座城市'),
              _cell(theme, '${d.logCount}', '篇日志'),
              _cell(theme, '${d.photoCount}', '张照片'),
              _cell(theme, d.expenseCents > 0 ? _money(d.expenseCents) : '—', '旅行花费'),
            ],
          ),
          const SizedBox(height: 20),
          if (d.photoCount > 0 && d.totalPhotosEver > 0)
            _note(theme,
                '今年拍了 ${d.photoCount} 张，占你全部照片的 ${(d.photoCount / d.totalPhotosEver * 100).toStringAsFixed(0)}%'),
          if (d.busiestMonth != null)
            _note(theme, '${d.busiestMonth!.month} 月是你最忙的月份，走了 ${d.busiestMonth!.days} 天'),
          if (d.expenseCents > 0 && d.totalDays > 0)
            _note(theme, '平均每天花 ${_money(d.dailySpendCents)}'),
        ],
      ),
    );
  }

  static String _money(int cents) => Money.format(cents);

  Widget _cell(ThemeData theme, String v, String l) {
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(v,
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800, color: cs.primary)),
          ),
          const SizedBox(height: 2),
          Text(l, style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
        ],
      ),
    );
  }

  Widget _note(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('· ', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
}

// ==================== 3. 月份 ====================

class _MonthsCard extends StatelessWidget {
  const _MonthsCard({required this.d});

  final YearReviewData d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final active = d.months.where((m) => m.days > 0).toList();

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
              kicker: 'TIMELINE',
              title: '四季的足迹',
              sub: active.isEmpty ? null : '有出行的月份：${active.length} 个'),
          const SizedBox(height: 22),
          BarChart(
            height: 170,
            items: [for (final m in d.months) BarItem(label: '${m.month}月', value: m.days.toDouble())],
            valueFormatter: (v) => v <= 0 ? '' : v.toStringAsFixed(0),
          ),
          const SizedBox(height: 24),
          if (active.isEmpty)
            Text('这一年没有记录到出行月份', style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline))
          else
            Expanded(
              child: ListView(
                children: [
                  for (final m in active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 46,
                            child: Text('${m.month}月',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          Expanded(
                            child: Text(
                              m.places.isEmpty ? '走了 ${m.days} 天' : m.places.join('、'),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text('${m.days} 天',
                              style: theme.textTheme.labelMedium?.copyWith(color: cs.primary)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== 4. 城市 ====================

class _CitiesCard extends StatelessWidget {
  const _CitiesCard({required this.d});

  final YearReviewData d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fresh = d.newCities.toSet();

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
              kicker: 'CITIES',
              title: '走过的城市',
              sub: d.cities.isEmpty
                  ? null
                  : '${d.cities.length} 座，其中 ${fresh.length} 座是第一次去'),
          const SizedBox(height: 20),
          if (d.cities.isEmpty)
            Text('还没有记录到城市。写日志时开启定位，就能自动记下你去过的地方。',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline))
          else
            Expanded(
              child: ListView.separated(
                itemCount: d.cities.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant.withAlpha(70)),
                itemBuilder: (context, i) {
                  final c = d.cities[i];
                  final isNew = fresh.contains(c);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text('${i + 1}'.padLeft(2, '0'),
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: cs.outline, fontWeight: FontWeight.w700)),
                    title: Text(c, style: theme.textTheme.bodyLarge),
                    trailing: isNew
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.primary.withAlpha(38),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('首访',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                          )
                        : null,
                    onTap: () => Navigator.pushNamed(context, AppRouter.footprintList),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== 5. 高光旅程 ====================

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard({required this.d});

  final YearReviewData d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(kicker: 'HIGHLIGHTS', title: '年度高光旅程', sub: '按你给出的评分排序'),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < d.highlights.length; i++) _trip(context, theme, cs, d.highlights[i], i),
                if (d.longest != null && d.longest!.durationDays > 1) ...[
                  const SizedBox(height: 10),
                  _pill(theme, cs, '最长的一次', '${d.longest!.destination} · ${d.longest!.durationDays} 天'),
                ],
                if (d.shortest != null)
                  _pill(theme, cs, '最短的逃离', '${d.shortest!.destination} · ${d.shortest!.durationDays} 天'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _trip(BuildContext context, ThemeData theme, ColorScheme cs, Trip t, int rank) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            Navigator.pushNamed(context, AppRouter.tripDetail, arguments: {'tripId': t.id}),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Text('${rank + 1}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900, color: cs.primary.withAlpha(120))),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (t.coverPath ?? '').isNotEmpty && File(t.coverPath!).existsSync()
                    ? Image.file(File(t.coverPath!), width: 56, height: 56, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _ph(cs))
                    : _ph(cs),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.destination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(date_utils.formatDateRange(t.startDate, t.endDate),
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
                    if (t.rating > 0)
                      Row(
                        children: [
                          for (var i = 0; i < 5; i++)
                            Icon(i < t.rating ? Icons.star : Icons.star_border,
                                size: 13, color: Colors.amber),
                        ],
                      ),
                  ],
                ),
              ),
              Text('${t.durationDays}天', style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ph(ColorScheme cs) => Container(
        width: 56, height: 56,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.image_outlined, size: 20, color: cs.outline),
      );

  Widget _pill(ThemeData theme, ColorScheme cs, String k, String v) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(k,
                style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.primary, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(v,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
}

// ==================== 6. 心情 ====================

class _MoodsCard extends StatelessWidget {
  const _MoodsCard({required this.d});

  final YearReviewData d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entries = d.moodCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (s, e) => s + e.value);

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
              kicker: 'MOODS',
              title: '你的心情天气',
              sub: total == 0
                  ? '还没给日志标过心情'
                  : '共 $total 篇日志标了心情${d.topMood == null ? '' : '，最常出现的是「${d.topMood!.label}」'}'),
          const SizedBox(height: 22),
          if (entries.isEmpty)
            Expanded(
              child: Center(
                child: Text('写日志时点底部的 😊 按钮，\n就能给那天标上心情',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline, height: 1.6)),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  for (final e in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(e.key.emoji, style: const TextStyle(fontSize: 17)),
                              const SizedBox(width: 8),
                              Text(e.key.label, style: theme.textTheme.bodyMedium),
                              const Spacer(),
                              Text('${e.value} 篇',
                                  style: theme.textTheme.labelMedium?.copyWith(color: cs.outline)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LayoutBuilder(
                            builder: (ctx, c) => Stack(
                              children: [
                                Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                  FractionallySizedBox(
                                    widthFactor: (e.value / total).clamp(0.03, 1.0),
                                    child: Container(
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: e.key.accent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== 7. 花费 ====================

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.d});

  final YearReviewData d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cats = d.expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
              kicker: 'SPENDING',
              title: '钱都去哪儿了',
              sub: d.expenseCents == 0
                  ? '这一年没记消费'
                  : '全年 ${Money.format(d.expenseCents)}'
                      '${d.totalDays > 0 ? ' · 日均 ${Money.format(d.dailySpendCents)}' : ''}'),
          const SizedBox(height: 20),
          if (cats.isEmpty)
            Expanded(
              child: Center(
                child: Text('记账后这里会出现分类占比。\n可以让右下角的精灵帮你记，说「午餐45」就行。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline, height: 1.6)),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  DonutChart(
                    size: 150,
                    thickness: 24,
                    centerTitle: '${cats.length} 个分类',
                    centerValue: Money.format(d.expenseCents),
                    slices: [
                      for (final e in cats)
                        DonutSlice(
                            label: e.key.label,
                            value: e.value.toDouble(),
                            color: e.key.color),
                    ],
                  ),
                  const SizedBox(height: 20),
                  RankBars(
                    items: [
                      for (final e in cats)
                        BarItem(label: '${e.key.emoji} ${e.key.label}', value: e.value / 100, color: e.key.color),
                    ],
                    valueFormatter: (v) => Money.format((v * 100).round()),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== 8. 照片墙 ====================

class _PhotosCard extends StatelessWidget {
  const _PhotosCard({required this.d});

  final YearReviewData d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final photos = d.photoWall;

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
              kicker: 'MEMORIES',
              title: '这一年的画面',
              sub: photos.isEmpty ? null : '拍了 ${d.photoCount} 张照片，这里是最先的 ${photos.length} 张'),
          const SizedBox(height: 18),
          if (photos.isEmpty)
            Expanded(
              child: Center(
                child: Text('这一年还没有照片',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline)),
              ),
            )
          else
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1,
                children: [
                  for (final p in photos)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(p), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.broken_image_outlined,
                                  size: 18, color: cs.outline)),
                          ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== 9. 结尾 ====================

class _ClosingCard extends StatelessWidget {
  const _ClosingCard({required this.d});

  final YearReviewData d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(kicker: 'RECAP', title: '这一年的关键词'),
          const SizedBox(height: 18),
          if (d.tagCounts.isEmpty)
            Text('旅程还没打过标签', style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in d.tagCounts)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: cs.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('#${e.key} ×${e.value}',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          if (d.unlockedAchievements.isNotEmpty) ...[
            Text('新解锁的成就', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final a in d.unlockedAchievements)
                  Tooltip(
                    message: a.description,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${a.icon} ${a.name}', style: theme.textTheme.labelMedium),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primaryContainer.withAlpha(120), cs.tertiaryContainer.withAlpha(120)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${d.year} 年，你出发了 ${d.trips.length} 次，\n在路上待了 ${d.totalDays} 天。\n${d.year + 1} 年，继续走。',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text('TrailMate · 年度旅行报告',
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 2, color: cs.outline)),
          ),
        ],
      ),
    );
  }
}

// ==================== 空/错误态 ====================

class _EmptyYear extends StatelessWidget {
  const _EmptyYear({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories_outlined, size: 52, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text('$year 年还没有旅行记录', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('建一段旅程、写几篇日志，\n明年这时候就能生成一份年度报告',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline, height: 1.6)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 30),
          const SizedBox(height: 10),
          Text('年度数据加载失败'),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(message,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            ),
          ),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
