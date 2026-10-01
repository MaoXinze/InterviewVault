import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../motion.dart';
import '../theme.dart';

/// 开屏（参考主流 App 的品牌瞬间：logo 弹入 → 字标扫金 shimmer →
/// 标语浮现 → 整体上滑淡出交棒给首页），播完经 [SplashOverlay.onDone]
/// 由宿主从树上移除（叠在正常界面之上，不参与路由）。
///
/// 品牌瞬间但要短（常规 2.0s）；「减弱动态效果」时整屏跳过。
/// logo 用立体版品牌资产（assets/icons/logo_mark.svg，自带渐变，不着色）。
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
    _controller.duration = const Duration(milliseconds: 2000);
    if (prefersReducedMotion(context)) {
      // 减弱动态：装饰性开屏直达终态——整屏跳过（首页本就同色同层）
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

  // —— 序列（权重 %）：logo 0-20 弹入；标题 22-36 浮现；扫金 30-56；
  // —— 标语 34-48；86-100 整体上滑 + 淡出（交棒给首页）
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wordBase = isDark ? AppTheme.gold : AppTheme.goldDeep;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    final logoScale = _seq([
      (0.66, 1, Motion.spring, 20),
      (1, 1, null, 66),
      (1, 0.94, Motion.emphasized, 14),
    ]);
    final logoOpacity = _seq([
      (0, 1, Motion.emphasized, 12),
      (1, 1, null, 74),
      (1, 0, Motion.emphasized, 14),
    ]);
    final titleOpacity = _seq([
      (0, 0, null, 22),
      (0, 1, Motion.emphasized, 14),
      (1, 1, null, 50),
      (1, 0, Motion.emphasized, 14),
    ]);
    final shimmer = _seq([
      (0, 0, null, 30),
      (0, 1, Motion.emphasized, 26),
      (1, 1, null, 30),
      (1, 1, null, 14),
    ]);
    final taglineOpacity = _seq([
      (0, 0, null, 34),
      (0, 1, Motion.emphasized, 14),
      (1, 1, null, 38),
      (1, 0, Motion.emphasized, 14),
    ]);
    final overall = _seq([
      (1, 1, null, 86),
      (1, 0, Motion.emphasized, 14),
    ]);
    final exitSlide = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: ConstantTween(Offset.zero),
        weight: 86,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Offset.zero, end: const Offset(0, -0.06))
            .chain(CurveTween(curve: Motion.emphasized)),
        weight: 14,
      ),
    ]).animate(_controller);

    return ColoredBox(
      color: bg,
      child: FadeTransition(
        opacity: overall,
        child: ClipRect(
          child: SlideTransition(
            position: exitSlide,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: logoScale,
                    child: FadeTransition(
                      opacity: logoOpacity,
                      child: SvgPicture.asset(
                        'assets/icons/logo_mark.svg',
                        width: 128,
                        height: 128,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FadeTransition(
                    opacity: titleOpacity,
                    child: ShimmerWordmark(
                      progress: shimmer,
                      base: wordBase,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: taglineOpacity,
                    child: Text(
                      '把每一次面试，炼成你的资产',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「问渠」字标：底色字 + 一道金色流光从左到右扫过（扫金 shimmer）。
class ShimmerWordmark extends StatelessWidget {
  const ShimmerWordmark({
    super.key,
    required this.progress,
    required this.base,
  });

  final Animation<double> progress;
  final Color base;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = Text(
      '问渠',
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: base,
            fontWeight: FontWeight.w800,
            letterSpacing: 8,
          ),
    );
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.value;
        final center = (t * 1.6 - 0.2).clamp(0.0, 1.0);
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              base,
              if (isDark) const Color(0xFFFFF3C4) else base,
              base,
            ],
            stops: [
              (center - 0.3).clamp(0.0, 1.0),
              center,
              (center + 0.3).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: text,
    );
  }
}
