import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/motion.dart';

/// 首页：快捷入口 + 待回顾 hero（卡片堆叠 + 数字滚动）+ 今日汇总 + 最近面试。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardCount = ref.watch(flashcardCountProvider).value ?? 0;
    final interviews = ref.watch(interviewsStreamProvider).value ?? [];

    return Scaffold(
      key: const Key('page_home'),
      appBar: AppBar(title: const Text('InterviewVault')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StaggeredItem(
            index: 0,
            child: Row(
              children: [
                _QuickAction(
                  icon: Icons.mic,
                  label: '新录音',
                  onTap: () => context.push('/record'),
                ),
                const SizedBox(width: 12),
                _QuickAction(
                  icon: Icons.upload_file,
                  label: '导入音频',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('音频导入将在 W2 提供')),
                  ),
                ),
                const SizedBox(width: 12),
                _QuickAction(
                  icon: Icons.psychology,
                  label: '模拟面试',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('模拟面试将在 W3 提供')),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          StaggeredItem(index: 1, child: _ReviewHero(count: cardCount)),
          const SizedBox(height: 16),
          StaggeredItem(
            index: 2,
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.today),
                title: const Text('今日汇总'),
                subtitle: const Text('当天面试/录音的摘要视图（W4 提供）'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          StaggeredItem(
            index: 3,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('最近面试',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    if (interviews.isEmpty)
                      const ListTile(
                        title: Text('暂无面试记录'),
                        subtitle: Text('录音→转写→卡片，从一场面试开始'),
                      )
                    else
                      for (final entry in interviews.take(3).toList().indexed)
                        StaggeredItem(
                          index: entry.$1 + 1,
                          child: ListTile(
                            title: Text(entry.$2.company ?? '未填公司'),
                            subtitle: Text([
                              entry.$2.position ?? '未填岗位',
                              entry.$2.interviewDate ?? '',
                            ].where((s) => s.isNotEmpty).join(' · ')),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 待回顾 hero：两层"卡背"堆叠 + 渐变主卡 + 数字滚动（辨识度担当）。
class _ReviewHero extends StatelessWidget {
  const _ReviewHero({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: () => context.go('/review'),
      child: Column(
        children: [
          FractionallySizedBox(
            widthFactor: 0.86,
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          FractionallySizedBox(
            widthFactor: 0.93,
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colorScheme.primary, colorScheme.tertiary],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          CountUpText(
                            count,
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(
                                  color: colorScheme.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '道题待回顾',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: colorScheme.onPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '把面试里的问题变成你的资产',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onPrimary
                                  .withValues(alpha: 0.85),
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.onPrimary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: PressableScale(
        child: Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(icon, color: colorScheme.primary, size: 28),
                  const SizedBox(height: 8),
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
