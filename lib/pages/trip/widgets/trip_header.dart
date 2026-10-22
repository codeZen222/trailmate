import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/trip_model.dart';
import '../../../utils/date_utils.dart' as date_utils;

class TripHeader extends StatelessWidget {
  final Trip trip;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onCoverTap;
  final VoidCallback onToggleCompleted;

  const TripHeader({
    super.key,
    required this.trip,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
    required this.onShare,
    required this.onRatingChanged,
    required this.onCoverTap,
    required this.onToggleCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBack,
      ),
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
                break;
              case 'share':
                onShare();
                break;
              case 'delete':
                onDelete();
                break;
              case 'toggleDone':
                onToggleCompleted();
                break;
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
              title: Text('分享'),
              dense: true,
            )),
            // 归期是显式标志位，只能由用户自己确认；
            // 「一日行程」和「没填归期」在数据上长得一样，程序不该猜。
            const PopupMenuItem(value: 'toggleDone', child: ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('标记为已完成 / 进行中'),
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
      flexibleSpace: FlexibleSpaceBar(
        background: GestureDetector(
          onTap: onCoverTap,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.primaryContainer,
                  colorScheme.tertiaryContainer,
                  colorScheme.surface,
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.destination,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: colorScheme.onSurface),
                          const SizedBox(width: 4),
                          Text(
                            date_utils.formatDateRange(trip.startDate, trip.endDate),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.access_time, size: 14, color: colorScheme.onSurface),
                          const SizedBox(width: 4),
                          Text(
                            date_utils.formatDuration(trip.durationDays),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 评分：未评分时 5 个空心星会被误读成"打了 0 分"，
                      // 所以加一行文字说明这是可点的输入，并在已评分时显示分值。
                      Row(
                        children: [
                          ...List.generate(5, (i) {
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                // 点当前分数的同一颗星 = 清除评分
                                final newVal = trip.rating == i + 1 ? 0 : i + 1;
                                onRatingChanged(newVal);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 3, vertical: 6),
                                child: Icon(
                                  i < trip.rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: trip.rating == 0
                                      ? Colors.amber.withAlpha(120)
                                      : Colors.amber,
                                  size: 28,
                                ),
                              ),
                            );
                          }),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              trip.rating == 0
                                  ? '点击星星给这趟旅行评分'
                                  : '${trip.rating} 分 · 再点同一颗可清除',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: trip.rating == 0
                                    ? colorScheme.outline
                                    : colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}