import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/database/app_database.dart';
import '../../data/secure/key_storage.dart';
import 'markdown_export_service.dart';

/// 删除全部的结果（提示用户清掉了多少场面试）。
class DeleteAllResult {
  const DeleteAllResult({required this.deletedInterviews});

  final int deletedInterviews;
}

/// 数据管理服务（PRD 2.10）：
/// - 全量导出 JSON（schema 见 data/database/export.dart，稳定性承诺）
/// - 全量导出 Markdown（bundle = 头部 + 每场面试的单场文稿，快照锁定）
/// - 删除全部数据：级联清库 + 录音真删 + AI 配置与 Key + 自定义标签
///   （系统标签是 App 预置能力，保留）
class DataManagementService {
  DataManagementService({
    required this.db,
    required this.keyStorage,
    Future<String> Function()? documentsPathResolver,
    Future<void> Function(String?)? audioFileCleaner,
    DateTime Function()? clock,
  })  : _documentsPathResolver =
            documentsPathResolver ?? _defaultDocumentsPath,
        _audioFileCleaner = audioFileCleaner ?? _noopCleaner,
        _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final KeyStorage keyStorage;
  final Future<String> Function() _documentsPathResolver;
  final Future<void> Function(String?) _audioFileCleaner;
  final DateTime Function() _clock;

  static Future<String> _defaultDocumentsPath() async =>
      (await getApplicationDocumentsDirectory()).path;

  static Future<void> _noopCleaner(String? path) async {}

  /// 全量 JSON 备份（六表 + schema_version，PRD 2.10）
  Future<ExportedFile> exportAllJson() async {
    final payload = await buildExportPayload(db, now: _clock);
    final content = const JsonEncoder.withIndent('  ').convert(payload);
    return _write(
      'interviewvault-export-${_fileStamp()}.json',
      content,
    );
  }

  /// 全量 Markdown：按面试日期升序把每场的复盘文稿合并为一个 bundle。
  /// 格式为单场模板（PRD 2.8）之上的扩展层，头部与分隔被快照锁定。
  Future<ExportedFile> exportAllMarkdown() async {
    final interviews = [...await db.interviewsDao.getAll()]..sort((a, b) {
        final da = a.interviewDate;
        final dbb = b.interviewDate;
        if (da == null && dbb == null) {
          return a.createdAt.compareTo(b.createdAt);
        }
        if (da == null) return 1;
        if (dbb == null) return -1;
        final byDate = da.compareTo(dbb);
        if (byDate != 0) return byDate;
        return a.createdAt.compareTo(b.createdAt);
      });
    final segments = await db.segmentsDao.getAll();
    final annotations = await db.annotationsDao.getAll();
    final cards = await db.flashcardsDao.getAll();

    final docs = <String>[];
    for (final interview in interviews) {
      final interviewCards = [
        for (final c in cards)
          if (c.interviewId == interview.id) c,
      ];
      final interviewAnnotations = [
        for (final a in annotations)
          if (a.interviewId == interview.id) a,
      ];
      final interviewSegments = [
        for (final s in segments)
          if (s.interviewId == interview.id) s,
      ];
      docs.add(
        buildInterviewMarkdown(
          interview: interview,
          cards: interviewCards,
          annotations: interviewAnnotations,
          segments: interviewSegments,
        ).trim(),
      );
    }

    final now = _clock();
    final header = [
      '# InterviewVault 复盘全量导出',
      '',
      '导出时间：${_formatStamp(now)}',
      '面试场次：${interviews.length}',
    ].join('\n');
    final content = docs.isEmpty
        ? '$header\n'
        : '${[header, '---', docs.join('\n\n---\n\n')].join('\n\n')}\n';

    return _write('interviewvault-复盘全量-${_fileStamp()}.md', content);
  }

  /// 删除全部数据（AGENTS 铁律 3"删除即真删"）：
  /// 面试记录（外键级联逐字稿/标注/卡片）→ 录音文件 → AI 配置与
  /// 对应 Key → 自定义标签。系统标签为预置能力保留。
  Future<DeleteAllResult> deleteAllData() async {
    final interviews = await db.interviewsDao.getAll();
    for (final interview in interviews) {
      await _audioFileCleaner(interview.audioFilePath);
    }
    for (final config in await db.aiConfigsDao.getAll()) {
      await keyStorage.delete(config.provider);
    }
    await db.customUpdate('DELETE FROM interviews');
    await db.customUpdate('DELETE FROM ai_configs');
    await db.customUpdate('DELETE FROM tags WHERE is_system = 0');
    return DeleteAllResult(deletedInterviews: interviews.length);
  }

  Future<ExportedFile> _write(String fileName, String content) async {
    final docsPath = await _documentsPathResolver();
    final dir = Directory('$docsPath/exports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
    return ExportedFile(path: file.path, fileName: fileName);
  }

  String _fileStamp() {
    final now = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  String _formatStamp(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }
}
