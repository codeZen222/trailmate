import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/database_provider.dart';
import '../../models/trip_model.dart';
import '../../models/mood_type.dart';
import '../../widgets/share/trip_poster_card.dart';

/// 上次所选模板的持久化键。
const String _templateSettingKey = 'share_poster_template';

/// 旅程分享页：把旅程聚合成一张竖版旅行海报卡，可改文案与特效后分享。
class ShareCardPage extends ConsumerStatefulWidget {
  final int tripId;

  const ShareCardPage({super.key, required this.tripId});

  @override
  ConsumerState<ShareCardPage> createState() => _ShareCardPageState();
}

class _ShareCardPageState extends ConsumerState<ShareCardPage> {
  final GlobalKey _boundaryKey = GlobalKey();
  final TextEditingController _caption = TextEditingController();

  bool _sharing = false;
  bool _loading = true;
  PosterTemplate _template = PosterTemplate.wave;

  Trip? _trip;
  List<String> _photoPaths = const [];
  List<String> _cities = const [];
  List<String> _tags = const [];
  int _logCount = 0;
  int _totalCents = 0;
  List<MoodType> _tripMoods = const [];
  MoodType? _effectMood;

  @override
  void initState() {
    super.initState();
    _load();
    _restoreTemplate();
  }

  /// 恢复上次使用的模板。
  Future<void> _restoreTemplate() async {
    final saved = await ref.read(databaseProvider).getSetting(_templateSettingKey);
    if (!mounted || saved == null) return;
    setState(() => _template = PosterTemplate.fromKey(saved));
  }

  void _chooseTemplate(PosterTemplate t) {
    setState(() => _template = t);
    ref.read(databaseProvider).setSetting(_templateSettingKey, t.key);
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// 聚合旅程数据：照片、城市、标签、日志数、心情。
  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final trip = await db.getTripById(widget.tripId);
    final logs = await db.getLogsByTrip(widget.tripId);
    final images = await db.getImagesByTrip(widget.tripId);
    final tags = await db.getTagsByTrip(widget.tripId);
    final cities = await db.getCitiesByTrip(widget.tripId);
    _totalCents = await db.getTripTotalCents(widget.tripId);

    if (!mounted) return;

    // 主图优先用旅程封面，其余按时间顺序补上。
    // 【必须限量】海报会把每张照片都解码进 RepaintBoundary，
    // 而截图用 pixelRatio 3.0 —— 几十张原图一起解码会把主线程堵死（"点分享就卡住"）。
    // 版面上最多也只有 5 个图位，取 6 张已足够轮换。
    const maxPosterPhotos = 6;
    final paths = <String>[
      if ((trip?.coverPath ?? '').isNotEmpty) trip!.coverPath!,
      ...images.map((i) => i.filePath).where((p) => p != trip?.coverPath),
    ];
    final unique = paths.toList();
    final capped = unique.length > maxPosterPhotos
        ? unique.sublist(0, maxPosterPhotos)
        : unique;

    final sorted = [...logs]..sort((a, b) => b.date.compareTo(a.date));
    final moods = <MoodType>{};
    MoodType? latest;
    for (final l in sorted) {
      final m = MoodType.fromKey(l.moodTag);
      if (m == null) continue;
      moods.add(m);
      latest ??= m;
    }

    setState(() {
      // db.getTripById 返回的是 drift 行对象，需映射为模型 Trip
      _trip = trip == null
          ? null
          : Trip(
              id: trip.id,
              destination: trip.destination,
              coverPath: trip.coverPath,
              startDate: trip.startDate,
              endDate: trip.endDate,
              rating: trip.rating,
              notes: trip.notes,
              isCompleted: trip.isCompleted,
              createdAt: trip.createdAt,
              updatedAt: trip.updatedAt,
            );
      _photoPaths = capped;
      _cities = cities;
      _tags = tags.map((t) => t.name).toList();
      _logCount = logs.length;
      _tripMoods = moods.toList();
      _effectMood = latest;
      _loading = false;
    });
  }

