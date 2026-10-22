import 'package:flutter/material.dart';
import '../../models/mood_type.dart';
import 'mood_effect_layer.dart';

/// 选择结果：区分「取消（不改动）」与「确认清除心情」。
class MoodPickResult {
  const MoodPickResult.cancel()
      : confirmed = false,
        mood = null;
  const MoodPickResult.set(this.mood) : confirmed = true;

  final bool confirmed;
  final MoodType? mood;

  /// confirmed 且 mood == null 表示用户主动清除心情。
  bool get isClear => confirmed && mood == null;
}

/// 心情选择器：12 宫格 + 顶部实时预览。
class MoodPickerSheet extends StatefulWidget {
  const MoodPickerSheet({super.key, this.initial});

  final MoodType? initial;

  static Future<MoodPickResult?> pick(BuildContext context, {MoodType? initial}) {
    return showModalBottomSheet<MoodPickResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => MoodPickerSheet(initial: initial),
    );
  }

  @override
  State<MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends State<MoodPickerSheet> {
  late MoodType? _preview = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32, height: 4,
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Text('选择今天的心情', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('特效会伴随这篇日志一直存在',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
            const SizedBox(height: 12),

            // 预览区
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 132,
                width: double.infinity,
                color: cs.surfaceContainerHighest,
                child: Stack(
                  children: [
                    if (_preview != null)
                      MoodEffectLayer(mood: _preview, seed: _preview!.key.length * 7 + 3),
                    Center(
                      child: _preview == null
                          ? Text('点下方任一心境预览特效',
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline))
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: cs.surface.withAlpha(200),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_preview!.emoji} ${_preview!.label} · ${_preview!.effectHint}',
                                style: theme.textTheme.labelMedium,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            Flexible(
              child: SingleChildScrollView(
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.18,
                  children: MoodType.all.map((m) {
                    final selected = _preview == m;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _preview = m),
                      onLongPress: () => setState(() => _preview = null),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: selected
                              ? m.accent.withAlpha(46)
                              : cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? m.accent : cs.outlineVariant.withAlpha(90),
                            width: selected ? 1.6 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(m.emoji, style: const TextStyle(fontSize: 24)),
                            const SizedBox(height: 4),
                            Text(m.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                )),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, const MoodPickResult.cancel()),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, MoodPickResult.set(_preview)),
                    child: Text(_preview == null ? '不设置' : '就用这个'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
