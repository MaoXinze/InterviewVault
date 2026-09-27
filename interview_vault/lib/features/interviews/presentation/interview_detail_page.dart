import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/motion.dart';
import '../../../data/database/app_database.dart';
import '../../transcription/transcription_service.dart';
import '../../transcription/whisper_model_manager.dart';
import '../annotation_tags.dart';
import 'annotation_editor_sheet.dart';
import 'mini_player.dart';

/// 面试详情 = 逐字稿页（W2-M3 / W3-M1）：
/// draft → 转写卡片（模型状态/下载入口/开始转写/进度）
/// transcribed → 迷你播放条 + 分段列表（时间戳 + 编辑校正 + 说话人标记 + 标注）
class InterviewDetailPage extends ConsumerWidget {
  const InterviewDetailPage({super.key, required this.interviewId});

  final String interviewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interview = ref.watch(interviewByIdProvider(interviewId)).value;

    return Scaffold(
      key: const Key('page_interview_detail'),
      appBar: AppBar(title: Text(_title(interview))),
      body: interview == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeaderCard(interview: interview),
                if (interview.audioFilePath?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  MiniAudioPlayer(audioPath: interview.audioFilePath!),
                ],
                const SizedBox(height: 16),
                if (interview.status == 'draft')
                  _TranscribeCard(interview: interview)
                else
                  _TranscriptSection(
                    interviewId: interviewId,
                    audioFilePath: interview.audioFilePath,
                  ),
              ],
            ),
    );
  }

  String _title(Interview? interview) {
    if (interview == null) return '面试详情';
    return [interview.company ?? '未填公司', interview.position ?? '']
        .where((s) => s.isNotEmpty)
        .join(' · ');
  }
}

