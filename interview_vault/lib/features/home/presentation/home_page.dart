import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';

/// 首页：快捷入口 + 待回顾数 + 今日汇总 + 最近面试。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardCount = ref.watch(flashcardCountProvider).value ?? 0;
    final interviews = ref.watch(interviewsStreamProvider).value ?? [];
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: const Key('page_home'),
      appBar: AppBar(title: const Text('InterviewVault')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
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
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(Icons.style, color: colorScheme.primary),
              title: Text('$cardCount 道题待回顾'),
              subtitle: const Text('把面试里的问题变成你的资产'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/review'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.today),
              title: const Text('今日汇总'),
              subtitle: const Text('当天面试/录音的摘要视图（W4 提供）'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
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
                    for (final interview in interviews.take(3))
                      ListTile(
                        title: Text(interview.company ?? '未填公司'),
                        subtitle: Text([
                          interview.position ?? '未填岗位',
                          interview.interviewDate ?? '',
                        ].where((s) => s.isNotEmpty).join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                ],
              ),
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
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
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
    );
  }
}
