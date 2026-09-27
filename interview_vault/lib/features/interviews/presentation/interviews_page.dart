import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/arc_dismiss.dart';
import '../../../core/widgets/motion.dart';
import '../../../data/database/app_database.dart';

/// 面试 Tab：历史面试记录列表（按公司/岗位即时过滤）。
/// 搜索框只在有数据后出现——空列表时它只会让人困惑。
class InterviewsPage extends ConsumerStatefulWidget {
  const InterviewsPage({super.key});

  @override
  ConsumerState<InterviewsPage> createState() => _InterviewsPageState();
}

class _InterviewsPageState extends ConsumerState<InterviewsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final interviews = ref.watch(interviewsStreamProvider).value ?? [];
    final filtered = _query.isEmpty
        ? interviews
        : interviews
            .where(
              (i) =>
                  (i.company ?? '').contains(_query) ||
                  (i.position ?? '').contains(_query),
            )
            .toList();

    return Scaffold(
      key: const Key('page_interviews'),
      appBar: AppBar(title: const Text('面试')),
      body: Column(
        children: [
          if (interviews.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                key: const Key('field_search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索公司 / 岗位',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 错位卡片视觉（与回顾页空状态同一套设计词汇）
                        SizedBox(
                          width: 180,
                          height: 118,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.rotate(
                                angle: -0.12,
                                child: _ghostCard(context, 0.4),
                              ),
                              Transform.rotate(
                                angle: 0.09,
                                child: _ghostCard(context, 0.7),
                              ),
                              Container(
                                width: 112,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.work_outline,
                                  color: AppTheme.gold,
                                  size: 32,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '还没有面试记录',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '从一场录音开始，让它变成你的题库',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '点击下方',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: const Icon(
                                Icons.fiber_manual_record,
                                color: AppTheme.gold,
                                size: 18,
                              ),
                            ),
                            Text(
                              '录下第一场面试',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_downward,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              size: 16,
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final interview = filtered[index];
                      return StaggeredItem(
                        index: index,
                        child: ArcDismiss(
                          onDeleted: () => _deleteInterview(interview),
                          child: Builder(
                            builder: (context) => Card(
                              child: ListTile(
                                title: Text(interview.company ?? '未填公司'),
                                subtitle: Text([
                                  interview.position ?? '未填岗位',
                                  interview.round ?? '',
                                  interview.interviewDate ?? '',
                                  _statusLabel(interview.status),
                                ].where((s) => s.isNotEmpty).join(' · ')),
                                trailing: IconButton(
                                  key: Key('menu_${interview.id}'),
                                  icon: const Icon(Icons.more_vert),
                                  onPressed: () => ArcDismiss.maybeOf(context)
                                      ?.confirmAndDismiss(),
                                ),
                                onTap: () => context.push(
                                  '/interviews/${interview.id}',
                                ),
                              ),
                            ),
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

  Future<void> _deleteInterview(Interview interview) async {
    await ref.read(appDatabaseProvider).interviewsDao.deleteOne(interview.id);
    // 删除即真删（AGENTS 铁律 3）：行删除成功后同步清理音频文件
    await ref.read(audioFileCleanerProvider)(interview.audioFilePath);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已删除')));
  }

  String _statusLabel(String status) => switch (status) {
        'draft' => '草稿',
        'transcribed' => '已转写',
        'annotated' => '已标注',
        'summarized' => '已总结',
        _ => status,
      };

  Widget _ghostCard(BuildContext context, double opacity) {
    return Container(
      width: 112,
      height: 76,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
