import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/mood_type.dart';
import '../../providers/database_provider.dart';
import '../../utils/geo_naming.dart';
import '../../widgets/share/log_share_card.dart';

/// 单篇日志的分享页。
///
/// 【与旅程海报的区别】这里只讲"这一天"：正文优先、配当日天气与心情，
/// 主图用该日志自己的第一张照片，而不是整趟行程的封面。
class LogSharePage extends ConsumerStatefulWidget {
  const LogSharePage({super.key, required this.logId});

  final int logId;

  @override
  ConsumerState<LogSharePage> createState() => _LogSharePageState();
}

class _LogSharePageState extends ConsumerState<LogSharePage> {
  final GlobalKey _boundaryKey = GlobalKey();

  bool _loading = true;
  bool _sharing = false;
  String? _error;

  LogCardData? _data;
  List<MoodType> _moodChoices = const [];
  MoodType? _effectMood;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final database = ref.read(databaseProvider);
      // getLogById / getTripById 返回的是 drift 行对象（非模型层同名类），
      // 字段直接取用即可，不要试图赋给 models 里的 Log/Trip。
      final log = await database.getLogById(widget.logId);
      if (log == null) {
        setState(() {
          _loading = false;
          _error = '找不到这篇日志';
        });
        return;
      }
      final trip = await database.getTripById(log.tripId);
      final images = await database.getImagesByLogOrdered(log.id);
      final loc = await database.getLocationByLog(log.id);

      final photos = images.map((i) => i.filePath).toList();
      final mood = MoodType.fromKey(log.moodTag);

      setState(() {
        _data = LogCardData(
          title: log.title ?? '',
          content: log.content,
          date: log.date,
          destination:
              cityOf(trip?.destination ?? '') ?? trip?.destination ?? '',
          weather: log.weather,
          mood: mood,
          photos: photos,
          placeName: loc?.placeName ?? loc?.cityName,
          tripName: trip?.destination ?? '',
        );
        // 允许换成该日志已有的心情，或关掉特效
        _moodChoices = [
          if (mood != null) mood,
          ...MoodType.all.where((m) => m != mood).take(5),
        ];
        _effectMood = mood;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _doShare() async {
    if (_data == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('卡片尚未渲染完成');

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw Exception('截图失败');

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/trailmate_log_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      final d = _data!;
      final caption = d.title.trim().isNotEmpty
          ? d.title.trim()
          : '${d.destination} · ${d.date.month}月${d.date.day}日';
      await Share.shareXFiles([XFile(file.path)],
          text: caption, subject: d.destination);
      await ref.read(databaseProvider).markAchievementFlag('poster_shared');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分享失败：$e')));
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
        title: const Text('分享这篇日志'),
        actions: [
          IconButton(
            onPressed: _sharing || _data == null ? null : _doShare,
            icon: _sharing
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            tooltip: '分享',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: cs.outlineVariant),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Column(
                    children: [
                      RepaintBoundary(
                        key: _boundaryKey,
                        child: LogShareCard(
                          data: _data!.copyWithMood(_effectMood),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('特效',
                            style: theme.textTheme.titleSmall),
                      ),
                      const SizedBox(height: 8),
                      _moodBar(theme, cs),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _sharing ? null : _doShare,
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('分享图片'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _moodBar(ThemeData theme, ColorScheme cs) {
    Widget chip(MoodType? m) {
      final selected = _effectMood == m;
      return ChoiceChip(
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
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [chip(null), ..._moodChoices.map(chip)],
    );
  }
}

/// 便于在页面上临时替换特效而不动原始数据。
extension on LogCardData {
  LogCardData copyWithMood(MoodType? m) => LogCardData(
        title: title,
        content: content,
        date: date,
        destination: destination,
        weather: weather,
        mood: m,
        photos: photos,
        placeName: placeName,
        tripName: tripName,
      );
}
