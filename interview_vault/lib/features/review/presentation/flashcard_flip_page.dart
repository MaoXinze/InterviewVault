import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../data/database/app_database.dart';

/// 翻卡复习模式（PRD 2.7，MVP 简单复习列表；间隔重复 P1）。
///
/// 入口：回顾页「开始回顾」，携带当前筛选后的卡片（go_router extra）。
/// 正面 = 问题；点击翻面 = 我的回答 + AI 参考；「已复习」记一次复习并推进，
/// 「跳过」直接推进不计复习。最后一张后进入完成页。
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

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
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

  /// 已复习：记一次复习 + 推进（P1 间隔重复的基础计数）
  Future<void> _markReviewedAndNext() async {
    if (_finished) return;
    final card = _cards[_index];
    if (!_flipped) await _toggleFlip();
    await ref.read(appDatabaseProvider).flashcardsDao.markReviewed(card.id);
    if (mounted) {
      setState(() {
        _reviewedNow++;
        _index++;
        _flipped = false;
      });
      _flipController.value = 0;
    }
  }

  void _skip() {
    if (_finished) return;
    setState(() {
      _index++;
      _flipped = false;
    });
    _flipController.value = 0;
  }

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
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: GestureDetector(
                      key: Key('flip_card_${_cards[_index].id}'),
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
                                ? _FrontCard(card: _cards[_index])
                                : Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..rotateY(math.pi),
                                    child: _BackCard(card: _cards[_index]),
                                  ),
                          );
                        },
                      ),
                    ),
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
                            onPressed: _skip,
                            child: const Text('跳过'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            key: const Key('btn_reviewed_next'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.gold,
                              foregroundColor: AppTheme.onGold,
                            ),
                            onPressed: _markReviewedAndNext,
                            icon: const Icon(Icons.check),
                            label: Text(
                                _index == _cards.length - 1 ? '已复习，完成' : '已复习，下一张'),
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

  Widget _buildFinish(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Column(
        key: const Key('flip_finish'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.style, color: AppTheme.gold, size: 56),
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
  const _FrontCard({required this.card});

  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    final tags = decodeCardTags(card.tags);
    return _CardShell(
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
          SelectableText(
            card.question,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            '点击翻面看回答',
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
  const _CardShell({required this.child});

  final Widget child;

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
      child: child,
    );
  }
}
