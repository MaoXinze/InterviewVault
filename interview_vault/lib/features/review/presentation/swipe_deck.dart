import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion.dart';

/// 横滑提交判定（纯函数）：位移超过卡宽 45%，或快速轻扫（>900px/s）超 15%。
/// 阈值口径与 ArcDismiss 一致（同类手势同一肌肉记忆）。
bool commitSwipe({
  required double dx,
  required double width,
  required double vx,
}) {
  final adx = dx.abs();
  return adx > width * 0.45 || (vx.abs() > 900 && adx > width * 0.15);
}

/// 拖动中卡片的变换（纯函数）：rotateZ 倾斜跟随指尖 + 速度形变
/// （波态形变：拖动轴按速度拉伸、垂直轴轻微压缩保持体积感）。
/// 只产 Transform，不触发布局；squish 取自最近拖动位移（≈帧速度）。
Matrix4 swipeCardTransform({
  required double dx,
  required double width,
  required double squish,
}) {
  if (dx == 0 && squish == 0) return Matrix4.identity();
  final progress = (dx / width).clamp(-1.0, 1.0).toDouble();
  // 封顶 5% 拉伸：文字永不失真
  final stretch = (squish.abs() * 0.0011).clamp(0.0, 0.05).toDouble();
  // M = Rz·S：先在卡片空间缩放再倾斜，小角度下形变始终沿运动方向
  return Matrix4.identity()
    ..rotateZ(progress * 0.12)
    ..scaleByDouble(1.0 + stretch, 1.0 - stretch * 0.75, 1.0, 1.0);
}

/// 背后下一张卡的变换（纯函数，层级视差）：静止时下沉 6px 露出底边
/// （卡片堆隐喻），拖动越深越收拢（反向缩放制造前后景层次）。
Matrix4 deckBehindTransform(double progress) {
  final p = progress.clamp(0.0, 1.0).toDouble();
  final scale = 1.0 - 0.04 * p;
  return Matrix4.identity()
    ..translateByDouble(0.0, 6 * (1 - p), 0.0, 1.0)
    ..scaleByDouble(scale, scale, 1.0, 1.0);
}

/// 补位卡的落位起点：与 [deckBehindTransform] 拖到底的缩放一致，
/// 新卡从 0.96 弹到 1.0（spring 过冲），换卡零跳变。
const double _landingScale = 0.96;

/// 滑动方向：右滑 = 已复习，左滑 = 跳过。
enum SwipeDirection { right, left }

/// 横滑卡片堆（翻卡页专用交互底座）：
///
/// - 手势推进：横滑过阈值即提交（onCommit），松手未过阈值弹性回位
/// - 速度形变 + 倾斜 + 背后卡片反向缩放（见纯函数）
/// - 提交后当前卡沿原方向飞出淡出，背后的卡弹起补位（spring）
/// - 只做 Transform + RepaintBoundary：拖动每帧仅重复合成，不重排不重绘内容
/// - 减弱动态效果：拖动保留（功能性输入）但无视觉形变，提交直达终态
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    super.key,
    required this.front,
    this.behind,
    required this.onCommit,
    this.padding = const EdgeInsets.all(20),
    this.stampBuilder,
  });

  /// 当前卡（含点击翻面的手势，堆只负责横滑与变换）
  final Widget front;

  /// 下一张预览（卡片堆视差层；null = 最后一张）
  final Widget? behind;

  final EdgeInsetsGeometry padding;

  /// 提交回调：飞出动画结束后调用，deck 等待其完成（数据推进/落库）
  /// 再落位——保证落位后正面即新卡，无旧卡闪回。
  final Future<void> Function(SwipeDirection direction) onCommit;

  /// 判定章（Quizlet 式）：随拖动进度 (-1..1) 出现的叠层，
  /// 画在卡片坐标系内（跟随倾斜/形变），不拦截手势。null = 无。
  final Widget Function(double progress)? stampBuilder;

  @override
  State<SwipeDeck> createState() => _SwipeDeckState();
}

enum _DeckMode { idle, dragging, flying, settling, landing }

