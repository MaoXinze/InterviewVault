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
    final tags = decodeCardTags(card.tags);
    return _CardShell(
      watermark: const CardIllustration.question(opacity: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in tags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      tag,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.goldDeep,
                          ),
                    ),
                  ),
              ],
            ),
          const Spacer(),
          // 普通 Text 而非 SelectableText：SelectableText 的拖拽选择手势
          // 会在竞技场里抢走卡片堆的横滑；文本复制走详情页
          Text(
            card.question,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (!preview)
            Text(
              '点击翻面看回答 · 支持左右滑动',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
    return _CardShell(
      watermark: const CardIllustration.answer(opacity: 0.1),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            '我的回答',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            (card.myAnswer == null || card.myAnswer!.isEmpty)
                ? '未记录回答'
                : card.myAnswer!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (card.aiReference != null && card.aiReference!.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              'AI 参考思路',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppTheme.goldDeep,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(card.aiReference!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.watermark});

  final Widget child;

  /// 右上角鎏金线稿水印（场景插画，内容之下）
  final Widget? watermark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gold.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (watermark != null)
            Positioned(
              top: 0,
              right: 0,
              child: IgnorePointer(child: watermark!),
            ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
