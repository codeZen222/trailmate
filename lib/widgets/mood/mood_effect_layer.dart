import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../../models/mood_type.dart';
import 'mood_painter.dart';

/// 心情特效层：铺在内容下方的动画背景。
///
/// 性能与体验护栏：
/// - 约 30fps 驱动（淡雅特效无需 60fps，明显省电）
/// - App 退到后台自动暂停计时与动画
/// - 尊重系统「减弱动态效果」→ 只画一帧静态
/// - [enabled] 为 false 或心情为 null 时完全不渲染
/// - `IgnorePointer` 包裹，绝不拦截上层手势
class MoodEffectLayer extends StatefulWidget {
  const MoodEffectLayer({
    super.key,
    required this.mood,
    this.enabled = true,
    this.seed = 1,
    this.animate = true,
    this.staticTime = 1.2,
  });

  final MoodType? mood;
  final bool enabled;
  /// 不同日志用不同种子，避免所有页面粒子排布一模一样。
  final int seed;

  /// 是否持续播放。分享海报这类"看一眼就截走"的场景应传 false：
  /// 既省掉常驻 30fps 重绘（实测是切特效卡顿的主因之一），
  /// 也让截图时刻的画面稳定可预期。
  final bool animate;

  /// animate=false 时取用的时间点。
  final double staticTime;

  @override
  State<MoodEffectLayer> createState() => _MoodEffectLayerState();
}

class _MoodEffectLayerState extends State<MoodEffectLayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ticker;
  final Stopwatch _watch = Stopwatch();
  List<MoodParticle> _particles = const [];
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reduceMotion = SchedulerBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    // 33ms ≈ 30fps
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 33),
    );
    _prepare();
  }

  void _prepare() {
    final mood = widget.mood;
    if (mood == null || !widget.enabled) {
      _particles = const [];
      _ticker.stop();
      _watch.stop();
      return;
    }
    _particles = MoodParticle.make(72, widget.seed + mood.key.hashCode & 0xffff);
    // 【必须重置时间轴】之前这里从不 reset，切特效时秒表已累加到几十秒。
    // 粒子位置含 t*speed 且部分分支对 t 取模方式不同，t 过大既浪费计算
    // 也会让画面看起来"糊成一团"，配合每帧重绘就是实测到的越用越卡。
    _watch
      ..stop()
      ..reset()
      ..start();
    if (_reduceMotion || !widget.animate) {
      // 静态：只画一帧，不起 ticker
      _ticker.stop();
      return;
    }
    // repeat() 会持续排帧；先 stop 再 repeat 确保不会叠加多个动画循环
    _ticker
      ..stop()
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant MoodEffectLayer old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood ||
        old.enabled != widget.enabled ||
        old.seed != widget.seed ||
        old.animate != widget.animate) {
      _prepare();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _ticker.stop();
      _watch.stop();
    } else if (state == AppLifecycleState.resumed && mounted) {
      _prepare();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;
    if (mood == null || !widget.enabled || _particles.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget painted(double t) => CustomPaint(
          size: Size.infinite,
          painter: MoodPainter(mood: mood, t: t, particles: _particles),
        );

    return Positioned.fill(
      child: IgnorePointer(
        child: (_reduceMotion || !widget.animate)
            ? painted(widget.staticTime) // 静态取一个好看的时刻
            : AnimatedBuilder(
                animation: _ticker,
                // 把时间折回 [0, cycle) 区间：粒子的运动周期远小于此，
                // 长时间停留在本页时不让 t 无限增大（既省浮点开销也避免累积误差）
                builder: (_, __) => painted(
                    (_watch.elapsedMilliseconds % _cycleMs) / 1000.0),
              ),
      ),
    );
  }

  /// 动画循环周期（毫秒），所有粒子运动都在这个窗口内重复。
  static const int _cycleMs = 60000;
}
