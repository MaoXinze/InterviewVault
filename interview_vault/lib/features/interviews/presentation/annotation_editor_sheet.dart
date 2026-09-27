import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../data/database/app_database.dart';
import '../annotation_tags.dart';

/// 标注编辑弹层（PRD 2.5）：选标签（5 系统标签 + 自定义）+ 复盘笔记。
///
/// - 已有标注传入 [existing]：可换标签、改笔记或删除
/// - 长按标签 chip 可删除标签（系统标签拦截提示，自定义标签确认后删除，
///   已有标注保留 customTagName 文字不受影响）
/// - 保存新标注后，面试状态 transcribed → annotated（首次标注即视为已标注）
Future<void> showAnnotationEditorSheet(
  BuildContext context, {
  required String interviewId,
  required String segmentId,
  Annotation? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: AnnotationEditorSheet(
        interviewId: interviewId,
        segmentId: segmentId,
        existing: existing,
      ),
    ),
  );
}

class AnnotationEditorSheet extends ConsumerStatefulWidget {
  const AnnotationEditorSheet({
    super.key,
    required this.interviewId,
    required this.segmentId,
    this.existing,
  });

  final String interviewId;
  final String segmentId;
  final Annotation? existing;

  @override
  ConsumerState<AnnotationEditorSheet> createState() =>
      _AnnotationEditorSheetState();
}

class _AnnotationEditorSheetState extends ConsumerState<AnnotationEditorSheet> {
  String? _selectedKey;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _selectedKey = existing == null ? null : annotationFilterKey(existing);
    _noteController = TextEditingController(text: existing?.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  AppDatabase get _db => ref.read(appDatabaseProvider);

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsStreamProvider).value ?? const <Tag>[];
    final customTags = tags.where((t) => !t.isSystem).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          key: const Key('annotation_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sell_outlined, color: AppTheme.gold, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.existing == null ? '添加标注' : '编辑标注',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in systemTagOrder)
                  TagChip(
                    key: Key('tag_chip_$key'),
                    label: systemTagLabel(key),
                    filterKey: key,
                    selected: _selectedKey == key,
                    onTap: () => setState(() => _selectedKey = key),
                    onLongPress: () => _deleteTag('tag-$key', key),
                  ),
                for (final tag in customTags)
                  TagChip(
                    key: Key('tag_chip_custom:${tag.name}'),
                    label: tag.name,
                    filterKey: 'custom:${tag.name}',
                    selected: _selectedKey == 'custom:${tag.name}',
                    onTap: () =>
                        setState(() => _selectedKey = 'custom:${tag.name}'),
                    onLongPress: () => _deleteTag(tag.id, tag.name),
                  ),
                ActionChip(
                  key: const Key('btn_new_tag'),
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('新建标签'),
                  onPressed: _createTag,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('annotation_note_field'),
              controller: _noteController,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: '复盘笔记（选填）：这题答得怎么样？该怎么改进？',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.existing != null)
                  TextButton(
                    key: const Key('btn_annotation_delete'),
                    onPressed: _deleteAnnotation,
                    child: const Text('删除'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                if (_selectedKey == 'question')
                  FilledButton.tonal(
                    key: const Key('btn_save_as_card'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.gold.withValues(alpha: 0.16),
                      foregroundColor: AppTheme.goldDeep,
                    ),
                    onPressed: () => _save(createCard: true),
                    child: const Text('存为卡片'),
                  ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('btn_annotation_save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: AppTheme.onGold,
                  ),
                  onPressed: _selectedKey == null ? null : _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save({bool createCard = false}) async {
    final key = _selectedKey;
    if (key == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final isCustom = key.startsWith('custom:');
    final customName = isCustom ? key.substring('custom:'.length) : null;
    final note = _noteController.text.trim();
    final companion = AnnotationsCompanion(
      tag: Value(isCustom ? 'custom' : key),
      customTagName: Value(customName),
      note: Value(note.isEmpty ? null : note),
    );

    final existing = widget.existing;
    String? annotationId;
    if (existing == null) {
      annotationId = 'an-${DateTime.now().microsecondsSinceEpoch}';
      await _db.annotationsDao.insertOne(
        AnnotationsCompanion.insert(
          id: annotationId,
          interviewId: widget.interviewId,
          segmentId: Value(widget.segmentId),
          tag: isCustom ? 'custom' : key,
          customTagName: Value(customName),
          note: Value(note.isEmpty ? null : note),
        ),
      );
      // 首次标注即视为已标注（状态只进不退）
      final interview = await _db.interviewsDao.getById(widget.interviewId);
      if (interview?.status == 'transcribed') {
        await _db.interviewsDao.updateOne(
          widget.interviewId,
          const InterviewsCompanion(status: Value('annotated')),
        );
      }
    } else {
      annotationId = existing.id;
      await _db.annotationsDao.updateOne(existing.id, companion);
    }

    // PRD 2.7：从标注中提取问题卡片（幂等，重复生成更新原卡）
    Flashcard? card;
    if (createCard) {
      final saved = await _db.annotationsDao.getById(annotationId);
      if (saved != null) {
        try {
          card = await ref
              .read(flashcardServiceProvider)
              .createOrUpdateFromAnnotation(saved);
        } on Exception catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('生成卡片失败：$e')));
        }
      }
    }

    if (mounted) Navigator.of(context).pop();
    if (card != null) {
      // 已捕获的 app 级 messenger/router 在弹层卸载后仍可用
      messenger.showSnackBar(SnackBar(
        content: const Text('已生成问题卡片'),
        action: SnackBarAction(
          label: '查看',
          onPressed: () => appRouter.push('/cards/${card!.id}'),
        ),
      ));
    }
  }

  Future<void> _deleteAnnotation() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条标注？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('btn_confirm_delete_annotation'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.annotationsDao.deleteOne(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _createTag() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          key: const Key('new_tag_field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '标签名，如：系统设计',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('btn_new_tag_save'),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final messenger = ScaffoldMessenger.of(dialogContext);
              try {
                await _db.tagsDao.insertOne(
                  TagsCompanion.insert(id: 'tag-custom-$name', name: name),
                );
              } on Exception {
                messenger.showSnackBar(
                  const SnackBar(content: Text('标签已存在，换个名字试试')),
                );
                return;
              }
              if (mounted) setState(() => _selectedKey = 'custom:$name');
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  /// 长按标签删除：系统标签直接提示不可删；自定义标签确认后删除
  /// （删除动作仍以 DAO 的系统标签保护为准，此处只是提前免掉确认框）
  Future<void> _deleteTag(String tagId, String label) async {
    final messenger = ScaffoldMessenger.of(context);
    final tag = await _db.tagsDao.getById(tagId);
    if (tag == null) return;
    if (tag.isSystem) {
      messenger.showSnackBar(
        SnackBar(content: Text('系统标签「${tag.name}」不可删除')),
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除标签「$label」？'),
        content: const Text('已有标注会保留标签文字，不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('btn_confirm_delete_tag'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.tagsDao.deleteOne(tagId);
    } on SystemTagDeletionError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
