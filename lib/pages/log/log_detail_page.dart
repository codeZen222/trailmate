import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../providers/log_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/log_model.dart';
import '../../core/router/app_router.dart';
import '../../widgets/mood/mood_effect_layer.dart';
import 'widgets/image_grid.dart';

class LogDetailPage extends ConsumerStatefulWidget {
  final int logId;
  final int tripId;

  const LogDetailPage({
    super.key,
    required this.logId,
    required this.tripId,
  });

  @override
  ConsumerState<LogDetailPage> createState() => _LogDetailPageState();
}

class _LogDetailPageState extends ConsumerState<LogDetailPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志详情'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                Navigator.pushNamed(
                  context,
                  AppRouter.logEditor,
                  arguments: {
                    'tripId': widget.tripId,
                    'logId': widget.logId,
                  },
                );
              } else if (value == 'share') {
                Navigator.pushNamed(context, AppRouter.logShare,
                    arguments: {'logId': widget.logId});
              } else if (value == 'delete') {
                _confirmDelete();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('编辑'),
                dense: true,
              )),
              const PopupMenuItem(value: 'share', child: ListTile(
                leading: Icon(Icons.share_outlined),
                title: Text('分享这篇'),
                dense: true,
              )),
              const PopupMenuItem(value: 'delete', child: ListTile(
                leading: Icon(Icons.delete_outlined, color: Colors.red),
                title: Text('删除', style: TextStyle(color: Colors.red)),
                dense: true,
              )),
            ],
          ),
        ],
      ),
      body: Consumer(
        builder: (context, ref, _) {
          final logAsync = ref.watch(logByIdProvider(widget.logId));
          return logAsync.when(
            data: (log) {
              if (log == null) {
                return const Center(child: Text('日志不存在'));
              }
              return Stack(
                children: [
                  // 心情特效层：固定在背景，正文在其上滚动，保证可读性
                  if (log.mood != null && ref.watch(effectsActiveProvider))
                    MoodEffectLayer(mood: log.mood, seed: log.id * 31 + 7),
                  Positioned.fill(child: _buildContent(context, colorScheme, log)),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败: $e')),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme, Log log) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日期、天气、评分
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${log.date.year}年${log.date.month}月${log.date.day}日',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(width: 8),
              if (log.weather != null)
                Text(log.weather!, style: const TextStyle(fontSize: 18)),
              if (log.mood != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: log.mood!.accent.withAlpha(38),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: log.mood!.accent.withAlpha(110)),
                  ),
                  child: Text(
                    '${log.mood!.emoji} ${log.mood!.label}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color.alphaBlend(
                        log.mood!.accent.withAlpha(40),
                        colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (log.rating != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < log.rating! ? Icons.star : Icons.star_border,
                      size: 18,
                      color: Colors.amber,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 标题
          if (log.title != null && log.title!.isNotEmpty) ...[
            Text(
              log.title!,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 图片
          _ImageSection(logId: widget.logId),
          const SizedBox(height: 16),

          // GPS 位置（若日志记录了定位）
          _LocationSection(logId: widget.logId),

          // Markdown 正文
          MarkdownBody(
            data: log.content,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.8),
              h1: Theme.of(context).textTheme.headlineSmall,
              h2: Theme.of(context).textTheme.titleLarge,
              h3: Theme.of(context).textTheme.titleMedium,
              listBullet: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除日志'),
        content: const Text('确定要删除这篇日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              // 等删除完成再关：失败时如实提示，不留下"说删了其实没删"的状态。
              try {
                await deleteLog(ref, widget.logId);
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
                const SnackBar(content: Text('日志已删除')),
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

class _ImageSection extends ConsumerWidget {
  final int logId;

  const _ImageSection({required this.logId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(databaseProvider).getImagesByLog(logId),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
        return ImageGrid(images: snap.data!);
      },
    );
  }
}

/// 展示日志记录的 GPS 位置：城市/地点名 + 坐标，点击可跳足迹地图。
class _LocationSection extends ConsumerWidget {
  final int logId;

  const _LocationSection({required this.logId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder(
      future: ref.read(databaseProvider).getLocationByLog(logId),
      builder: (context, snap) {
        final loc = snap.data;
        if (loc == null) return const SizedBox.shrink();
        final title = [loc.cityName, loc.placeName]
            .where((e) => e != null && e.isNotEmpty)
            .join(' · ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () => Navigator.pushNamed(context, AppRouter.footprintMap),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Icon(Icons.place_outlined, color: colorScheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty ? '已记录位置' : title,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colorScheme.outline),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}