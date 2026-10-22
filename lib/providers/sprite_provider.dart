import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/router/app_router.dart';
import '../models/sprite_form.dart';
import 'database_provider.dart';

const String _prefsKey = 'sprite_prefs';

/// 与全屏 AI 页共用的会话存储键（保持记忆一致，不产生两套历史）。
const String sessionsKey = 'ai_chat_sessions';

/// 精灵偏好。位置用**归一化坐标**（0..1）存储，
/// 这样换设备/旋转屏幕后不会跑到屏幕外。
class SpritePrefs {
  const SpritePrefs({
    this.enabled = true,
    this.form = SpriteForm.travel,
    this.collapsed = false,
    this.nx,
    this.ny,
  });

  final bool enabled;
  final SpriteForm form;

  /// 贴边折叠（缩成半个身子，不挡内容）。
  final bool collapsed;

  /// 归一化中心坐标；null 表示用默认位置。
  final double? nx;
  final double? ny;

  SpritePrefs copyWith({
    bool? enabled,
    SpriteForm? form,
    bool? collapsed,
    double? nx,
    double? ny,
  }) {
    return SpritePrefs(
      enabled: enabled ?? this.enabled,
      form: form ?? this.form,
      collapsed: collapsed ?? this.collapsed,
      nx: nx ?? this.nx,
      ny: ny ?? this.ny,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'form': form.key,
        'collapsed': collapsed,
        'nx': nx,
        'ny': ny,
      };

  factory SpritePrefs.fromJson(Map<String, dynamic> j) => SpritePrefs(
        enabled: j['enabled'] as bool? ?? true,
        form: SpriteForm.fromKey(j['form'] as String?),
        collapsed: j['collapsed'] as bool? ?? false,
        nx: (j['nx'] as num?)?.toDouble(),
        ny: (j['ny'] as num?)?.toDouble(),
      );
}

class SpriteNotifier extends StateNotifier<SpritePrefs> {
  SpriteNotifier(this._ref) : super(const SpritePrefs()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final raw = await _ref.read(databaseProvider).getSetting(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) state = SpritePrefs.fromJson(m);
    } catch (_) {
      // 损坏则用默认值，不影响使用
    }
  }

  Future<void> _persist(SpritePrefs s) async {
    state = s;
    await _ref
        .read(databaseProvider)
        .setSetting(_prefsKey, jsonEncode(s.toJson()));
  }

  void setEnabled(bool v) => _persist(state.copyWith(enabled: v));
  void setForm(SpriteForm f) => _persist(state.copyWith(form: f));
  void setCollapsed(bool v) => _persist(state.copyWith(collapsed: v));
  void toggleCollapsed() => _persist(state.copyWith(collapsed: !state.collapsed));

  void setPosition(double nx, double ny) =>
      _persist(state.copyWith(nx: nx.clamp(0.0, 1.0), ny: ny.clamp(0.0, 1.0)));
}

final spriteProvider =
    StateNotifierProvider<SpriteNotifier, SpritePrefs>((ref) => SpriteNotifier(ref));

/// 当前路由名，由 [spriteRouteObserver] 维护。
final currentRouteProvider = StateProvider<String?>((ref) => null);

/// 对话窗是否展开（不持久化）。
final spriteChatOpenProvider = StateProvider<bool>((ref) => false);

/// 庆祝信号：每 +1 表示"该高兴一下"（解锁成就时触发）。
/// 悬浮层监听它，让精灵短暂进入 happy 状态——复用已有表情，不新增动画系统。
final spriteCelebrationProvider = StateProvider<int>((ref) => 0);

/// 正在写日志时不显示精灵——写字时被遮挡最烦。
final spriteVisibleProvider = Provider<bool>((ref) {
  final prefs = ref.watch(spriteProvider);
  if (!prefs.enabled) return false;
  final route = ref.watch(currentRouteProvider);
  return route != AppRouter.logEditor;
});

/// 跟踪路由的 NavigatorObserver。
class SpriteRouteObserver extends NavigatorObserver {
  SpriteRouteObserver(this._onRoute);

  final void Function(String? name) _onRoute;

  void _report(Route<dynamic>? route) {
    _onRoute(route?.settings.name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _report(newRoute);
}

final spriteRouteObserverProvider = Provider<SpriteRouteObserver>((ref) {
  return SpriteRouteObserver((name) {
    // 只在变化时写，避免无谓重建
    if (ref.read(currentRouteProvider) != name) {
      ref.read(currentRouteProvider.notifier).state = name;
    }
  });
});
