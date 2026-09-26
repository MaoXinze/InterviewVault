import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';

/// 弧线删除（模式⑧ Curved Card Deletion）：
/// 横向拖出或从卡片菜单触发 → 弹确认框 → 卡片沿弧线飞出并淡出，
/// 数据层删除后由 watch 流自动完成列表回流。
class ArcDismiss extends StatefulWidget {
  const ArcDismiss({super.key, required this.onDeleted, required this.child});

  final VoidCallback onDeleted;
  final Widget child;

  /// 卡片子树内通过 [ArcDismiss.maybeOf] 触发确认删除。
  static ArcDismissState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<ArcDismissState>();

  @override
  State<ArcDismiss> createState() => ArcDismissState();
}

class ArcDismissState extends State<ArcDismiss>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Motion.slow);
  double _dragDx = 0;
  bool _flying = false;
  double _width = 320;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 先确认，确认后从当前位置沿弧线飞出。
  Future<void> confirmAndDismiss() async {
    if (_flying) return;
    final confirmed = await _showConfirmDialog();
    if (!confirmed || !mounted) return;
    await _flyOut();
  }

  Future<bool> _showConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这场面试？'),
        content: const Text('转写稿、标注、问题卡片将一并删除，且不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _flyOut() async {
    if (prefersReducedMotion(context)) {
      widget.onDeleted();
      return;
    }
    _flying = true;
    HapticFeedback.mediumImpact();
    await _controller.forward();
    widget.onDeleted();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_flying) return;
    setState(() => _dragDx = math.max(0, _dragDx + details.delta.dx));
  }

  void _onDragEnd(DragEndDetails details) {
    if (_flying) return;
    final flick = details.velocity.pixelsPerSecond.dx > 900;
    if (_dragDx > _width * 0.45 || (flick && _dragDx > _width * 0.15)) {
      confirmAndDismiss();
    } else {
      setState(() => _dragDx = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = prefersReducedMotion(context);
    // 宽度用 LayoutBuilder 取：build 期间禁止读 context.size
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            // 拖动时从左侧露出的删除提示
            Opacity(
              opacity: (_dragDx / 160).clamp(0.0, 1.0),
              child: Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = Motion.emphasized.transform(_controller.value);
                final dx = _dragDx + (_width * 1.25 - _dragDx) * t;
                final dy = -math.sin(math.pi * t) * 48; // 弧线：先扬后落
                final angle = 0.12 * t;
                final opacity = _flying ? (1 - t).clamp(0.0, 1.0) : 1.0;
                return Transform.translate(
                  offset: Offset(dx, dy),
                  child: Transform.rotate(
                    angle: angle,
                    child: Opacity(opacity: opacity, child: child),
                  ),
                );
              },
              child: GestureDetector(
                onHorizontalDragUpdate: reduced ? null : _onDragUpdate,
                onHorizontalDragEnd: reduced ? null : _onDragEnd,
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}
