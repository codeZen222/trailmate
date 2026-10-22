import 'package:flutter/material.dart';
import '../../../models/log_model.dart';
import '../../../utils/date_utils.dart' as date_utils;

class TimelineTile extends StatelessWidget {
  final String dateKey;
  final List<Log> logs;
  final void Function(Log log) onLogTap;

  const TimelineTile({
    super.key,
    required this.dateKey,
    required this.logs,
    required this.onLogTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final date = DateTime.tryParse(dateKey) ?? DateTime.now();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日期头部
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${date_utils.formatShortDate(date)} ${date_utils.dayOfWeek(date)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (logs.first.weather != null)
                  Text(logs.first.weather!, style: const TextStyle(fontSize: 16)),
                if (logs.first.mood != null) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: logs.first.mood!.label,
                    child: Text(logs.first.mood!.emoji, style: const TextStyle(fontSize: 16)),
                  ),
                ],
                const Spacer(),
                if (logs.first.rating != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < logs.first.rating! ? Icons.star : Icons.star_border,
                        size: 14,
                        color: Colors.amber,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 当天日志
          ...logs.map((log) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LogCard(log: log, onTap: () => onLogTap(log)),
          )),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final Log log;
  final VoidCallback onTap;

  const _LogCard({required this.log, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (log.mood != null) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: log.mood!.accent.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: log.mood!.accent.withAlpha(90)),
                      ),
                      child: Text(
                        '${log.mood!.emoji} ${log.mood!.label}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              if (log.title != null && log.title!.isNotEmpty) ...[
                Text(
                  log.title!,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                log.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.schedule, size: 12, color: colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    '${log.createdAt.hour.toString().padLeft(2, '0')}:${log.createdAt.minute.toString().padLeft(2, '0')}',
                    style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 18, color: colorScheme.outline),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}