String _statusLabel(String status) => switch (status) {
      'draft' => '草稿',
      'transcribed' => '已转写',
      'annotated' => '已标注',
      'summarized' => '已总结',
      _ => status,
    };

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.interview});

  final Interview interview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final meta = [
      interview.round ?? '',
      interview.interviewDate?.substring(0, 10) ?? '',
      interview.durationSeconds != null
          ? formatClock(Duration(seconds: interview.durationSeconds!))
          : '',
    ].where((s) => s.isNotEmpty).join(' · ');
    final audioName =
        interview.audioFilePath?.split(Platform.pathSeparator).last;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel(interview.status),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppTheme.goldDeep,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const Spacer(),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
            if (audioName != null && audioName.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.graphic_eq,
                      size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      audioName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 转写卡片：draft 状态下的模型选择、下载入口与开始转写
class _TranscribeCard extends ConsumerStatefulWidget {
  const _TranscribeCard({required this.interview});

  final Interview interview;

  @override
  ConsumerState<_TranscribeCard> createState() => _TranscribeCardState();
}

class _TranscribeCardState extends ConsumerState<_TranscribeCard> {
  TranscribeModel _model = TranscribeModel.base;

  @override
  Widget build(BuildContext context) {
    final models = ref.watch(whisperModelGatewayProvider);
    final progressEvent =
        ref.watch(transcriptionProgressProvider(widget.interview.id)).value;
    final running = progressEvent?.phase == TranscriptionPhase.running;

    return Card(
      key: const Key('transcribe_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.graphic_eq, color: AppTheme.gold),
                const SizedBox(width: 8),
                Text(
                  '本地转写',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '录音不出设备',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<TranscribeModel>(
              key: const Key('model_selector'),
              segments: [
                for (final m in TranscribeModel.values)
                  ButtonSegment(
                    value: m,
                    label: Text(m == TranscribeModel.base ? 'Base' : 'Small'),
                  ),
              ],
              selected: {_model},
              onSelectionChanged: (s) => setState(() => _model = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              '${_model.description} · ${_model.sizeHint}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            _buildAction(context, models, running),
          ],
        ),
      ),
    );
  }

  /// 三态按钮：转写中（进度条）→ 模型未下载（先下载）→ 就绪（开始转写）
  Widget _buildAction(
    BuildContext context,
    WhisperModelGateway models,
    bool running,
  ) {
    if (running) {
      final percent =
          ref.watch(transcriptionProgressProvider(widget.interview.id)).value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            key: const Key('transcribe_progress'),
            value: (percent?.percent ?? 0) / 100,
          ),
          const SizedBox(height: 8),
          Text(
            '转写中 ${percent?.percent ?? 0}% · 可离开页面，完成后自动出现在这里',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    return FutureBuilder<bool>(
      future: models.isDownloaded(_model),
      builder: (context, snap) {
        final downloaded = snap.data ?? false;
        final downloading = models.isDownloading(_model);
        if (downloading) {
          final pct = models.percentOf(_model) ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                key: const Key('model_download_progress'),
                value: pct / 100,
              ),
              const SizedBox(height: 8),
              Text('模型下载中 $pct%', style: Theme.of(context).textTheme.bodySmall),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PressableScale(
              child: FilledButton.icon(
                key: Key(
                    downloaded ? 'btn_start_transcribe' : 'btn_download_model'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: AppTheme.onGold,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () => downloaded
                    ? _startTranscribe(context)
                    : _downloadModel(context),
                icon: Icon(downloaded ? Icons.graphic_eq : Icons.download),
                label: Text(
                    downloaded ? '开始转写' : '先下载模型（${_model.sizeHint}）'),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('btn_manage_models'),
                onPressed: () => context.push('/models'),
                child: const Text('管理转写模型'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadModel(BuildContext context) async {
    final models = ref.read(whisperModelGatewayProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await models.download(_model);
      if (mounted) setState(() {});
    } on WhisperDownloadException {
      messenger.showSnackBar(const SnackBar(
        content: Text('模型下载失败：主源与镜像均不可达，请检查网络后重试'),
      ));
    }
  }

  Future<void> _startTranscribe(BuildContext context) async {
    final runner = ref.read(transcriptionServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await runner.transcribeInterview(
        widget.interview.id,
        model: _model,
      );
    } on AlreadyTranscribingException {
      messenger.showSnackBar(
          const SnackBar(content: Text('这场面试正在转写中，请稍候')));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('转写失败：$e')));
    }
  }
}

/// 逐字稿：分段列表 + 文本编辑校正 + 说话人标记 + 标注/筛选/跳播放（PRD 2.4/2.5）
class _TranscriptSection extends ConsumerStatefulWidget {
  const _TranscriptSection({
    required this.interviewId,
    required this.audioFilePath,
  });

  final String interviewId;
  final String? audioFilePath;

  @override
  ConsumerState<_TranscriptSection> createState() => _TranscriptSectionState();
}

class _TranscriptSectionState extends ConsumerState<_TranscriptSection> {
  /// 当前筛选的标签键；null = 全部
  String? _filterKey;

  @override
  Widget build(BuildContext context) {
    final segments =
        ref.watch(segmentsByInterviewProvider(widget.interviewId)).value ?? [];
    final annotations =
        ref.watch(annotationsByInterviewProvider(widget.interviewId)).value ??
            const <Annotation>[];

    final bySegment = <String, List<Annotation>>{};
    for (final annotation in annotations) {
      final segmentId = annotation.segmentId;
      if (segmentId == null) continue;
      bySegment.putIfAbsent(segmentId, () => []).add(annotation);
    }
    final visibleSegments = _filterKey == null
        ? segments
        : segments
            .where((s) =>
                (bySegment[s.id] ?? const <Annotation>[])
                    .any((a) => annotationFilterKey(a) == _filterKey))
            .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.subject, color: AppTheme.gold),
                const SizedBox(width: 8),
                Text(
                  '逐字稿（${segments.length} 段）',
                  key: const Key('transcript_header'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '点分段改文字 · 点标签跳播放 · 长按标签编辑',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            if (annotations.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildFilterChips(annotations),
            ],
            const SizedBox(height: 4),
            if (segments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '暂无内容',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              )
            else if (visibleSegments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '该标签下暂无分段',
                    key: const Key('filter_empty_hint'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              )
            else
              for (final segment in visibleSegments)
                _SegmentTile(
                  key: Key('segment_${segment.id}'),
                  segment: segment,
                  annotations: bySegment[segment.id] ?? const <Annotation>[],
                  onEdit: () => _editSegment(segment),
                  onCycleSpeaker: () => _cycleSpeaker(segment),
                  onAnnotate: () => _annotate(segment),
                  onJumpToAnnotation: () => _jumpToSegment(segment),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 标注筛选条（PRD 2.5：快速定位所有"失误"/"待改进"）
  Widget _buildFilterChips(List<Annotation> annotations) {
    final keys = sortedFilterKeys(annotations);
    return Wrap(
      key: const Key('annotation_filters'),
      spacing: 8,
      runSpacing: 8,
      children: [
        TagChip(
          key: const Key('filter_chip_all'),
          label: '全部',
          filterKey: 'all',
          selected: _filterKey == null,
          onTap: () => setState(() => _filterKey = null),
        ),
        for (final key in keys)
          TagChip(
            key: Key('filter_chip_$key'),
            label: filterKeyLabel(key),
            filterKey: key,
            selected: _filterKey == key,
            onTap: () => setState(() => _filterKey = key),
          ),
      ],
    );
  }

  Future<void> _annotate(TranscriptSegment segment) {
    return showAnnotationEditorSheet(
      context,
      interviewId: widget.interviewId,
      segmentId: segment.id,
    );
  }

  /// 点击标注 chip：播放器跳转到分段起点并继续播放（PRD 2.5 标注跳转）
  Future<void> _jumpToSegment(TranscriptSegment segment) async {
    final path = widget.audioFilePath;
    if (path == null || path.isEmpty) return;
    final player = ref.read(audioPlaybackProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await player.open(path);
      await player.seekTo(
        Duration(milliseconds: (segment.startTime * 1000).round()),
      );
      if (!player.current.playing) await player.toggle();
    } on Exception {
      messenger.showSnackBar(const SnackBar(
        content: Text('音频无法播放：录音文件可能已被移动或删除'),
      ));
    }
  }

  Future<void> _editSegment(TranscriptSegment segment) async {
    final controller = TextEditingController(text: segment.content);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tsLabel(segment.startTime)),
        content: TextField(
          key: const Key('segment_edit_field'),
          controller: controller,
          maxLines: null,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '校正这段文字',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('segment_edit_save'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.gold,
              foregroundColor: AppTheme.onGold,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final text = controller.text.trim();
    if (text.isEmpty || text == segment.content) return;
    await ref.read(appDatabaseProvider).segmentsDao.updateOne(
          segment.id,
          TranscriptSegmentsCompanion(content: Value(text)),
        );
  }

  /// 未标记 → 面试官 → 我 → 未标记（P0 手动标记）
  Future<void> _cycleSpeaker(TranscriptSegment segment) async {
    const cycle = [null, 'interviewer', 'candidate'];
    final next = cycle[(cycle.indexOf(segment.speaker) + 1) % cycle.length];
    await ref.read(appDatabaseProvider).segmentsDao.updateOne(
          segment.id,
          TranscriptSegmentsCompanion(speaker: Value(next)),
        );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    super.key,
    required this.segment,
    required this.annotations,
    required this.onEdit,
    required this.onCycleSpeaker,
    required this.onAnnotate,
    required this.onJumpToAnnotation,
  });

  final TranscriptSegment segment;
  final List<Annotation> annotations;
  final VoidCallback onEdit;
  final VoidCallback onCycleSpeaker;
  final VoidCallback onAnnotate;
  final VoidCallback onJumpToAnnotation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      key: Key('segment_tap_${segment.id}'),
      onTap: onEdit,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    _tsLabel(segment.startTime),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
                Expanded(
                  child: Text(
                    segment.content,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: Key('btn_annotate_${segment.id}'),
                  icon: Icon(
                    Icons.sell_outlined,
                    size: 18,
                    color: annotations.isEmpty
                        ? colorScheme.onSurfaceVariant
                        : AppTheme.gold,
                  ),
                  tooltip: '添加标注',
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: onAnnotate,
                ),
                const SizedBox(width: 4),
                _SpeakerChip(
                  key: Key('speaker_chip_${segment.id}'),
                  speaker: segment.speaker,
                  onTap: onCycleSpeaker,
                ),
              ],
            ),
            if (annotations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 92, top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final annotation in annotations)
                      TagChip(
                        key: Key('annotation_chip_${annotation.id}'),
                        label: annotation.note == null
                            ? annotationLabel(annotation)
                            : '${annotationLabel(annotation)} · ✎',
                        filterKey: annotationFilterKey(annotation),
                        selected: false,
                        onTap: onJumpToAnnotation,
                        onLongPress: () => showAnnotationEditorSheet(
                          context,
                          interviewId: segment.interviewId,
                          segmentId: segment.id,
                          existing: annotation,
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
}

class _SpeakerChip extends StatelessWidget {
  const _SpeakerChip({super.key, required this.speaker, required this.onTap});

  final String? speaker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (speaker) {
      'interviewer' => ('面试官', AppTheme.gold),
      'candidate' => ('我', Theme.of(context).colorScheme.primary),
      _ => ('未标记', Theme.of(context).colorScheme.outlineVariant),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color == AppTheme.gold ? AppTheme.goldDeep : color),
        ),
      ),
    );
  }

}

String _tsLabel(double seconds) {
  final d = Duration(milliseconds: (seconds * 1000).round());
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