class _SwipeDeckState extends State<SwipeDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Motion.swipe);

  _DeckMode _mode = _DeckMode.idle;
  double _dx = 0;
  double _squish = 0;
  double _width = 320;

  /// 松手瞬间的快照（飞出/回位动画的插值起点）
  double _dxAtRelease = 0;
  double _squishAtRelease = 0;
  double _progressAtRelease = 0;
  SwipeDirection _direction = SwipeDirection.right;

  bool get _reduced => prefersReducedMotion(context);

  bool get _busy =>
      _mode == _DeckMode.flying ||
      _mode == _DeckMode.settling ||
      _mode == _DeckMode.landing;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _progress => (_dx / _width).clamp(-1.0, 1.0).toDouble();

  void _onDragStart(DragStartDetails details) {
    if (_busy) return;
    _mode = _DeckMode.dragging;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_mode != _DeckMode.dragging) return;
    _dx += details.delta.dx;
    // 平滑逼近本帧位移 ≈ 速度信号；快速拖动形变更明显
    _squish = _squish * 0.55 + details.delta.dx.abs() * 0.45;
    if (!_reduced) setState(() {});
  }

  void _onDragEnd(DragEndDetails details) {
    if (_mode != _DeckMode.dragging) return;
    final vx = details.velocity.pixelsPerSecond.dx;
    if (commitSwipe(dx: _dx, width: _width, vx: vx)) {
      _commit(_dx >= 0 ? SwipeDirection.right : SwipeDirection.left);
    } else {
      _settleBack();
    }
  }

  Future<void> _commit(SwipeDirection direction) async {
    _direction = direction;
    HapticFeedback.mediumImpact();
    if (_reduced) {
      // 减弱动态效果：直达终态，无飞出/落位动画
      await widget.onCommit(direction);
      if (mounted) _resetIdle();
      return;
    }
    _dxAtRelease = _dx;
    _squishAtRelease = _squish;
    _progressAtRelease = _progress.abs();
    setState(() => _mode = _DeckMode.flying);
    await _controller.forward(from: 0);
    await widget.onCommit(direction);
    if (!mounted) return;
    // 落位：新卡从背后卡的收拢态（0.96）弹回 1.0，衔接无跳变
    setState(() => _mode = _DeckMode.landing);
    await _controller.forward(from: 0);
    if (mounted) _resetIdle();
  }

  Future<void> _settleBack() async {
    _dxAtRelease = _dx;
    _squishAtRelease = _squish;
    _progressAtRelease = _progress.abs();
    setState(() => _mode = _DeckMode.settling);
    await _controller.forward(from: 0);
    if (mounted) _resetIdle();
  }

  void _resetIdle() {
    setState(() {
      _mode = _DeckMode.idle;
      _dx = 0;
      _squish = 0;
      _controller.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 卡片净宽（阈值/视差按可见卡面计算，不含外边距）
          _width = constraints.maxWidth;
          Widget front = GestureDetector(
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: widget.front,
          );
          final stampBuilder = widget.stampBuilder;
          if (stampBuilder != null) {
            front = Stack(
              textDirection: TextDirection.ltr,
              children: [
                front,
                Positioned.fill(
                  child: IgnorePointer(child: stampBuilder(_progress)),
                ),
              ],
            );
          }
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final (frontMatrix, behindProgress, opacity) = _solve();
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.behind != null)
                    RepaintBoundary(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: deckBehindTransform(behindProgress),
                        child: widget.behind,
                      ),
                    ),
                  RepaintBoundary(
                    child: Opacity(
                      opacity: opacity,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: frontMatrix,
                        child: child,
                      ),
                    ),
                  ),
                ],
              );
            },
            child: front,
          );
        },
      ),
    );
  }

  /// 按当前模式解出正面变换 / 背后视差进度 / 正面不透明度。
  (Matrix4, double, double) _solve() {
    switch (_mode) {
      case _DeckMode.flying:
        final t = Motion.emphasized.transform(_controller.value);
        final from =
            _direction == SwipeDirection.right ? _progressAtRelease : -_progressAtRelease;
        // 飞向屏幕外并带旋转淡出（位移超界部分由淡出接管）
        final target = _direction == SwipeDirection.right ? 1.9 : -1.9;
        final progress = lerpDouble(from, target, t)!;
        final matrix = swipeCardTransform(
          dx: progress * _width,
          width: _width,
          squish: _squishAtRelease * (1 - t),
        );
        return (matrix, lerpDouble(_progressAtRelease, 1, t)!, 1 - t);
      case _DeckMode.settling:
        final t = Motion.spring.transform(_controller.value);
        // spring 过冲 → dx 短暂反向，形成回弹手感
        final dx = _dxAtRelease * (1 - t);
        final matrix = swipeCardTransform(
          dx: dx,
          width: _width,
          squish: _squishAtRelease * (1 - t),
        );
        return (matrix, lerpDouble(_progressAtRelease, 0, t)!, 1.0);
      case _DeckMode.landing:
        final t = Motion.spring.transform(_controller.value);
        final scale = lerpDouble(_landingScale, 1.0, t)!;
        return (Matrix4.identity()..scaleByDouble(scale, scale, 1.0, 1.0), 0.0, 1.0);
      case _DeckMode.dragging:
      case _DeckMode.idle:
        final matrix = _reduced
            ? Matrix4.identity()
            : swipeCardTransform(dx: _dx, width: _width, squish: _squish);
        return (matrix, _progress.abs(), 1.0);
    }
  }
}
