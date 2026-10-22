import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 卡片堆叠式图片查看器（相册大图浏览）。
///
/// 版式（对齐参考稿）：
/// - 大照片居中、白框相纸样式（照片本体决定相框大小，不留空边）
/// - 左右相邻照片从后面斜着露出来，向外倾倒并压暗，形成"前后"层次
/// - 底部一排小缩略图预览，点一张跳一张
/// - 整屏深色 + 中心提亮的暗角，卡片与背景分离
///
/// 交互：
/// - 左右滑动切页：位移/缩放/旋转随手指连续变化（真的跟手）
/// - 双击当前照片放大 2.4x（锚定点击点），放大期间锁住翻页，
///   可双指捏合/拖动看细节；捏合回 1x 或再双击复位
/// - 未放大时整屏下滑关闭（随手指缩小淡出）
/// - 底部缩略图当前项自动滚到可见；点两侧的相邻卡直接切到那一张
///
/// 【手势为什么交给 PageView 而不是外层 GestureDetector】
/// 试过在外层 GestureDetector 上自己写 onHorizontalDrag 驱动堆叠，
/// widget test 里拖 150px 页码纹丝不动（识别器没接管）。
/// PageView 的滑动物理是设备上验证过几个月的方案，翻页/甩动/吸附全都现成；
/// 这里只把卡片层叠效果叠在它上面，viewportFraction=0.68 让相邻两页
/// 正好从当前卡两侧露出一角。
class StackedPhotoViewer extends StatefulWidget {
  const StackedPhotoViewer({
    super.key,
    required this.paths,
    this.initialIndex = 0,
    this.title,
    this.subtitle,
    this.onDetails,
    this.captions,
  });

  final List<String> paths;
  final int initialIndex;
  final String? title;
  final String? subtitle;

  /// 传入则在底部显示「城市详情」按钮。
  final VoidCallback? onDetails;

  /// 与 [paths] 等长的逐张说明（如每张照片的 AI 描述）。
  /// 给了它，底部文字就会随左右滑动一起切换；否则沿用固定的 title/subtitle。
  final List<String?>? captions;

