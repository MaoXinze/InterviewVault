import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/illustration.dart';
import '../../../core/widgets/motion.dart';
import '../../../data/database/app_database.dart';
import 'swipe_deck.dart';

/// 翻卡复习模式（PRD 2.7，MVP 简单复习列表；间隔重复 P1）。
///
/// 入口：回顾页「开始回顾」，携带当前筛选后的卡片（go_router extra）。
/// 正面 = 问题；点击翻面 = 我的回答 + AI 参考。
/// 推进三种方式（等价）：「已复习」按钮 / 右滑（记一次复习）、「跳过」按钮 /
/// 左滑（不计复习）。最后一张后进入完成页。
class FlashcardFlipPage extends ConsumerStatefulWidget {
  const FlashcardFlipPage({super.key, required this.cards});

  final List<Flashcard> cards;

  static Future<void> push(BuildContext context, List<Flashcard> cards) =>
      context.push('/review/flip', extra: cards);

  @override
  ConsumerState<FlashcardFlipPage> createState() => _FlashcardFlipPageState();
}

class _FlashcardFlipPageState extends ConsumerState<FlashcardFlipPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipController;
  int _index = 0;
  bool _flipped = false;
  int _reviewedNow = 0;

  /// 推进互斥：飞出动画尾声误触按钮/连续提交不会跳卡
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: Motion.slow,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 减弱动态效果：翻面直达终态（保留状态变化，去掉装饰运动）
    _flipController.duration =
        prefersReducedMotion(context) ? Duration.zero : Motion.slow;
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  List<Flashcard> get _cards => widget.cards;
  bool get _finished => _index >= _cards.length;

  Future<void> _toggleFlip() async {
    if (_finished) return;
    if (_flipped) {
      await _flipController.reverse();
    } else {
      await _flipController.forward();
    }
    if (mounted) setState(() => _flipped = !_flipped);
  }

  /// 统一推进：已复习（记一次复习）或跳过（不记）。
  /// 按钮路径翻面后再标记（先看答案的完整流程）；横滑路径直接标记（明确手势）。
  Future<void> _advance({
    required bool reviewed,
    required bool viaSwipe,
  }) async {
    if (_finished || _advancing) return;
    _advancing = true;
    try {
      final card = _cards[_index];
      if (reviewed) {
        if (!viaSwipe && !_flipped) await _toggleFlip();
        await ref.read(appDatabaseProvider).flashcardsDao.markReviewed(card.id);
      }
      if (!mounted) return;
      setState(() {
        if (reviewed) _reviewedNow++;
        _index++;
        _flipped = false;
      });
      _flipController.value = 0;
    } finally {
      _advancing = false;
    }
  }

  /// 横滑提交回调（SwipeDeck 在飞出动画结束后调用，并等待本方法完成）
  Future<void> _onSwipeCommit(SwipeDirection direction) =>
      _advance(reviewed: direction == SwipeDirection.right, viaSwipe: true);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('page_flip'),
      appBar: AppBar(
        title: Text(_finished
            ? '复习完成'
            : '开始回顾 · ${_index + 1} / ${_cards.length}'),
      ),
      body: _finished
          ? _buildFinish(context, colorScheme)
          : Column(
              children: [
                Expanded(
                  child: SwipeDeck(
                    front: _buildFlipCard(_cards[_index]),
                    behind: _index + 1 < _cards.length
                        ? _FrontCard(card: _cards[_index + 1], preview: true)
                        : null,
                    onCommit: _onSwipeCommit,
                    stampBuilder: (progress) => _SwipeStamp(progress: progress),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('btn_skip_card'),
                            onPressed: () =>
                                _advance(reviewed: false, viaSwipe: false),
                            child: const Text('跳过'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: MagneticPress(
                            child: FilledButton.icon(
                              key: const Key('btn_reviewed_next'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.gold,
                                foregroundColor: AppTheme.onGold,
                              ),
                              onPressed: () =>
                                  _advance(reviewed: true, viaSwipe: false),
                              icon: const Icon(Icons.check),
                              label: Text(
                                  _index == _cards.length - 1 ? '已复习，完成' : '已复习，下一张'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFlipCard(Flashcard card) {
    return GestureDetector(
      key: Key('flip_card_${card.id}'),
      onTap: _toggleFlip,
      child: AnimatedBuilder(
        animation: _flipController,
        builder: (context, child) {
          final angle = _flipController.value * math.pi;
          final showFront = angle < math.pi / 2;
          // 外层恒转 angle；背面内容预转 π，翻到位时
          // π + π = 2π 归位，文字不呈镜像（只有翻卡页用 3D）
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle);
          return Transform(
            alignment: Alignment.center,
            transform: transform,
            child: showFront
                ? _FrontCard(card: card)
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..rotateY(math.pi),
                    child: _BackCard(card: card),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildFinish(BuildContext context, ColorScheme colorScheme) {
    final reduced = prefersReducedMotion(context);
    return Center(
      child: Column(
        key: const Key('flip_finish'),
        mainAxisSize: MainAxisSize.min,
        children: [
          // 奖牌插画：一次性弹性放大（一次性完成动效，非循环）
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.7, end: 1),
            duration: reduced ? Duration.zero : Motion.slow,
            curve: Motion.spring,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: child,
            ),
            child: const CardIllustration.done(size: 104),
          ),
          const SizedBox(height: 16),
          Text(
            '本轮复习完成',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '本次标记复习 $_reviewedNow 张 · 已复习 ${_cards.length} 张卡',
            key: const Key('flip_finish_summary'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('btn_flip_back'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.gold,
              foregroundColor: AppTheme.onGold,
            ),
            onPressed: () => context.pop(),
            child: const Text('返回回顾'),
          ),
        ],
      ),
    );
  }
}

class _FrontCard extends StatelessWidget {
  const _FrontCard({required this.card, this.preview = false});

  final Flashcard card;

  /// 卡片堆里的下一张预览：不显示操作提示（藏在当前卡后面）
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tags = decodeCardTags(card.tags);
    return _cardFace(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _FaceBadge(letter: '问'),
              const SizedBox(width: 10),
              Text(
                '问题',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
              ),
              const Spacer(),
              // 标签折叠展示：最多 2 个小点chip，多出聚合为 +n（Quizlet 式留白）
              ...[
                for (final tag in tags.take(2))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.gold.withValues(alpha: 0.45)
                            : AppTheme.goldDeep.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                            color: isDark ? AppTheme.gold : AppTheme.goldDeep,
                          ),
                    ),
                  ),
              ],
              if (tags.length > 2)
                Text(
                  '+${tags.length - 2}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
          Expanded(
            // Quizlet 式题面：大字居中，过长整体等比缩小（FittedBox）
            child: Center(
              child: LayoutBuilder(
                builder: (context, cons) => FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: cons.maxWidth,
                    child: Text(
                      card.question,
                      textAlign: TextAlign.center,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!preview)
            Row(
              children: [
                Icon(
                  Icons.swipe,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '左右滑动判定',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                const Icon(Icons.auto_awesome, size: 14, color: AppTheme.gold),
                const SizedBox(width: 4),
                Text(
                  '点击翻面',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BackCard extends StatelessWidget {
  const _BackCard({required this.card});

  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _cardFace(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _FaceBadge(letter: '答', green: true),
              const SizedBox(width: 10),
              Text(
                '参考',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Text(
                  '我的回答',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  (card.myAnswer == null || card.myAnswer!.isEmpty)
                      ? '未记录回答'
                      : card.myAnswer!,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.5),
                ),
                if (card.aiReference != null &&
                    card.aiReference!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  // AI 参考思路：金底面板（品牌签名块）
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(
                          alpha:
                              Theme.of(context).brightness == Brightness.dark
                                  ? 0.10
                                  : 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.gold.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CardIllustration.bulb(size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'AI 参考思路',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: AppTheme.goldDeep,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          card.aiReference!,
                          style:
                              Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '再次点击翻回正面',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
          ),
        ],
      ),
    );
  }
}

/// 「问」/「答」面别徽标：鎏金渐变圆角块（题面身份签名）
class _FaceBadge extends StatelessWidget {
  const _FaceBadge({required this.letter, this.green = false});

  final String letter;

  /// 绿底白字 = 背面（与正面金底深字形成翻面明暗语义）
  final bool green;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: green
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3D9B6F), Color(0xFF2F7D5F)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF6D98C), Color(0xFFD9A93A)],
              ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: green ? Colors.white : const Color(0xFF183A2C),
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Quizlet 式判定章：右滑「已掌握」/ 左滑「再看看」，
/// 随拖动深度淡入放大，跟随卡片倾斜。
class _SwipeStamp extends StatelessWidget {
  const _SwipeStamp({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = progress.abs();
    if (p < 0.06) return const SizedBox.shrink();
    final right = progress > 0;
    final color = right ? const Color(0xFF3D9B6F) : const Color(0xFFE8873B);
    final t = (p / 0.4).clamp(0.0, 1.0);
    return Center(
      child: Opacity(
        opacity: Curves.easeOut.transform(t),
        child: Transform.rotate(
          angle: right ? -0.16 : 0.16,
          child: Transform.scale(
            scale: 0.82 + 0.18 * Curves.easeOutBack.transform(t),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color, width: 3.5),
                color: Colors.white.withValues(alpha: 0.10),
              ),
              child: Text(
                right ? '已掌握' : '再看看',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  letterSpacing: 6,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡面基底（Quizlet 式留白：大圆角、细边、柔和落影、充足内边距）
Widget _cardFace(BuildContext context, {required Widget child}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: child,
  );
}
