import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../data/database/app_database.dart';
import '../../interviews/annotation_tags.dart';
import '../flashcard_service.dart';

/// 问题卡片详情（PRD 2.7）：
/// 正面 = 问题文本；背面 = 我的回答 + 来源段标注/笔记 + AI 参考思路。
class FlashcardDetailPage extends ConsumerStatefulWidget {
  const FlashcardDetailPage({super.key, required this.cardId});

  final String cardId;

  @override
  ConsumerState<FlashcardDetailPage> createState() =>
      _FlashcardDetailPageState();
}

class _FlashcardDetailPageState extends ConsumerState<FlashcardDetailPage> {
  List<TranscriptSegment>? _segments;
  List<Annotation>? _annotations;
  bool _generating = false;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _loadSource();
  }

  Future<void> _loadSource() async {
    final db = ref.read(appDatabaseProvider);
    final card = await db.flashcardsDao.getById(widget.cardId);
    if (card == null || !mounted) return;
    _segments = await db.segmentsDao.getByInterview(card.interviewId);
    _annotations = await db.annotationsDao.getByInterview(card.interviewId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(cardByIdProvider(widget.cardId)).value;

    return Scaffold(
      key: const Key('page_card_detail'),
      appBar: AppBar(
        title: const Text('问题卡片'),
        actions: [
          IconButton(
            key: const Key('btn_delete_card'),
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteCard,
          ),
        ],
      ),
      body: card == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SourceCard(card: card),
                const SizedBox(height: 16),
                _buildQuestion(card),
                const SizedBox(height: 16),
                _buildAnswer(card),
                if (_pickedAnnotations(card).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildAnnotations(card),
                ],
                const SizedBox(height: 16),
                _buildAiReference(card),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  List<Annotation> _pickedAnnotations(Flashcard card) {
    final segments = _segments;
    final annotations = _annotations;
    if (segments == null || annotations == null) return const [];
    return annotationsForCard(card, segments, annotations);
  }

  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? actionLabel,
    VoidCallback? onAction,
    String? actionKey,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.gold),
        const SizedBox(width: 6),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        if (actionLabel != null)
          TextButton(
            key: Key(actionKey ?? ''),
            onPressed: onAction,
            child: Text(actionLabel),
          ),
      ],
    );
  }

  Widget _buildQuestion(Flashcard card) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              icon: Icons.help_outline,
              title: '问题',
              actionLabel: '编辑',
              actionKey: 'btn_edit_question',
              onAction: () => _editText(
                title: '编辑问题',
                initial: card.question,
                fieldKey: 'question_edit_field',
                saveKey: 'question_edit_save',
                maxLines: 3,
                save: (text) => _updateCard(
                  FlashcardsCompanion(question: Value(text)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              card.question,
              key: const Key('card_question'),
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswer(Flashcard card) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              icon: Icons.record_voice_over,
              title: '我的回答',
              actionLabel: '编辑',
              actionKey: 'btn_edit_answer',
              onAction: () => _editText(
                title: '编辑我的回答',
                initial: card.myAnswer ?? '',
                fieldKey: 'answer_edit_field',
                saveKey: 'answer_edit_save',
                maxLines: 8,
                save: (text) => _updateCard(
                  FlashcardsCompanion(myAnswer: Value(text)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (card.myAnswer == null || card.myAnswer!.isEmpty)
              Text(
                '未记录回答',
                key: const Key('card_answer_empty'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              )
            else
              SelectableText(
                card.myAnswer!,
                key: const Key('card_answer'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnotations(Flashcard card) {
    final picked = _pickedAnnotations(card);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(context, icon: Icons.sell_outlined, title: '标注'),
            const SizedBox(height: 8),
            for (final annotation in picked)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TagChip(
                      key: Key('card_annotation_${annotation.id}'),
                      label: annotationLabel(annotation),
                      filterKey: annotationFilterKey(annotation),
                      selected: false,
                      onTap: () {},
                    ),
                    if (annotation.note != null && annotation.note!.isNotEmpty)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Text(
                            annotation.note!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiReference(Flashcard card) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              icon: Icons.auto_awesome,
              title: 'AI 参考思路',
              actionLabel: _generating ? null : (card.aiReference == null ? '生成' : '重新生成'),
              actionKey: 'btn_gen_ai_reference',
              onAction: _generating ? null : () => _generateReference(card),
            ),
            const SizedBox(height: 8),
            if (_generating) ...[
              Text(
                _aiBuffer.isEmpty ? '正在生成…' : _aiBuffer,
                key: const Key('ai_reference_text'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 3),
            ] else ...[
              if (_aiError != null) ...[
                Text(
                  _aiError!,
                  key: const Key('ai_error_text'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              if (card.aiReference != null && card.aiReference!.isNotEmpty)
                SelectableText(
                  card.aiReference!,
                  key: const Key('ai_reference_text'),
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                Text(
                  '生成这道题的参考答案思路（AI 调用由你的账户扣费）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _aiBuffer = '';

  Future<void> _generateReference(Flashcard card) async {
    setState(() {
      _generating = true;
      _aiBuffer = '';
      _aiError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    StreamSubscription<CardAiEvent>? sub;
    sub = ref
        .read(flashcardServiceProvider)
        .generateAiReference(card)
        .listen((event) {
      if (!mounted) {
        sub?.cancel();
        return;
      }
      switch (event) {
        case CardAiDelta(:final text):
          setState(() => _aiBuffer += text);
        case CardAiDone():
          setState(() => _generating = false);
        case CardAiError(:final message):
          setState(() {
            _generating = false;
            _aiError = message;
          });
      }
    }, onError: (Object error) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _aiError = '生成失败：$error';
      });
      messenger.showSnackBar(SnackBar(content: Text('生成失败：$error')));
    });
  }

  Future<void> _updateCard(FlashcardsCompanion companion) async {
    await ref
        .read(appDatabaseProvider)
        .flashcardsDao
        .updateOne(widget.cardId, companion);
  }

  Future<void> _editText({
    required String title,
    required String initial,
    required String fieldKey,
    required String saveKey,
    required int maxLines,
    required Future<void> Function(String text) save,
  }) async {
    final controller = TextEditingController(text: initial);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: Key(fieldKey),
          controller: controller,
          maxLines: maxLines,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: Key(saveKey),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.gold,
              foregroundColor: AppTheme.onGold,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final text = controller.text.trim();
    if (text.isEmpty || text == initial) return;
    await save(text);
  }

  Future<void> _deleteCard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这张卡片？'),
        content: const Text('删除即真删，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('btn_confirm_delete_card'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(appDatabaseProvider).flashcardsDao.deleteOne(widget.cardId);
    if (mounted) Navigator.of(context).pop();
  }
}

/// 来源卡：来自哪场面试 + 时间锚点 + 回跳入口
class _SourceCard extends ConsumerWidget {
  const _SourceCard({required this.card});

  final Flashcard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interview = ref.watch(interviewByIdProvider(card.interviewId)).value;
    final colorScheme = Theme.of(context).colorScheme;
    final info = interview == null
        ? ''
        : [
            interview.company ?? '未填公司',
            interview.position ?? '',
            interview.interviewDate?.substring(0, 10) ?? '',
          ].where((s) => s.isNotEmpty).join(' · ');
    final anchor = [
      if (card.sourceStartTime != null)
        formatClock(Duration(milliseconds: (card.sourceStartTime! * 1000).round())),
      if (card.sourceEndTime != null)
        formatClock(Duration(milliseconds: (card.sourceEndTime! * 1000).round())),
    ].join(' - ');

    return Card(
      key: const Key('card_source'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.history_edu, color: AppTheme.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info,
                    key: const Key('card_source_info'),
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (anchor.isNotEmpty)
                    Text(
                      anchor,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                ],
              ),
            ),
            TextButton(
              key: const Key('btn_view_interview'),
              onPressed: () => context.push('/interviews/${card.interviewId}'),
              child: const Text('查看面试'),
            ),
          ],
        ),
      ),
    );
  }
}
