import 'package:flutter/material.dart';

/// 心情标签（主观情绪），与 `weather`（客观天气）彼此独立。
///
/// 每种心情对应一种粒子特效，由 [MoodType.effect] 描述语义、
/// 具体绘制见 `widgets/mood/mood_painter.dart`。
enum MoodType {
  rain('rain', '心在下雨', '🌧️', Color(0xFF5B7FA6), '斜落雨丝 · 低落怀念'),
  sunshine('sunshine', '阳光满格', '☀️', Color(0xFFF2B441), '暖光呼吸 · 开心明朗'),
  snow('snow', '初雪', '❄️', Color(0xFF9CC7E8), '缓落雪花 · 纯净安静'),
  petal('petal', '落樱', '🌸', Color(0xFFE8A0B4), '旋转花瓣 · 浪漫心动'),
  star('star', '星愿', '✨', Color(0xFFB9A0E8), '明灭星点 · 感动期许'),
  leaf('leaf', '秋风', '🍂', Color(0xFFC98A4B), '落叶翻转 · 萧瑟思念'),
  night('night', '静夜', '🌙', Color(0xFF3A4A7A), '深蓝夜色 · 平静孤独'),
  wind('wind', '疾风', '💨', Color(0xFF8FB8C9), '横向流线 · 自由匆忙'),
  rainbow('rainbow', '彩虹', '🌈', Color(0xFFE88FB4), '光弧掠过 · 小确幸'),
  waves('waves', '海浪', '🌊', Color(0xFF3E8FB0), '底部波纹 · 放松治愈'),
  fireworks('fireworks', '烟花', '🎆', Color(0xFFE86A8A), '偶发绽放 · 高光时刻'),
  mist('mist', '迷雾', '🌫️', Color(0xFFA8B4C4), '漂移雾团 · 迷茫朦胧');

  const MoodType(this.key, this.label, this.emoji, this.accent, this.effectHint);

  /// 存入数据库 logs.moodTag 的稳定标识（改名不影响历史数据）。
  final String key;
  final String label;
  final String emoji;
  /// 主题色：用于徽章描边、粒子主色、时间线点缀。
  final Color accent;
  /// 选择器里的效果说明文案。
  final String effectHint;

  static const List<MoodType> all = values;

  /// 从数据库值解析；未知/空返回 null（旧数据没有该字段）。
  static MoodType? fromKey(String? k) {
    if (k == null || k.isEmpty) return null;
    for (final m in values) {
      if (m.key == k) return m;
    }
    return null;
  }
}
