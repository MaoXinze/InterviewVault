import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path_provider/path_provider.dart';

import '../../data/database/app_database.dart';
import '../../core/format.dart';
import '../interviews/annotation_tags.dart';
import '../flashcards/flashcard_service.dart';

/// Markdown 导出的单条结果。
class ExportedMarkdown {
  const ExportedMarkdown({required this.path, required this.fileName});

  final String path;
  final String fileName;
}

/// 标注标签在 Markdown 里的展示：系统标签固定 emoji + 展示名。
///
/// ⭐/⚠️ 来自 PRD 2.8 模板示例；其余标签为同风格补充，
/// 与标签行文案一并被快照测试锁定（改模板 = 破坏性变更）。
const markdownTagEmojis = <String, String>{
  'question': '❓',
  'answer': '💬',
  'highlight': '⭐',
  'mistake': '❌',
  'improvement': '⚠️',
};

String markdownTagDisplay(Annotation a) =>
    '${markdownTagEmojis[a.tag] ?? '🏷️'} ${annotationLabel(a)}';

/// 单场面试的 Markdown 复盘文稿（PRD 2.8 模板，快照测试锁定逐字符格式）。
///
/// 稳定性承诺（AGENTS 工程纪律 4）：
/// - 面试信息四行恒在，缺省值为空串；
/// - 每张卡片恒有 **问题**/**我的回答** 两行，未作答记（未作答）；
/// - **标注**/**复盘笔记**/**AI 参考** 仅在非空时输出——AI 参考是
///   PRD 2.7 卡片背面内容，模板的补充扩展行；
/// - 卡片按来源时间轴升序、无来源时间殿后。
String buildInterviewMarkdown({
  required Interview interview,
  required List<Flashcard> cards,
  required List<Annotation> annotations,
  required List<TranscriptSegment> segments,
}) {
  final date = interview.interviewDate;
  final datePart =
      date == null || date.isEmpty ? '' : (date.length >= 10 ? date.substring(0, 10) : date);
  final titleParts = [
    if (interview.company?.isNotEmpty == true) interview.company!,
    if (interview.position?.isNotEmpty == true) interview.position!,
    if (datePart.isNotEmpty) datePart,
  ];

  final buffer = StringBuffer()
    ..writeln(
      '# 面试复盘 - '
      '${titleParts.isEmpty ? '未命名面试' : titleParts.join(' ')}',
    )
    ..writeln()
    ..writeln('## 面试信息')
    ..writeln('- 公司：${interview.company ?? ''}')
    ..writeln('- 岗位：${interview.position ?? ''}')
    ..writeln('- 轮次：${interview.round ?? ''}')
    ..writeln(
      '- 时长：${interview.durationSeconds == null ? '' : formatClock(Duration(seconds: interview.durationSeconds!))}',
    )
    ..writeln()
    ..writeln('## 问题卡片');

  final sorted = [...cards]..sort((a, b) {
      final sa = a.sourceStartTime;
      final sb = b.sourceStartTime;
      if (sa == null && sb == null) {
        return a.createdAt.compareTo(b.createdAt);
      }
      if (sa == null) return 1;
      if (sb == null) return -1;
      final byStart = sa.compareTo(sb);
      if (byStart != 0) return byStart;
      return a.createdAt.compareTo(b.createdAt);
    });

  for (var i = 0; i < sorted.length; i++) {
    final card = sorted[i];
    final cardAnnotations =
        annotationsForCard(card, segments, annotations);
    final labels = cardAnnotations.map(markdownTagDisplay).toList();
    final notes = [
      for (final a in cardAnnotations)
        if (a.note?.trim().isNotEmpty == true) a.note!.trim(),
    ];
    final answer = card.myAnswer?.trim();
    final ai = card.aiReference?.trim();

    buffer
      ..writeln()
      ..writeln('### 问题 ${i + 1}')
      ..writeln('**问题**：${card.question}')
      ..writeln('**我的回答**：${answer == null || answer.isEmpty ? '（未作答）' : answer}');
    if (labels.isNotEmpty) buffer.writeln('**标注**：${labels.join(' / ')}');
    if (notes.isNotEmpty) buffer.writeln('**复盘笔记**：${notes.join('；')}');
    if (ai != null && ai.isNotEmpty) buffer.writeln('**AI 参考**：$ai');
    if (i < sorted.length - 1) buffer..writeln()..writeln('---');
  }

  return buffer.toString();
}

/// 面试复盘文稿导出：拼模板 → 写入 documents/exports/ → 状态推进为已总结。
/// 分享由 UI 层注入（markdownSharerProvider，share_plus）。
class MarkdownExportService {
  MarkdownExportService({
    required this.db,
    Future<String> Function()? documentsPathResolver,
  }) : _documentsPathResolver =
            documentsPathResolver ?? _defaultDocumentsPath;

  final AppDatabase db;
  final Future<String> Function() _documentsPathResolver;

  static Future<String> _defaultDocumentsPath() async =>
      (await getApplicationDocumentsDirectory()).path;

  Future<ExportedMarkdown> exportInterview(String interviewId) async {
    final interview = await db.interviewsDao.getById(interviewId);
    if (interview == null) {
      throw StateError('面试记录不存在：$interviewId');
    }

    final content = buildInterviewMarkdown(
      interview: interview,
      cards: await db.flashcardsDao.getByInterview(interviewId),
      annotations: await db.annotationsDao.getByInterview(interviewId),
      segments: await db.segmentsDao.getByInterview(interviewId),
    );

    final docsPath = await _documentsPathResolver();
    final dir = Directory('$docsPath/exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final fileName =
        '${_composeFileBase(interview)}-${_timestamp()}.md';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);

    // 状态只进不退：导出即完成一次总结（draft/transcribed/annotated → summarized）
    if (interview.status != 'summarized') {
      await db.interviewsDao.updateOne(
        interview.id,
        const InterviewsCompanion(status: Value('summarized')),
      );
    }

    return ExportedMarkdown(path: file.path, fileName: fileName);
  }

  /// 文件名 = 面试复盘 + 公司/岗位；路径非法字符一律替换为下划线。
  String _composeFileBase(Interview interview) {
    final parts = [
      '面试复盘',
      for (final s in [interview.company, interview.position])
        if (s != null && _sanitize(s).isNotEmpty) _sanitize(s),
    ];
    return parts.join('-');
  }

  String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
