import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/sprite_form.dart';
import '../../providers/sprite_provider.dart';
import 'sprite_bubble.dart';
import 'travel_sprite.dart';

/// 全局精灵悬浮层：包在 MaterialApp.builder 里，因此所有页面之上都有它。
/// 支持拖拽、松手吸边、贴边折叠、单击开合对话窗、双击进全屏对话、长按菜单。
class SpriteOverlay extends ConsumerStatefulWidget {
  const SpriteOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SpriteOverlay> createState() => _SpriteOverlayState();
}

class _SpriteOverlayState extends ConsumerState<SpriteOverlay> {
  static const double _sprite = 76;

  Offset _pos = Offset.zero;
  Size _screen = Size.zero;
  bool _onLeft = false;
  int _tick = 0;
  SpriteMood _mood = SpriteMood.idle;

  // 小对话窗位置：null 表示按精灵位置自动摆放，用户拖过之后改为手动值
  Offset? _bubblePos;

  static const Size _bubbleSize = Size(306, 430);

  /// 打开对话窗时把窗口重置为"跟随精灵"，避免沿用上次的拖拽位置。
  void _resetBubblePosition() => setState(() => _bubblePos = null);

  /// 拖拽开始：若还没被手动拖过，先把当前位置固化下来，
  /// 否则后续 delta 会相对"自动位置"累加导致跳位。
  void _bubbleDragStart(Offset global) {
    if (_bubblePos == null) {
      setState(() => _bubblePos = _autoBubblePos());
    }
  }

  void _bubbleDragUpdate(Offset delta) {
    setState(() {
      final base = _bubblePos ?? _autoBubblePos();
      _bubblePos = _clampBubble(base + delta);
    });
  }

  Offset _autoBubblePos() {
    final left = _onLeft;
    final x = left ? _pos.dx + _sprite + 8 : _pos.dx - _bubbleSize.width - 8;
    final y = _bubbleTopValue();
    return _clampBubble(Offset(x.isNegative ? 8 : x, y));
  }

  Offset _clampBubble(Offset p) {
    final topInset = MediaQuery.paddingOf(context).top + 8;
    final maxX = (_screen.width - _bubbleSize.width - 8).clamp(8.0, double.infinity);
    final maxY = (_screen.height - _bubbleSize.height - 8).clamp(topInset, double.infinity);
    return Offset(p.dx.clamp(8.0, maxX), p.dy.clamp(topInset, maxY));
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = MediaQuery.sizeOf(context);
    if (s != _screen) {
      _screen = s;
      _initPosition();
    }
  }

