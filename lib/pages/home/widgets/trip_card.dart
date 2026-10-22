import 'dart:io';

import 'package:flutter/material.dart';
import '../../../models/trip_model.dart';
import '../../../utils/date_utils.dart' as date_utils;

/// 时间轴风格的一行旅程条目：左侧圆点+连线由外层提供，这里只画内容卡。
class TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const TripCard({
    super.key,
    required this.trip,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 缩略图
              _Thumb(trip: trip, radius: 14),
              const SizedBox(width: 14),
              // 文字信息
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trip.destination,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (trip.rating > 0) ...[
                          Icon(Icons.star_rounded, size: 18, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text('${trip.rating}',
                              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // 未定归期时不要显示"2024-07-21 - 2024-07-21"这种假区间
                      trip.endDateUnset
                          ? '${date_utils.formatDate(trip.startDate)} 出发 · 归期未定'
                          : date_utils.formatDateRange(trip.startDate, trip.endDate),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: trip.endDateUnset
                                ? cs.tertiaryContainer.withAlpha(140)
                                : cs.primaryContainer.withAlpha(120),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            trip.endDateUnset
                                ? '进行中'
                                : date_utils.formatDuration(trip.durationDays),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: trip.endDateUnset
                                  ? cs.onTertiaryContainer
                                  : cs.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (trip.notes != null && trip.notes!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              trip.notes!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final Trip trip;
  final double radius;
  const _Thumb({required this.trip, required this.radius});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primaryContainer, cs.tertiaryContainer],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: trip.coverPath == null
          ? Center(
              child: Icon(Icons.luggage_outlined, color: cs.onPrimaryContainer.withAlpha(150)),
            )
          : Image.file(
              File(trip.coverPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.image_not_supported_outlined, color: cs.onPrimaryContainer.withAlpha(150)),
              ),
            ),
    );
  }
}
