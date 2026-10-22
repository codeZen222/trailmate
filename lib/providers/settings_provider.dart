import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_background.dart';
import '../database/app_database.dart' as db;
import 'database_provider.dart';

const String _effectsSettingKey = 'mood_effects_enabled';

/// 心情特效总开关：持久化到 settings 表，并自动尊重系统「减弱动态效果」。
class EffectsNotifier extends StateNotifier<bool> {
  EffectsNotifier(this._db) : super(true) {
    _restore();
  }

  final db.AppDatabase _db;

  Future<void> _restore() async {
    final saved = await _db.getSetting(_effectsSettingKey);
    // 缺省视为开启
    if (saved != null) state = saved != '0';
  }

  void setEnabled(bool v) {
    state = v;
    _db.setSetting(_effectsSettingKey, v ? '1' : '0');
  }
}

final effectsProvider =
    StateNotifierProvider<EffectsNotifier, bool>((ref) => EffectsNotifier(ref.watch(databaseProvider)));

/// 实际是否应播放特效：用户开关 && 系统未要求减弱动效。
/// 在 widget 里用 `ref.watch(effectsActiveProvider)` 即可。
final effectsActiveProvider = Provider<bool>((ref) {
  final userOn = ref.watch(effectsProvider);
  if (!userOn) return false;
  return !SchedulerBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
});

const String _backgroundSettingKey = 'background_style';

/// 背景风格：插画 / 渐变 / 纯色。持久化到 settings 表。
class BackgroundNotifier extends StateNotifier<BackgroundStyle> {
  BackgroundNotifier(this._db) : super(BackgroundStyle.scene) {
    _restore();
  }

  final db.AppDatabase _db;

  Future<void> _restore() async {
    final saved = await _db.getSetting(_backgroundSettingKey);
    if (saved != null && saved.isNotEmpty) {
      state = BackgroundStyle.fromKey(saved);
    }
  }

  void set(BackgroundStyle s) {
    state = s;
    _db.setSetting(_backgroundSettingKey, s.name);
  }
}

final backgroundProvider = StateNotifierProvider<BackgroundNotifier, BackgroundStyle>(
    (ref) => BackgroundNotifier(ref.watch(databaseProvider)));
