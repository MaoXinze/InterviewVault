import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/motion.dart';
import '../../../data/database/app_database.dart';

/// 回顾 Tab：问题卡片库 + 标签筛选（模式⑩ Expanding Tag Selection）。
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  final Set<String> _selectedTags = {};

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(flashcardsStreamProvider).value ?? [];
    final tags = ref.watch(tagsStreamProvider).value ?? const <Tag>[];
    final filtered = _selectedTags.isEmpty
        ? cards
        : cards
            .where(
              (c) =>
                  decodeCardTags(c.tags).any(_selectedTags.contains),
            )
            .toList();

    return Scaffold(
      key: const Key('page_review'),
      appBar: AppBar(title: const Text('回顾')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      cards.isEmpty ? '暂无卡片，先去积累问题吧' : '翻卡模式将在 W3 提供',
                    ),
                  ),
                ),
                icon: const Icon(Icons.style),
                label: const Text('开始回顾'),
              ),
            ),
          ),
          // 标签筛选：选中时弹性舒张
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _TagChip(
                  label: '全部',
                  active: _selectedTags.isEmpty,
                  onTap: () => setState(() => _selectedTags.clear()),
                ),
                for (final tag in tags)
                  _TagChip(
                    label: tag.name,
                    active: _selectedTags.contains(tag.name),
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
                      _selectedTags.isEmpty ? '还没有问题卡片，标注面试录音后会自动生成' : '该标签下还没有卡片',
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
                            title: Text(card.question),
                            subtitle: cardTags.isEmpty
                                ? null
                                : Text(cardTags.join(' · ')),
                            trailing: card.reviewCount > 0
                                ? Text(
                                    '已复习 ${card.reviewCount} 次',
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  )
                                : null,
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

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

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
          child: Text(
            label,
            style: TextStyle(
              color: active
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
