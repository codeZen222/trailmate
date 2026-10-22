import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_provider.dart';
import 'app_theme.dart';

/// 主题模式（浅色/深色/跟随系统），变更时持久化到 settings 表。
class ThemeNotifier extends StateNotifier<ThemeMode> {
  final Ref _ref;

  ThemeNotifier(this._ref) : super(ThemeMode.system) {
    _restore();
  }

  Future<void> _restore() async {
    final db = _ref.read(databaseProvider);
    final saved = await db.getSetting('theme_mode');
    if (saved != null) {
      state = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      );
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _persist(mode);
  }

  /// 循环：跟随系统 → 浅色 → 深色 → 跟随系统
  void cycle() {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    setThemeMode(next);
  }

  void _persist(ThemeMode mode) {
    _ref.read(databaseProvider).setSetting('theme_mode', mode.name);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) => ThemeNotifier(ref));

/// 配色方案控制器：内存态 + 持久化到 settings 表。
class ColorSchemeNotifier extends StateNotifier<AppTheme> {
  final Ref _ref;

  ColorSchemeNotifier(this._ref) : super(AppTheme.ocean) {
    _restore();
  }

  Future<void> _restore() async {
    final db = _ref.read(databaseProvider);
    final saved = await db.getSetting('color_scheme');
    if (saved != null) {
      final match = AppTheme.values.where((t) => t.name == saved).firstOrNull;
      if (match != null) state = match;
    }
  }

  void select(AppTheme theme) {
    state = theme;
    _ref.read(databaseProvider).setSetting('color_scheme', theme.name);
  }
}

final appThemeProvider =
    StateNotifierProvider<ColorSchemeNotifier, AppTheme>((ref) => ColorSchemeNotifier(ref));