  void _initPosition() {
    final prefs = ref.read(spriteProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom + 150;
    _pos = Offset(
      prefs.nx != null ? prefs.nx! * _screen.width : _screen.width - _sprite - 10,
      prefs.ny != null
          ? prefs.ny! * _screen.height
          : _screen.height - bottomInset - _sprite - 40,
    );
    _clamp();
    _onLeft = _pos.dx < _screen.width / 2;
  }

  void _clamp() {
    final topInset = MediaQuery.paddingOf(context).top + 8;
    // 底部要避开两块：导航栏 + 右下角 FAB。
    // 之前只留 76，结果精灵会压在「新建旅程」按钮上（真机截图发现）。
    final bottomInset = MediaQuery.paddingOf(context).bottom + 150;
    _pos = Offset(
      _pos.dx.clamp(4.0, (_screen.width - _sprite - 4).clamp(4.0, double.infinity)),
      _pos.dy.clamp(topInset, (_screen.height - bottomInset - _sprite).clamp(topInset, double.infinity)),
    );
  }

  /// 松手吸边：靠近哪边就贴哪边，避免悬在中间挡内容。
  void _snapToEdge() {
    setState(() {
      _onLeft = _pos.dx + _sprite / 2 < _screen.width / 2;
      _pos = Offset(_onLeft ? 2 : _screen.width - _sprite - 2, _pos.dy);
      ref
          .read(spriteProvider.notifier)
          .setPosition(_pos.dx / _screen.width, _pos.dy / _screen.height);
    });
  }

  void _toggleChat() {
    setState(() {
      _tick++;
      _mood = SpriteMood.happy;
    });
    final open = !ref.read(spriteChatOpenProvider);
    ref.read(spriteChatOpenProvider.notifier).state = open;
    if (open) {
      _resetBubblePosition();
    } else {
      setState(() => _mood = SpriteMood.idle);
    }
    _resetIdle();
  }

  void _resetIdle() {
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _mood = SpriteMood.idle);
    });
  }

  /// 庆祝：让精灵高兴约 2.5 秒后回落到当前状态。
  void _celebrate() {
    setState(() {
      _mood = SpriteMood.happy;
      _tick++;
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && _mood == SpriteMood.happy) setState(() => _mood = SpriteMood.idle);
    });
  }

  Future<void> _showMenu() async {
    final prefs = ref.read(spriteProvider);
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text('换个形象',
                style: Theme.of(ctx)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final f in SpriteForm.values)
                  ChoiceChip(
                    selected: prefs.form == f,
                    showCheckmark: false,
                    avatar: Icon(f.icon, size: 17),
                    label: Text(f.name),
                    onSelected: (_) {
                      ref.read(spriteProvider.notifier).setForm(f);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
            const Divider(height: 22),
            ListTile(
              leading: Icon(prefs.collapsed ? Icons.arrow_forward : Icons.arrow_back,
                  color: cs.outline),
              title: Text(prefs.collapsed ? '展开精灵' : '贴边折叠（不挡内容）'),
              onTap: () {
                ref.read(spriteProvider.notifier).toggleCollapsed();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('隐藏精灵'),
              onTap: () {
                ref.read(spriteProvider.notifier).setEnabled(false);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('全屏 AI 对话'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/chat/ai');
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(spriteProvider);
    final visible = ref.watch(spriteVisibleProvider);
    final chatOpen = ref.watch(spriteChatOpenProvider);

    // 解锁成就时精灵跟着高兴一下
    ref.listen(spriteCelebrationProvider, (prev, next) {
      if (next != prev) _celebrate();
    });

    return Stack(
      children: [
        widget.child,
        if (visible)
          Positioned(
            left: _pos.dx,
            top: _pos.dy,
            child: _buildSprite(prefs),
          ),
        if (visible && chatOpen)
          Positioned(
            left: (_bubblePos ?? _autoBubblePos()).dx,
            top: (_bubblePos ?? _autoBubblePos()).dy,
            // 【必须包一层 Overlay】真机 logcat 显示：点击输入框时
            // EditableTextState._handleSelectionChanged → SelectionOverlay.showHandles
            // → Overlay.of(context) 抛 "Null check operator used on a null value"。
            // 本组件挂在 MaterialApp.builder 里、不在 Navigator 的 Overlay 之下，
            // 文字光标/选择手柄无处渲染，异常还会打断文本状态同步 ——
            // 表现就是"发送后输入框看似清空、实际残留，再打字变成你好上海"。
            // Overlay 必须有界尺寸，否则会吃掉整屏并挡住底层手势；
            // 小窗本身是固定 306×430，直接按这个尺寸约束。
            child: SizedBox(
              width: _bubbleSize.width,
              height: _bubbleSize.height,
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => SpriteBubble(
                      form: prefs.form,
                      onDragStart: _bubbleDragStart,
                      onDragUpdate: _bubbleDragUpdate,
                      onOpenFullChat: () {
                        ref.read(spriteChatOpenProvider.notifier).state = false;
                        Navigator.pushNamed(context, '/chat/ai');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  double _bubbleTopValue() {
    const h = 430.0;
    final topInset = MediaQuery.paddingOf(context).top + 8;
    final maxTop = _screen.height - MediaQuery.paddingOf(context).bottom - h - 76;
    return (_pos.dy - 40).clamp(topInset, maxTop > topInset ? maxTop : topInset);
  }

  Widget _buildSprite(SpritePrefs prefs) {
    // 折叠：把身子的一半挪出屏幕边缘
    final shift = prefs.collapsed ? (_onLeft ? -_sprite * 0.55 : _sprite * 0.55) : 0.0;

    return SizedBox(
      width: _sprite,
      height: _sprite,
      child: Transform.translate(
        offset: Offset(shift, 0),
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: _toggleChat,
          onDoubleTap: () {
            ref.read(spriteChatOpenProvider.notifier).state = false;
            Navigator.pushNamed(context, '/chat/ai');
          },
          onLongPress: _showMenu,
          onPanStart: (d) => setState(() {
            _mood = SpriteMood.dragging;
            _tick++;
          }),
          onPanUpdate: (d) => setState(() {
            _pos += d.delta;
            _clamp();
          }),
          onPanEnd: (d) {
            _snapToEdge();
            _resetIdle();
          },
          // 只有精灵本体可点：外层 SizedBox 的透明区域不吞手势
          child: TravelSprite(
            form: prefs.form,
            mood: _mood,
            size: _sprite,
            interactionTick: _tick,
          ),
        ),
      ),
    );
  }
}
