import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/motion.dart';
import '../../../data/database/app_database.dart';
import 'flashcard_flip_page.dart';

/// 回顾 Tab：问题卡片库 + 标签筛选（模式⑩）。
///
/// 空库时展示设计过的空状态（卡片堆叠隐喻 + 流程引导），
/// 筛选 chips 与 CTA 只在有数据后出现——"全部"绝不孤悬。
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  final Set<String> _selectedTags = {};

  /// 语义色小圆点：性格与信息量兼得（与系统标签一一对应）
  Color? _tagDotColor(String name) => switch (name) {
        '问题' => const Color(0xFF5B8DEF),
        '回答' => const Color(0xFF3D9B6F),
        '亮点' => AppTheme.gold,
        '失误' => const Color(0xFFE4574C),
        '待改进' => const Color(0xFFE8873B),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(flashcardsStreamProvider).value ?? [];
    final tags = ref.watch(tagsStreamProvider).value ?? const <Tag>[];
    final filtered = _selectedTags.isEmpty
        ? cards
        : cards
            .where(
              (c) => decodeCardTags(c.tags).any(_selectedTags.contains),
            )
            .toList();

    return Scaffold(
      key: const Key('page_review'),
      appBar: AppBar(title: const Text('回顾')),
      body: cards.isEmpty
          ? const _EmptyReview()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      // 硬边按压：鎏金 CTA 的签名质感
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: AppTheme.goldEdge,
                            offset: Offset(0, 3),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.gold,
                          foregroundColor: AppTheme.onGold,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          // 当前筛选下的卡片进翻卡；筛选空态给提示
                          if (filtered.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('当前筛选下没有卡片')),
                            );
                            return;
                          }
                          FlashcardFlipPage.push(context, filtered);
                        },
                        icon: const Icon(Icons.style),
                        label: const Text('开始回顾'),
                      ),
                    ),
                  ),
                ),
                // 标签筛选：有标签可筛时才出现（"全部"只和兄弟们一起登场）
                if (tags.length > 1)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      children: [
                        _TagChip(
                          label: '全部',
                          active: _selectedTags.isEmpty,
                          onTap: () =>
                              setState(() => _selectedTags.clear()),
                        ),
                        for (final tag in tags)
                          _TagChip(
                            label: tag.name,
                            active: _selectedTags.contains(tag.name),
                            dot: _tagDotColor(tag.name),
                            onTap: () => setState(() {
                              _selectedTags.contains(tag.name)
                                  ? _selectedTags.remove(tag.name)
                                  : _selectedTags.add(tag.name);
                            }),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            _selectedTags.isEmpty
                                ? '还没有匹配的卡片'
                                : '该标签下还没有卡片',
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final card = filtered[index];
                            final cardTags = decodeCardTags(card.tags);
                            return StaggeredItem(
                              index: index,
                              child: Card(
                                child: ListTile(
                                  key: Key('review_card_${card.id}'),
                                  title: Text(card.question),
                                  subtitle: cardTags.isEmpty
                                      ? null
                                      : Text(cardTags.join(' · ')),
                                  trailing: card.reviewCount > 0
                                      ? Text(
                                          '已复习 ${card.reviewCount} 次',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        )
                                      : null,
                                  onTap: () =>
                                      context.push('/cards/${card.id}'),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// 空库空状态：卡片堆叠视觉（与首页 hero 呼应）+ 流程引导。
class _EmptyReview extends StatelessWidget {
  const _EmptyReview();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 三张错位旋转的卡片，最前面一张带金色卡片图标
          SizedBox(
            width: 190,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: -0.14,
                  child: _emptyCard(
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  ),
                ),
                Transform.rotate(
                  angle: 0.1,
                  child: _emptyCard(
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                  ),
                ),
                Container(
                  width: 120,
                  height: 82,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Icon(
                    Icons.style_outlined,
                    color: AppTheme.gold,
                    size: 34,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '题库还是空的',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '录一场面试 → 标注问题 → 自动生成卡片',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 28),
          // 引导动作：指向底栏的 ⏺
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '点击下方',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.fiber_manual_record,
                  color: AppTheme.gold,
                  size: 18,
                ),
              ),
              Text(
                '开始你的第一场面试',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_downward,
                color: colorScheme.onSurfaceVariant,
                size: 16,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(Color color) {
    return Container(
      width: 120,
      height: 82,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.dot,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  /// 语义色小圆点（可空：如"全部"）
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: Key('tag_chip_$label'),
      onTap: onTap,
      child: AnimatedScale(
        scale: active ? 1.06 : 1.0,
        duration: Motion.medium,
        curve: Motion.spring, // 选中时弹性舒张
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.emphasized,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? colorScheme.primary : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: active
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
