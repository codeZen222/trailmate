import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/achievement_provider.dart';
import '../providers/database_provider.dart';
import '../providers/sprite_provider.dart';
import '../pages/stats/achievement_page.dart';

/// 重算成就；若有新解锁则弹横幅并让精灵一起庆祝。
/// 统计页与成就页共用这一份逻辑，保证仪式感一致。
Future<int> runAchievementCheck(WidgetRef ref, BuildContext context) async {
  // 在任何 await 之前捕获 messenger，避免跨异步间隙使用 BuildContext
  final messenger = ScaffoldMessenger.maybeOf(context);
  final overlay = Overlay.maybeOf(context);

  final newly = await ref.read(databaseProvider).checkAchievements();
  if (newly.isEmpty) return 0;

  ref.invalidate(achievementsWithProgressProvider);

  // 精灵高兴一下
  ref.read(spriteCelebrationProvider.notifier).state++;

  for (var i = 0; i < newly.length; i++) {
    if (i > 0) await Future.delayed(const Duration(milliseconds: 900));
    if (overlay == null || !overlay.mounted) break;
    AchievementUnlockBanner.showWith(overlay, newly[i].name, newly[i].icon);
  }
  messenger?.showSnackBar(
    SnackBar(
      content: Text(newly.length == 1
          ? '解锁了 1 个新成就 🏅'
          : '解锁了 ${newly.length} 个新成就 🏅'),
      duration: const Duration(seconds: 2),
    ),
  );
  return newly.length;
}
