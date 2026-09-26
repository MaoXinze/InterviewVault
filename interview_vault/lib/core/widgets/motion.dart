import 'dart:async';

import 'package:flutter/material.dart';

import '../motion.dart';

/// 按压缩放：按下轻微下沉 0.98，松开回弹（Things 3 式手感）。
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: Motion.fast,
      curve: Motion.emphasized,
      child: widget.child,
    );
    if (!widget.enabled || prefersReducedMotion(context)) {
      return GestureDetector(onTap: widget.onTap, child: content);
    }
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: content,
    );
  }
}

/// 错落浮现：列表项按序淡入上移（间隔 50ms，封顶 8 档）。
class StaggeredItem extends StatefulWidget {
  const StaggeredItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<StaggeredItem> {
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.index > 7) {
      _shown = true;
      return;
    }
    _timer = Timer(Motion.staggerDelay(widget.index), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = prefersReducedMotion(context);
    final shown = reduced || _shown;
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: reduced ? Duration.zero : Motion.medium,
      curve: Motion.emphasized,
      child: AnimatedSlide(
        offset: shown ? Offset.zero : const Offset(0, 0.06),
        duration: reduced ? Duration.zero : Motion.medium,
        curve: Motion.emphasized,
        child: widget.child,
      ),
    );
  }
}

/// 数字滚动：数值变化时从旧值滚到新值（Duolingo 式计数）。
class CountUpText extends StatelessWidget {
  const CountUpText(this.value, {super.key, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: Motion.slow,
      curve: Motion.emphasized,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// 文本展开：高度按内容收放，箭头旋转 180°（模式⑤ Animated Text Disclosure）。
class DisclosureTile extends StatefulWidget {
  const DisclosureTile({
    super.key,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<DisclosureTile> createState() => _DisclosureTileState();
}

class _DisclosureTileState extends State<DisclosureTile> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final reduced = prefersReducedMotion(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: reduced ? Duration.zero : Motion.medium,
                  curve: Motion.emphasized,
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: _expanded ? 1 : 0,
            duration: reduced ? Duration.zero : Motion.medium,
            curve: Motion.emphasized,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
        ),
      ],
    );
  }
}
