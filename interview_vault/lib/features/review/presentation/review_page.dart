import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/database/export.dart';

/// 回顾 Tab：问题卡片库（导航命名铁律：回顾，不是"卡片库"）。
class ReviewPage extends ConsumerWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(flashcardsStreamProvider).value ?? [];

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
          Expanded(
            child: cards.isEmpty
                ? const Center(
                    child: Text('还没有问题卡片，标注面试录音后会自动生成'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: cards.length,
                    itemBuilder: (context, index) {
                      final card = cards[index];
                      final tags = decodeCardTags(card.tags);
                      return Card(
                        child: ListTile(
                          title: Text(card.question),
                          subtitle: tags.isEmpty
                              ? null
                              : Text(tags.join(' · ')),
                          trailing: card.reviewCount > 0
                              ? Text('已复习 ${card.reviewCount} 次',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall)
                              : null,
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
