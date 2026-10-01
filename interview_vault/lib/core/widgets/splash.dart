import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import 'brand_icon.dart';

/// 开屏：logo 弹入 + 名字浮现 + 整体淡出，播完经 [SplashOverlay.onDone]
/// 由宿主从树上移除（叠在正常界面之上，不参与路由）。
///
/// 品牌瞬间但要短（常规 1.6s）；「减弱动态效果」时整屏跳过。
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) widget.onDone();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedNow = prefersReducedMotion(context);
    _controller.duration = const Duration(milliseconds: 1600);
    if (reducedNow) {
      // 减弱动态：装饰性开屏直达终态——整屏跳过（首页本就同色同层，无跳变）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone();
      });
      return;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gold = isDark ? AppTheme.gold : AppTheme.goldDeep;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    // 常规路径：logo 0-22% 弹入，标题 20-38% 浮现，80-100% 整体淡出
    // （减弱动态在 didChangeDependencies 已整屏跳过，不会走到这里）
    final Animation<double> overall = _seq([
      (1, 1, null, 80),
      (1, 0, Motion.emphasized, 20),
    ]);
    final Animation<double> logoOpacity = _seq([
      (0, 1, Motion.emphasized, 15),
      (1, 1, null, 85),
    ]);
    final Animation<double> logoScale = _seq([
      (0.72, 1, Motion.spring, 22),
      (1, 1, null, 78),
    ]);
    final Animation<double> titleOpacity = _seq([
      (0, 0, null, 20),
      (0, 1, Motion.emphasized, 18),
      (1, 1, null, 62),
    ]);

    return ColoredBox(
      color: bg,
      child: FadeTransition(
        opacity: overall,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: logoScale,
                child: FadeTransition(
                  opacity: logoOpacity,
                  child:
                      BrandIcon('logo_mark', size: 92, color: gold),
                ),
              ),
              const SizedBox(height: 14),
              FadeTransition(
                opacity: titleOpacity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '问渠',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                            color: gold,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 6,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '把每一次面试，炼成你的资产',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 常规路径的 TweenSequence 便捷构造：[(begin, end, curve, weight)]。
  Animation<double> _seq(List<(double, double, Curve?, int)> items) {
    return TweenSequence<double>([
      for (final (begin, end, curve, weight) in items)
        TweenSequenceItem(
          tween: curve == null
              ? Tween<double>(begin: begin, end: end)
              : Tween<double>(begin: begin, end: end)
                  .chain(CurveTween(curve: curve)),
          weight: weight.toDouble(),
        ),
    ]).animate(_controller);
  }
}
