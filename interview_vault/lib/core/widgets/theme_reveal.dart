import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../motion.dart';

/// 圆形主题切换（模式① Radial Theme Transition）：
/// 截取旧帧 → 应用新主题（新帧在底层渲染）→ 在旧帧快照上开一个
/// 从触发点不断扩张的圆孔，新主题从孔中"揭示"出来。
///
/// 降级路径：截屏失败或系统开启"减弱动态效果"时直接切换主题。
class ThemeRevealController extends ChangeNotifier {
  /// 包住 MaterialApp 的 RepaintBoundary，用于截取旧帧
  final GlobalKey boundaryKey = GlobalKey(debugLabel: 'themeRevealBoundary');

  ui.Image? _snapshot;
  Offset _center = Offset.zero;
  double _progress = 0;
  Ticker? _ticker;

  bool get revealing => _snapshot != null;
  ui.Image? get snapshot => _snapshot;
  Offset get center => _center;
  double get progress => _progress;

  /// 在 [center]（全局坐标）触发主题切换：截取旧帧，[applyTheme] 切换
  /// 底层主题，然后旧帧快照上开圆孔揭示新主题。
  Future<void> reveal({
    required Offset center,
    required VoidCallback applyTheme,
    required double pixelRatio,
    required bool reducedMotion,
  }) async {
    if (reducedMotion) {
      applyTheme();
      return;
    }
    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) {
      applyTheme();
      return;
    }
    final ui.Image image;
    try {
      image = await boundary.toImage(pixelRatio: pixelRatio);
    } catch (_) {
      applyTheme();
      return;
    }
    applyTheme();
    _snapshot = image;
    _center = center;
    _progress = 0;
    notifyListeners();
    _ticker?.dispose();
    _ticker = Ticker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final t =
        (elapsed.inMicroseconds / Motion.slow.inMicroseconds).clamp(0.0, 1.0);
    _progress = Motion.emphasized.transform(t);
    notifyListeners();
    if (t >= 1) _finish();
  }

  void _finish() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _snapshot?.dispose();
    _snapshot = null;
    _progress = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    _snapshot?.dispose();
    _snapshot = null;
    super.dispose();
  }
}

/// 包住 MaterialApp：内部负责旧帧截屏（RepaintBoundary）与扩散遮罩。
/// 遮罩只在揭示期间渲染，空闲时是 SizedBox.shrink——
/// 动画每帧只重建遮罩子树，不触碰 MaterialApp。
class ThemeRevealHost extends StatelessWidget {
  const ThemeRevealHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final ThemeRevealController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 本 Stack 位于 MaterialApp 之上，没有 Directionality 祖先；
    // 两个子节点都是全尺寸定位，对齐无实际意义，用非方向性 topLeft。
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      children: [
        RepaintBoundary(key: controller.boundaryKey, child: child),
        _RevealOverlay(controller: controller),
      ],
    );
  }
}

class _RevealOverlay extends StatelessWidget {
  const _RevealOverlay({required this.controller});

  final ThemeRevealController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        if (snapshot == null) return const SizedBox.shrink();
        final size = MediaQuery.sizeOf(context);
        return Positioned.fill(
          child: ClipPath(
            clipper: _InverseCircleClipper(
              center: controller.center,
              radius:
                  controller.progress * _maxRadius(controller.center, size),
            ),
            child: RawImage(image: snapshot, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}

/// 旧帧挖圆孔：孔半径随进度扩张，露出下层的新主题。
class _InverseCircleClipper extends CustomClipper<Path> {
  const _InverseCircleClipper({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) {
    final hole = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      hole,
    );
  }

  @override
  bool shouldReclip(_InverseCircleClipper oldClipper) =>
      oldClipper.center != center || oldClipper.radius != radius;
}

/// 圆孔扩张的最大半径：从触发点到屏幕最远角的距离。
double _maxRadius(Offset center, Size size) {
  double distanceTo(Offset corner) => (corner - center).distance;
  return [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
  ].map(distanceTo).reduce((a, b) => a > b ? a : b);
}
