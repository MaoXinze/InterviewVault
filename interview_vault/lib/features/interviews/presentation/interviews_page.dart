import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// 面试 Tab：历史面试记录列表，支持按公司/岗位关键词即时过滤。
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
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('还没有面试记录'),
                        SizedBox(height: 4),
                        Text('点击底部 ⏺ 开始你的第一场'),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final interview = filtered[index];
                      return Card(
                        child: ListTile(
                          title: Text(interview.company ?? '未填公司'),
                          subtitle: Text([
                            interview.position ?? '未填岗位',
                            interview.round ?? '',
                            interview.interviewDate ?? '',
                          ].where((s) => s.isNotEmpty).join(' · ')),
                          trailing: _StatusChip(status: interview.status),
                          onTap: () => ScaffoldMessenger.of(context)
                              .showSnackBar(
                                const SnackBar(
                                  content: Text('面试详情页将在 W2 提供'),
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
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final labels = {
      'draft': '草稿',
      'transcribed': '已转写',
      'annotated': '已标注',
      'summarized': '已总结',
    };
    return Text(labels[status] ?? status,
        style: Theme.of(context).textTheme.labelSmall);
  }
}
