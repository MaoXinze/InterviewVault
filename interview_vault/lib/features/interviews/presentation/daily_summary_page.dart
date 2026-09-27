import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../data/database/app_database.dart';

/// 按日汇总页（PRD 2.8）：所有面试/录音按日分组的摘要视图，
/// 每日显示场数与累计时长，面试行点进详情。
class DailySummaryPage extends ConsumerWidget {
  const DailySummaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interviews = ref.watch(interviewsStreamProvider).value;

    return Scaffold(
      key: const Key('page_daily'),
      appBar: AppBar(title: const Text('按日汇总')),
      body: interviews == null
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context, interviews),
    );
  }

  Widget _buildBody(BuildContext context, List<Interview> interviews) {
    if (interviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('暂无面试记录', style: Theme.of(context).textTheme.titleMedium),
            const Text('录一场面试或导入音频，按日回看节奏'),
          ],
        ),
      );
    }

    // 按面试日期分组（无日期归入"未记录日期"殿后），组按日期倒序
    final groups = <String, List<Interview>>{};
    for (final interview in interviews) {
      final date = interview.interviewDate;
      final key = date == null || date.length < 10 ? '未记录日期' : date.substring(0, 10);
      groups.putIfAbsent(key, () => []).add(interview);
    }
    final days = groups.keys.toList()
      ..sort((a, b) {
        if (a == '未记录日期') return 1;
        if (b == '未记录日期') return -1;
        return b.compareTo(a);
      });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final day in days)
          _DaySection(
            day: day,
            interviews: groups[day]!,
          ),
      ],
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.interviews});

  final String day;
  final List<Interview> interviews;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = interviews.fold<int>(
      0,
      (n, i) => n + (i.durationSeconds ?? 0),
    );
    final summary = '${interviews.length} 场 · ${formatClock(Duration(seconds: totalSeconds))}';

    return Card(
      key: Key('daily_day_$day'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      day,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    summary,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            for (final interview in interviews)
              ListTile(
                title: Text([
                  interview.company ?? '未填公司',
                  interview.position ?? '未填岗位',
                ].join(' · ')),
                subtitle: Text(
                  interview.round?.isNotEmpty == true
                      ? interview.round!
                      : _statusLabel(interview.status),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/interviews/${interview.id}'),
              ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
      'draft' => '草稿',
      'transcribed' => '已转写',
      'annotated' => '已标注',
      'summarized' => '已总结',
      _ => status,
    };
