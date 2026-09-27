import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../data/database/app_database.dart';
import '../../interviews/annotation_tags.dart';

/// 面试总结页（PRD 2.8 单次面试总结）：面试信息 + 标注统计 +
/// 问题卡片列表 + 录音概要；AppBar 导出 Markdown（格式快照锁定，
/// 见 markdown_export_service.dart）。
class InterviewSummaryPage extends ConsumerWidget {
  const InterviewSummaryPage({super.key, required this.interviewId});

  final String interviewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interview = ref.watch(interviewByIdProvider(interviewId)).value;
    final cards = ref.watch(flashcardsByInterviewProvider(interviewId)).value;
    final annotations =
        ref.watch(annotationsByInterviewProvider(interviewId)).value;
    final segments = ref.watch(segmentsByInterviewProvider(interviewId)).value;

    return Scaffold(
      key: const Key('page_interview_summary'),
      appBar: AppBar(
        title: const Text('面试总结'),
        actions: [
          IconButton(
            key: const Key('btn_export_markdown'),
            tooltip: '导出 Markdown',
            icon: const Icon(Icons.ios_share),
            onPressed: interview == null
                ? null
                : () => _export(context, ref),
          ),
        ],
      ),
      body: interview == null || cards == null || annotations == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _InfoCard(interview: interview),
                const SizedBox(height: 16),
                _StatsCard(annotations: annotations),
                const SizedBox(height: 16),
                _CardsSection(
                  interviewId: interviewId,
                  cards: cards,
                ),
                const SizedBox(height: 16),
                if (segments != null) _OverviewCard(
                  interview: interview,
                  segments: segments,
                ),
              ],
            ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result =
          await ref.read(markdownExportServiceProvider).exportInterview(
                interviewId,
              );
      await ref.read(markdownSharerProvider)(result.path);
      messenger.showSnackBar(
        SnackBar(content: Text('已导出 ${result.fileName}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }
}

String _statusLabel(String status) => switch (status) {
      'draft' => '草稿',
      'transcribed' => '已转写',
      'annotated' => '已标注',
      'summarized' => '已总结',
      _ => status,
    };

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.interview});

  final Interview interview;

  @override
  Widget build(BuildContext context) {
    final title = [
      interview.company ?? '未填公司',
      interview.position ?? '未填岗位',
      if (interview.round?.isNotEmpty == true) interview.round!,
    ].join(' · ');
    final meta = [
      if (interview.interviewDate?.isNotEmpty == true)
        interview.interviewDate!.substring(0, 10),
      if (interview.durationSeconds != null)
        '时长 ${formatClock(Duration(seconds: interview.durationSeconds!))}',
      _statusLabel(interview.status),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('面试信息'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  meta,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 卡片标签（存展示名）→ 筛选键（系统标签配色）
String filterKeyForTagDisplay(String display) {
  for (final entry in systemTagLabels.entries) {
    if (entry.value == display) return entry.key;
  }
  return 'custom:$display';
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.annotations});

  final List<Annotation> annotations;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final a in annotations) {
      final key = annotationFilterKey(a);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final keys = sortedFilterKeys(annotations);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('标注统计'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: keys.isEmpty
                ? Text(
                    '暂无标注',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final key in keys)
                        TagChip(
                          label: '${filterKeyLabel(key)} · ${counts[key]}',
                          filterKey: key,
                          selected: false,
                          onTap: () {},
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _CardsSection extends StatelessWidget {
  const _CardsSection({required this.interviewId, required this.cards});

  final String interviewId;
  final List<Flashcard> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeader('问题卡片')),
            Text(
              '${cards.length} 张',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        if (cards.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('还没有问题卡片',
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text(
                    '去逐字稿里把面试官的问题标注成「问题」标签，即可自动生成卡片',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          )
        else
          for (final card in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                key: Key('summary_card_${card.id}'),
                child: ListTile(
                  title: Text(
                    card.question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        card.myAnswer?.trim().isNotEmpty == true
                            ? card.myAnswer!
                            : '（未作答）',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (decodeCardTags(card.tags).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final tag in decodeCardTags(card.tags))
                                TagChip(
                                  label: tag,
                                  filterKey: filterKeyForTagDisplay(tag),
                                  selected: false,
                                  onTap: () {},
                                ),
                            ],
                          ),
                        ),
                      if (card.aiReference?.trim().isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 14,
                                color: AppTheme.gold,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '已生成 AI 参考',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: AppTheme.gold),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/cards/${card.id}'),
                ),
              ),
            ),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.interview, required this.segments});

  final Interview interview;
  final List<TranscriptSegment> segments;

  @override
  Widget build(BuildContext context) {
    final wordCount =
        segments.fold<int>(0, (n, s) => n + s.content.length);
    final rows = [
      ('音频', interview.audioFilePath?.isNotEmpty == true ? '有' : '无'),
      ('分段', '${segments.length} 段'),
      ('转写', '$wordCount 字'),
      (
        '时长',
        interview.durationSeconds == null
            ? '—'
            : formatClock(Duration(seconds: interview.durationSeconds!)),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('录音概要'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(
                            rows[i].$1,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                        Expanded(
                          child: Text(rows[i].$2,
                              style: Theme.of(context).textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
