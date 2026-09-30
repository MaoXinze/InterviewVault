import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/brand_icon.dart';
import '../../../core/widgets/motion.dart';
import '../../mock/presentation/mock_setup_page.dart';

/// 首页：时间问候 + 快捷入口 + 待回顾 hero（卡片堆叠 + 数字滚动）+ 最近面试。
/// 人格：清晨·阳光——问候语是亲近感的来源，配色性格在主题层统一。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardCount = ref.watch(flashcardCountProvider).value ?? 0;
    final interviews = ref.watch(interviewsStreamProvider).value ?? [];
    final now = DateTime.now();

    return Scaffold(
      key: const Key('page_home'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          children: [
            _GreetingHeader(now: now),
            const SizedBox(height: 20),
            StaggeredItem(
              index: 0,
              child: Row(
                children: [
                  _QuickAction(
                    icon: 'qa_mic',
                    label: '新录音',
                    onTap: () => context.push('/record'),
                  ),
                  const SizedBox(width: 12),
                  _QuickAction(
                    icon: 'qa_import',
                    label: '导入音频',
                    onTap: () => context.push('/import'),
                  ),
                  const SizedBox(width: 12),
                  _QuickAction(
                    icon: 'qa_mock',
                    label: '模拟面试',
                    onTap: () =>
                        MockSetupPage.enterMockInterview(context, ref),
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
                  subtitle: const Text('按日回看所有面试与录音的节奏'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/daily'),
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
      ),
    );
  }
}

/// 时间问候头：产品的"清晨"人格从这里开始。
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.now});

  final DateTime now;

  (String, String) get _greeting {
    final hour = now.hour;
    if (hour >= 5 && hour < 11) return ('早上好 ☀', '新的一天，从复盘一道题开始');
    if (hour >= 11 && hour < 13) return ('中午好 🌤', '午休刷两道题，稳住手感');
    if (hour >= 13 && hour < 18) return ('下午好 🌤', '把上午的问题趁热记下来');
    return ('晚上好 🌙', '睡前复盘，明天更稳');
  }

  String get _dateLabel {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月${now.day}日 · 周${weekdays[now.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = _greeting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(_dateLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.gold
                          : AppTheme.goldDeep,
                      fontWeight: FontWeight.w600,
                    )),
            const SizedBox(width: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 待回顾 hero：两层"卡背"堆叠 + 渐变主卡（绿→晨光琥珀）+ 数字滚动。
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
              borderRadius: BorderRadius.circular(24),
              // 墨绿金库块：两种模式下同一块"库"，金字点睛
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E3A2E), Color(0xFF12241C)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                                  color: AppTheme.gold,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '道题待回顾',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '把面试里的问题变成你的资产',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
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

  /// 品牌线稿图标资产名（assets/icons/）
  final String icon;
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
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  BrandIcon(icon, color: colorScheme.primary, size: 28),
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
