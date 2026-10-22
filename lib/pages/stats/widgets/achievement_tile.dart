import 'package:flutter/material.dart';
import '../../../models/achievement_model.dart';

class AchievementTile extends StatelessWidget {
  final Achievement achievement;

  const AchievementTile({super.key, required this.achievement});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(achievement.icon, style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 4),
              Text(
                achievement.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(achievement.icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Text(achievement.name),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(achievement.description),
            const SizedBox(height: 8),
            if (achievement.unlockedAt != null)
              Text(
                '解锁时间：${achievement.unlockedAt!.year}年${achievement.unlockedAt!.month}月${achievement.unlockedAt!.day}日',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            const SizedBox(height: 4),
            Text('条件：${achievement.condition}', style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}