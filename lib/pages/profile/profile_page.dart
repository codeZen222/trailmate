import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/database_provider.dart';
import '../../widgets/profile/profile_card.dart';
import 'profile_edit_page.dart';

/// 个人旅行档案页：未填写显示引导，已填写展示卡片并可编辑/分享。
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share(Profile p) async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('卡片尚未渲染完成');
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('截图失败');
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/trailmate_profile_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${p.nickname} 的旅行档案 · TrailMate',
        subject: '我的旅行档案',
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
    final profile = ref.watch(profileProvider);
    final statsAsync = ref.watch(profileStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的旅行档案'),
        actions: [
          if (profile != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: () =>
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProfileEditPage())),
            ),
        ],
      ),
      body: profile == null
          ? _EmptyProfile(
              onCreate: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfileEditPage())),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(profileStatsProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: [
                  Center(
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: statsAsync.when(
                        data: (s) => ProfileCard(profile: profile, stats: s),
                        loading: () => const SizedBox(
                          height: 320,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (_, __) => ProfileCard(profile: profile, stats: ProfileStats.empty),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _sharing ? null : () => _share(profile),
                    icon: _sharing
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.share_outlined),
                    label: Text(_sharing ? '正在生成…' : '分享我的档案卡'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50)),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ProfileEditPage())),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑档案'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => _confirmClear(context),
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    label: Text('清空档案', style: TextStyle(color: cs.error)),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空档案？'),
        content: const Text('只会清除档案资料，旅程与日志不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(profileProvider.notifier).clear();
    }
  }
}

class _EmptyProfile extends StatelessWidget {
  const _EmptyProfile({required this.onCreate});

  final VoidCallback onCreate;

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
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primaryContainer.withAlpha(90),
              ),
              child: Icon(Icons.badge_outlined, size: 52, color: cs.primary),
            ),
            const SizedBox(height: 22),
            Text('还没有旅行档案',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              '填几项资料，就能生成一张属于你的\n旅行人格卡片，还能分享出去',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline, height: 1.5),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('创建我的档案'),
            ),
          ],
        ),
      ),
    );
  }
}
