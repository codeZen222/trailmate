import '../services/achievement_rules.dart';

class Achievement {
  final int id;
  final String name;
  final String description;
  final String icon;

  /// 可求值规则串（如 `cities>=10`）。旧数据里可能是中文描述。
  final String condition;
  final Rarity rarity;
  final DateTime? unlockedAt;

  /// 展示用的达成说明（由规则翻译成中文，不再直接暴露规则串）。
  final String hint;

  /// 当前进度 0..1；已解锁为 1。
  final double progress;

  Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.condition,
    this.rarity = Rarity.common,
    this.unlockedAt,
    this.hint = '',
    this.progress = 0,
  });

  bool get isUnlocked => unlockedAt != null;

  Achievement copyWith({
    int? id,
    String? name,
    String? description,
    String? icon,
    String? condition,
    Rarity? rarity,
    DateTime? unlockedAt,
    String? hint,
    double? progress,
  }) {
    return Achievement(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      condition: condition ?? this.condition,
      rarity: rarity ?? this.rarity,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      hint: hint ?? this.hint,
      progress: progress ?? this.progress,
    );
  }
}
