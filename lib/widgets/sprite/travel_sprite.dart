import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/sprite_form.dart';
import 'sprite_painter.dart';
import 'sprite_skin.dart';

/// 悬浮旅行精灵。
///
/// 表情状态由外部（悬浮层）通过 [mood] 驱动：拖拽中、等回复、收到回复……
/// 组件内部只负责节拍：浮动、眨眼、以及长时间无互动后自动打瞌睡。
class TravelSprite extends StatefulWidget {
  const TravelSprite({
    super.key,
    required this.form,
    required this.mood,
    this.size = 76,
    this.interactionTick = 0,
  });

  final SpriteForm form;
  final SpriteMood mood;
  final double size;

  /// 每次外部交互（点击/拖拽）递增此值，用于重置瞌睡计时。
  final int interactionTick;

  @override
  State<TravelSprite> createState() => _TravelSpriteState();
}

class _TravelSpriteState extends State<TravelSprite>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ticker;
  final Stopwatch _watch = Stopwatch();
  Timer? _sleepTimer;
  bool _asleep = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 约 30fps：精灵是配角，不需要 60fps，省电一半
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 33),
    )..repeat();
    _watch.start();
    _restartSleepTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台就停：精灵是配角，不该在看不见的地方耗电
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _ticker.stop();
      _watch.stop();
    } else if (state == AppLifecycleState.resumed && mounted) {
      if (!_watch.isRunning) _watch.start();
      if (!_ticker.isAnimating) _ticker.repeat();
    }
  }

  void _restartSleepTimer() {
    _sleepTimer?.cancel();
    if (_asleep && mounted) setState(() => _asleep = false);
    _sleepTimer = Timer(const Duration(minutes: 3), () {
      if (mounted) setState(() => _asleep = true);
    });
  }

  @override
  void didUpdateWidget(covariant TravelSprite old) {
    super.didUpdateWidget(old);
    if (old.interactionTick != widget.interactionTick) {
      _restartSleepTimer();
    }
    // 任何主动状态（拖拽/思考/说话）都算"被理睬"
    if (widget.mood != old.mood &&
        widget.mood != SpriteMood.idle &&
        widget.mood != SpriteMood.sleepy) {
      _restartSleepTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sleepTimer?.cancel();
    _ticker.dispose();
    _watch.stop();
    super.dispose();
  }

  SpriteMood get _effectiveMood {
    if (_asleep && widget.mood == SpriteMood.idle) return SpriteMood.sleepy;
    return widget.mood;
  }

  @override
  Widget build(BuildContext context) {
    // 皮肤自带明暗两套配色，按当前亮度选取
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        final t = _watch.elapsedMilliseconds / 1000.0;
        final mood = _effectiveMood;
        // 浮动：正常轻缓；瞌睡时更慢更小；被拖时几乎不动
        final amp = mood == SpriteMood.sleepy ? 1.6 : (mood == SpriteMood.dragging ? 0.6 : 3.4);
        final speed = mood == SpriteMood.sleepy ? 0.7 : 1.9;
        final bob = math.sin(t * speed) * amp;
        final sway = math.sin(t * speed * 0.6) * (amp * 0.35);

        return Transform.translate(
          offset: Offset(sway, bob),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: SpritePainter(
                skin: SpriteSkins.of(widget.form, dark: isDark),
                mood: mood,
                t: t,
                dark: isDark,
              ),
            ),
          ),
        );
      },
    );
  }
}