  static Future<void> open(BuildContext context, {
    required List<String> paths,
    int initialIndex = 0,
    String? title,
    String? subtitle,
    VoidCallback? onDetails,
    List<String?>? captions,
  }) {
    if (paths.isEmpty) return Future.value();
    return Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => StackedPhotoViewer(
        paths: paths,
        initialIndex: initialIndex,
        title: title,
        subtitle: subtitle,
        onDetails: onDetails,
        captions: captions,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
  }

  @override
  State<StackedPhotoViewer> createState() => _StackedPhotoViewerState();
}

class _StackedPhotoViewerState extends State<StackedPhotoViewer>
    with TickerProviderStateMixin {
  /// 0.68 = 相邻页的露出量：
  /// 相邻槽中心在 ±0.68W，卡片半宽约 0.30W（缩放 0.9 后），
  /// 内边缘落在 0.38W —— 与当前卡（半宽 0.33W）之间留一条缝隙，
  /// 缝隙比卡片倾斜后外凸的角大，保证"后卡"永远不会盖到当前卡上。
  static const double _viewportFraction = 0.68;

  late final PageController _pager;
  final ScrollController _thumbCtrl = ScrollController();
  final TransformationController _transCtrl = TransformationController();

  /// 双击放大/复位的矩阵补间动画。
  late final AnimationController _zoomAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260));
  late final Animation<double> _zoomCurve =
      CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic);
  Matrix4Tween? _zoomTween;

  /// 下滑关闭的回弹动画。
  late final AnimationController _settleAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));
  double _settleFrom = 0;

  late int _index;
  bool _zoomed = false;
  bool _zoomOuting = false; // 正在动画复位（结束后卸载 InteractiveViewer）
  Offset? _zoomTapPos;

  /// 下滑关闭的累计位移（只往下，不往上）。
  double _dismissDy = 0;

  int get _total => widget.paths.length;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _total - 1);
    _pager = PageController(initialPage: _index, viewportFraction: _viewportFraction);

    _zoomAnim.addListener(() {
      final tween = _zoomTween;
      if (tween == null || !_zoomAnim.isAnimating) return;
      _transCtrl.value = tween.evaluate(_zoomCurve);
    });
    _zoomAnim.addStatusListener((status) {
      // 复位动画结束后才卸载 InteractiveViewer，动画期间照片不能闪回未放大状态
      if (status == AnimationStatus.completed && _zoomOuting && mounted) {
        setState(() {
          _zoomed = false;
          _zoomOuting = false;
          _transCtrl.value = Matrix4.identity();
        });
      }
    });
    _settleAnim.addListener(() {
      if (!_settleAnim.isAnimating || !mounted) return;
      setState(() => _dismissDy = ui.lerpDouble(_settleFrom, 0,
              Curves.easeOut.transform(_settleAnim.value))!
          .clamp(0.0, 220.0));
    });

    // 初始就停在后页时，缩略图条滚到该页可见
    if (_total > 1) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollThumbTo(_index));
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    _thumbCtrl.dispose();
    _transCtrl.dispose();
    _zoomAnim.dispose();
    _settleAnim.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0 || i >= _total || i == _index) return;
    _pager.animateToPage(i,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _onPageChanged(int i) {
    // 切页时把上一张的放大状态立即复位（此时旧卡已不可见，无需动画）
    _zoomAnim.stop();
    _zoomTween = null;
    _zoomOuting = false;
    if (_transCtrl.value != Matrix4.identity()) {
      _transCtrl.value = Matrix4.identity();
    }
    setState(() {
      _zoomed = false;
      _index = i;
      _dismissDy = 0;
    });
    _scrollThumbTo(i);
  }

  // ==================== 放大 / 复位 ====================

  void _animateZoom(Matrix4 target, {required bool toIdentity}) {
    _zoomTween = Matrix4Tween(begin: _transCtrl.value, end: target);
    _zoomOuting = toIdentity;
    _zoomAnim.forward(from: 0);
  }

  void _onImageDoubleTap() {
    if (_zoomed) {
      _animateZoom(Matrix4.identity(), toIdentity: true);
    } else {
      final p = _zoomTapPos ?? Offset.zero;
      const s = 2.4;
      final m = Matrix4.identity()
        ..setEntry(0, 0, s)
        ..setEntry(1, 1, s)
        ..setEntry(0, 3, (1 - s) * p.dx)
        ..setEntry(1, 3, (1 - s) * p.dy);
      // 先挂上 InteractiveViewer（_zoomed=true），再驱动矩阵动画，
      // 进入/退出两头都是平滑的
      setState(() {
        _zoomed = true;
        _zoomOuting = false;
      });
      _animateZoom(m, toIdentity: false);
    }
  }

  /// 点当前照片：放大态复位；未放大则关闭查看器。
  void _onImageTap() {
    if (_zoomed) {
      _animateZoom(Matrix4.identity(), toIdentity: true);
    } else {
      Navigator.pop(context);
    }
  }

  /// 双指开始捏合时停掉双击动画，避免两边同时写 controller。
  void _onZoomInteractionStart(ScaleStartDetails d) => _zoomAnim.stop();

  /// 捏合回到 ~1x 自动退出放大，恢复翻页。
  void _onZoomInteractionEnd(ScaleEndDetails d) {
    if (_zoomed && _transCtrl.value.getMaxScaleOnAxis() <= 1.05) {
      _animateZoom(Matrix4.identity(), toIdentity: true);
    }
  }

  // ==================== 下滑关闭 ====================

  void _onDismissDragUpdate(DragUpdateDetails d) {
    _settleAnim.stop();
    setState(() => _dismissDy = (_dismissDy + d.delta.dy).clamp(0.0, 220.0));
  }

  void _onDismissDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    if (_dismissDy > 120 || v > 800) {
      Navigator.pop(context);
    } else {
      _settleFrom = _dismissDy;
      _settleAnim.forward(from: 0);
    }
  }

  // ==================== 缩略图条 ====================

  static const double _thumbW = 32;
  static const double _thumbGap = 5;

  void _scrollThumbTo(int i) {
    if (!_thumbCtrl.hasClients) return;
    final pos = _thumbCtrl.position;
    const itemW = _thumbW + _thumbGap;
    final target = (i * itemW + 16 - (pos.viewportDimension - _thumbW) / 2)
        .clamp(0.0, pos.maxScrollExtent);
    _thumbCtrl.animateTo(target,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  // ==================== build ====================

  @override
  Widget build(BuildContext context) {
    final dismissT = (_dismissDy / 700).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF101114),
      body: Stack(
        children: [
          // 氛围底色：当前照片的极小 cover 版重度模糊、重度压暗后铺底。
          // 只保留一点色调，不抢卡片；纯黑在窄高屏上会显得空。
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            child: _Backdrop(
              key: ValueKey<String>(widget.paths[_index]),
              path: widget.paths[_index],
            ),
          ),

          Column(
            children: [
              Expanded(
                child: GestureDetector(
                  // 垂直下滑关闭；放大时让位给 InteractiveViewer
                  onVerticalDragUpdate:
                      _zoomed ? null : _onDismissDragUpdate,
                  onVerticalDragEnd: _zoomed ? null : _onDismissDragEnd,
                  onTap: () {
                    if (_zoomed) {
                      _animateZoom(Matrix4.identity(), toIdentity: true);
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(0, _dismissDy),
                    child: Transform.scale(
                      scale: 1 - 0.16 * dismissT,
                      child: Opacity(
                        opacity: 1 - 0.5 * dismissT,
                        child: AnimatedBuilder(
                          animation: _pager,
                          builder: (context, _) {
                            // 连续页位置：滑动过程中相邻卡片实时倾斜/缩放
                            final page = _pager.hasClients &&
                                    _pager.position.haveDimensions
                                ? (_pager.page ?? _index.toDouble())
                                : _index.toDouble();
                            return PageView.builder(
                              controller: _pager,
                              // 放大时锁页：看细节时滑动不应该误触切页
                              physics: _zoomed
                                  ? const NeverScrollableScrollPhysics()
                                  : null,
                              itemCount: _total,
                              onPageChanged: _onPageChanged,
                              itemBuilder: (context, i) => _Card(
                                path: widget.paths[i],
                                offset: i - page,
                                active: i == _index,
                                zoomed: i == _index && _zoomed,
                                transformationController: _transCtrl,
                                onDoubleTapDown: (p) => _zoomTapPos = p,
                                onDoubleTap: _onImageDoubleTap,
                                onTap: _onImageTap,
                                onSelect: () => _go(i),
                                onZoomInteractionStart: _onZoomInteractionStart,
                                onZoomInteractionEnd: _onZoomInteractionEnd,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _bottomBar(),
            ],
          ),

          // 顶部：计数 + 关闭
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(120),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withAlpha(30)),
                    ),
                    child: Text('${_index + 1} / $_total',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white, letterSpacing: 1)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 当前应显示的标题：有 captions 时随页码切换，否则用固定 title。
  String? get _headline {
    final caps = widget.captions;
    if (caps != null && _index < caps.length) {
      final c = caps[_index];
      if (c != null && c.trim().isNotEmpty) return c.trim();
      // 该张没有描述时退回固定标题，避免出现空白区
      return widget.title;
    }
    return widget.title;
  }

  bool get _hasCaptionMode => (widget.captions?.length ?? 0) == widget.paths.length;

  Widget _bottomBar() {
    final headline = _headline;
    final hasText = headline != null ||
        widget.subtitle != null ||
        widget.onDetails != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (headline != null)
              Text(
                headline,
                textAlign: TextAlign.center,
                // AI 描述可能较长，允许多行而不是截成一行的省略号
                maxLines: _hasCaptionMode ? 3 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: _hasCaptionMode ? 14.5 : 19,
                    fontWeight: _hasCaptionMode ? FontWeight.w600 : FontWeight.w800,
                    height: _hasCaptionMode ? 1.45 : 1.2,
                    color: Colors.white,
                    letterSpacing: _hasCaptionMode ? 0.2 : 1.2,
                    shadows: const [Shadow(blurRadius: 12, color: Colors.black87)]),
              ),
            if (!(_hasCaptionMode && headline != null) &&
                widget.subtitle != null) ...[
              const SizedBox(height: 3),
              Text(widget.subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withAlpha(190),
                      shadows: const [
                        Shadow(blurRadius: 8, color: Colors.black87)
                      ])),
            ],
            if (widget.onDetails != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onDetails,
                icon: const Icon(Icons.info_outline,
                    size: 15, color: Color(0xFF9FE4FF)),
                label: const Text('查看城市详情',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9FE4FF))),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black.withAlpha(130),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: Colors.white.withAlpha(50)),
                  ),
                ),
              ),
            ],
            SizedBox(height: hasText ? 10 : 0),
            if (_total > 1)
              SizedBox(
                height: 44,
                child: ListView.separated(
                  controller: _thumbCtrl,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _total,
                  separatorBuilder: (_, __) => const SizedBox(width: _thumbGap),
                  itemBuilder: (context, i) {
                    final active = i == _index;
                    return GestureDetector(
                      onTap: () => _go(i),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: active ? 1 : 0.5,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _thumbW,
                          height: active ? 44 : 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: active ? Colors.white : Colors.white24,
                              width: active ? 1.6 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          // cacheWidth：32px 的缩略图不该解码 4000px 原图
                          child: Image.file(File(widget.paths[i]),
                              fit: BoxFit.cover,
                              cacheWidth: 96,
                              errorBuilder: (_, __, ___) => Container(
                                  color: Colors.white10,
                                  child: const Icon(Icons.broken_image_outlined,
                                      size: 16, color: Colors.white24))),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 深色氛围底：当前照片重模糊 + 压暗，再叠一层中心提亮的暗角。
class _Backdrop extends StatelessWidget {
  const _Backdrop({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.38,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              // 只为取色，解码必须极小，否则每页都是一次大图解码
              cacheWidth: 48,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF101114)),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(color: Color(0x99000000)),
        ),
        // 中心亮、四周暗：卡片浮起来的错觉
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.85,
              colors: [Color(0x14FFFFFF), Color(0x00000000), Color(0x66000000)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// 单张卡片：横向位置由 PageView 决定；这里只按相对当前页的连续偏移量
/// 做"退到后面"的效果（缩小 + 向外倾倒 + 压暗），滑动中连续变化、跟手。
///
/// 【为什么不做重叠式堆叠】PageView 按下标顺序绘制，右邻页永远画在
/// 当前页之上。靠 viewportFraction=0.68 留出的缝隙，保证两卡互不搭界，
/// 绘制顺序就不影响观感；旋转外凸的角也设计在缝隙之内。
class _Card extends StatelessWidget {
  const _Card({
    required this.path,
    required this.offset,
    required this.active,
    required this.zoomed,
    required this.transformationController,
    required this.onDoubleTapDown,
    required this.onDoubleTap,
    required this.onTap,
    required this.onSelect,
    required this.onZoomInteractionStart,
    required this.onZoomInteractionEnd,
  });

  final String path;

  /// 相对当前页的偏移（左负右正），滑动中连续取值。
  final double offset;
  final bool active;

  /// 仅当前卡片为 true 时挂 InteractiveViewer。
  final bool zoomed;
  final TransformationController transformationController;
  final ValueChanged<Offset> onDoubleTapDown;
  final VoidCallback onDoubleTap;
  final VoidCallback onTap;

  /// 点非当前卡：切到那一张，而不是直接关掉查看器。
  final VoidCallback onSelect;
  final GestureScaleStartCallback onZoomInteractionStart;
  final GestureScaleEndCallback onZoomInteractionEnd;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final clamped = offset.clamp(-2.0, 2.0);
    final abs = clamped.abs();
    // 邻居缩小 + 向外倾倒，都按偏移线性给，滑动过程里连续变化。
    // 角度 0.05rad(≈2.9°)：外凸的角(sin×半高≈12px) < 缝隙(≈28px)，
    // 不会碰到当前卡
    final scale = (1.0 - 0.10 * abs).clamp(0.70, 1.0);
    final angle = 0.05 * clamped.clamp(-1.0, 1.0);
    final dim = (0.30 * abs).clamp(0.0, 0.45);

    // 照片本体（点击/双击在手势层，位于 InteractiveViewer 内侧，
    // 这样双击坐标是照片本地坐标，放大锚点才准确）
    Widget photo = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (d) => onDoubleTapDown(d.localPosition),
      onDoubleTap: active ? onDoubleTap : onSelect,
      onTap: active ? onTap : onSelect,
      // contain 不裁照片：cover 会把风景照的四边裁掉，看细节时缺失信息
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        // 放大到 3.5x 时按 3.5 × 卡片宽反推，1800 是
        // "看得清细节"和"单张内存别太狠"之间的折中
        cacheWidth: 1800,
        errorBuilder: (_, __, ___) => const ColoredBox(
            color: Color(0xFF202225),
            child: Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.white38))),
      ),
    );

    // 只在放大态挂 InteractiveViewer：常挂会抢走 PageView 的滑动手势，
    // 导致翻页失灵（InteractiveViewer 在可滚动容器里的老问题）。
    if (zoomed) {
      photo = InteractiveViewer(
        transformationController: transformationController,
        minScale: 1.0,
        maxScale: 3.5,
        panEnabled: true,
        onInteractionStart: onZoomInteractionStart,
        onInteractionEnd: onZoomInteractionEnd,
        child: photo,
      );
    }

    Widget card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((190 * (1 - dim)).round()),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      // 相纸白边；照片自己决定相框尺寸，不留空边
      padding: const EdgeInsets.all(8),
      child: photo,
    );

    // 压暗整张卡（含白边），远处的卡是"退到后面"的灰白，不是亮白
    if (dim > 0) {
      card = Stack(
        children: [
          card,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha((255 * dim).round()),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Transform.rotate(
      angle: angle,
      child: Transform.scale(
        scale: scale,
        child: Center(
          child: ConstrainedBox(
            // 高宽都按屏幕比例限：竖构图照片受宽度约束，横构图受高度约束，
            // 相框贴着照片走，不会出现撑满空壳的情况
            constraints: BoxConstraints(
              maxWidth: size.width * 0.66,
              maxHeight: size.height * 0.60,
            ),
            child: card,
          ),
        ),
      ),
    );
  }
}