  TripPosterData _buildData() {
    final t = _trip!;
    return TripPosterData(
      destination: t.destination,
      startDate: t.startDate,
      endDate: t.endDate,
      days: t.durationDays,
      photoPaths: _photoPaths,
      cities: _cities,
      tagNames: _tags,
      logCount: _logCount,
      photoCount: _photoPaths.length,
      caption: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
      notes: t.notes,
      rating: t.rating,
      mood: _effectMood,
      totalCents: _totalCents,
    );
  }

  Future<File?> _captureCard() async {
    final boundary =
        _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // 2.5 倍已足够清晰（输出约 950x3600）；原来的 3.0 会让 PNG 编码与
    // 内存占用明显上升，配合多张原图解码就是"点分享卡住"的主因。
    final image = await boundary.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/trailmate_share_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return file;
  }

  Future<void> _doShare() async {
    setState(() => _sharing = true);
    try {
      final file = await _captureCard();
      if (file == null) throw Exception('卡片尚未渲染完成');
      final t = _trip!;
      final caption = _caption.text.trim();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: caption.isNotEmpty
            ? caption
            : '${t.destination} · 旅行记录',
        subject: t.destination,
      );
      await ref.read(databaseProvider).markAchievementFlag('poster_shared');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分享失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('分享海报'),
        actions: [
          IconButton(
            icon: _sharing
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share),
            onPressed: _loading || _sharing ? null : _doShare,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trip == null
              ? const Center(child: Text('旅程不存在'))
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Center(
                          child: RepaintBoundary(
                            key: _boundaryKey,
                            child: TripPosterCard(
                                data: _buildData(), template: _template),
                          ),
                        ),
                      ),
                    ),
                    _templateBar(theme, cs),
                    _captionBar(theme, cs),
                    _moodBar(theme, cs),
                  ],
                ),
    );
  }

  /// 模板选择条：横向滑动的 5 种版式。
  Widget _templateBar(ThemeData theme, ColorScheme cs) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final t in PosterTemplate.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: _template == t,
                showCheckmark: false,
                label: Text('${t.emoji} ${t.label}'),
                selectedColor: cs.primary.withAlpha(45),
                side: BorderSide(
                  color: _template == t ? cs.primary : cs.outlineVariant,
                  width: _template == t ? 1.6 : 1,
                ),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: _template == t ? FontWeight.w700 : FontWeight.w500,
                ),
                onSelected: (_) => _chooseTemplate(t),
              ),
            ),
        ],
      ),
    );
  }

  /// 可编辑文案：写什么就印在海报顶部。
  Widget _captionBar(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: TextField(
        controller: _caption,
        maxLength: 24,
        maxLines: 1,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          hintText: '写一句文案印在海报上（留空用默认）',
          prefixIcon: const Icon(Icons.edit_outlined, size: 18),
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  /// 特效选择条：无 / 该旅程出现过的心情 / 其余心情。
  Widget _moodBar(ThemeData theme, ColorScheme cs) {
    final quick = _tripMoods;
    final rest = MoodType.all.where((m) => !quick.contains(m));

    Widget chip(MoodType? m) {
      final selected = _effectMood == m;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          showCheckmark: false,
          avatar: m == null
              ? const Icon(Icons.block, size: 16)
              : Text(m.emoji, style: const TextStyle(fontSize: 15)),
          label: Text(m?.label ?? '无特效'),
          selectedColor: (m?.accent ?? cs.outlineVariant).withAlpha(60),
          side: BorderSide(
            color: selected ? (m?.accent ?? cs.onSurface) : cs.outlineVariant.withAlpha(90),
            width: selected ? 1.5 : 1,
          ),
          onSelected: (_) => setState(() => _effectMood = m),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant.withAlpha(80))),
        ),
        child: SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              chip(null),
              ...quick.map(chip),
              if (quick.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(width: 1, color: cs.outlineVariant),
                ),
              ...rest.map(chip),
            ],
          ),
        ),
      ),
    );
  }
}
