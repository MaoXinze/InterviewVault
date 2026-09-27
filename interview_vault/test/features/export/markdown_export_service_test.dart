import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/export/markdown_export_service.dart';

/// PRD 2.8 Markdown 导出模板快照：AGENTS 工程纪律 4——格式是稳定性承诺，
/// 任何模板调整都是破坏性变更，必须先改这里的期望串并文档化。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  Future<void> seedFullInterview() async {
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: 'iv-1',
        company: const Value('字节跳动'),
        position: const Value('后端工程师'),
        round: const Value('二面'),
        interviewDate: const Value('2026-09-27T10:00:00.000'),
        durationSeconds: const Value(1925),
        status: const Value('annotated'),
      ),
    );
    Future<void> segment(String id, double start, double end, String content,
            String? speaker) =>
        db.segmentsDao.insertOne(
          TranscriptSegmentsCompanion.insert(
            id: id,
            interviewId: 'iv-1',
            startTime: start,
            endTime: end,
            content: content,
            speaker: Value(speaker),
          ),
        );
    await segment('seg-1', 0, 30, '先自我介绍一下', 'interviewer');
    await segment('seg-2', 30, 120, '我叫张三，三年后端经验，主要做过电商订单系统', 'candidate');
    await segment('seg-3', 120, 180, '讲讲 Flutter 的事件循环', 'interviewer');
    await segment('seg-4', 180, 240, '先说 microtask queue，再说 event queue', 'candidate');

    Future<void> annotation(
      String id,
      String segmentId,
      String tag, {
      String? customTagName,
      String? note,
    }) =>
        db.annotationsDao.insertOne(
          AnnotationsCompanion.insert(
            id: id,
            interviewId: 'iv-1',
            tag: tag,
            segmentId: Value(segmentId),
            customTagName: Value(customTagName),
            note: Value(note),
            createdAt: Value('2026-09-27T10:05:0${id.split('-').last}'),
          ),
        );
    await annotation('an-1', 'seg-1', 'question');
    await annotation('an-2', 'seg-2', 'highlight', note: '项目难点讲清了');
    await annotation('an-3', 'seg-2', 'improvement', note: '超时没控制好');
    await annotation('an-4', 'seg-1', 'custom', customTagName: '心态平稳');

    Future<void> card(
      String id, {
      required String question,
      String? myAnswer,
      String? aiReference,
      double? start,
      double? end,
      List<String> tags = const ['问题'],
    }) =>
        db.flashcardsDao.insertOne(
          FlashcardsCompanion.insert(
            id: id,
            interviewId: 'iv-1',
            question: question,
            myAnswer: Value(myAnswer),
            aiReference: Value(aiReference),
            tags: Value('["${tags.join('","')}"]'),
            sourceStartTime: Value(start),
            sourceEndTime: Value(end),
          ),
        );
    // card-3 故意最先插入且 source 为 null：导出按时间轴排序，null 殿后
    await card('card-3', question: '你有什么想问我的吗');
    await card(
      'card-1',
      question: '先自我介绍一下',
      myAnswer: '我叫张三，三年后端经验，主要做过电商订单系统',
      start: 0,
      end: 120,
      tags: const ['问题', '回答'],
    );
    await card(
      'card-2',
      question: '讲讲 Flutter 的事件循环',
      myAnswer: '先说 microtask queue，再说 event queue',
      aiReference: '分三点：事件循环模型、microtask 优先、isolate 隔离。',
      start: 120,
      end: 240,
    );
  }

  group('buildInterviewMarkdown 模板快照', () {
    test('完整数据：PRD 2.8 模板 + 标注/笔记/AI 参考/时间轴排序逐字符锁定',
        () async {
      await seedFullInterview();
      final interview = (await db.interviewsDao.getById('iv-1'))!;
      final markdown = buildInterviewMarkdown(
        interview: interview,
        cards: await db.flashcardsDao.getByInterview('iv-1'),
        annotations: await db.annotationsDao.getByInterview('iv-1'),
        segments: await db.segmentsDao.getByInterview('iv-1'),
      );

      final expected = [
        '# 面试复盘 - 字节跳动 后端工程师 2026-09-27',
        '',
        '## 面试信息',
        '- 公司：字节跳动',
        '- 岗位：后端工程师',
        '- 轮次：二面',
        '- 时长：32:05',
        '',
        '## 问题卡片',
        '',
        '### 问题 1',
        '**问题**：先自我介绍一下',
        '**我的回答**：我叫张三，三年后端经验，主要做过电商订单系统',
        '**标注**：❓ 问题 / ⭐ 亮点 / ⚠️ 待改进 / 🏷️ 心态平稳',
        '**复盘笔记**：项目难点讲清了；超时没控制好',
        '',
        '---',
        '',
        '### 问题 2',
        '**问题**：讲讲 Flutter 的事件循环',
        '**我的回答**：先说 microtask queue，再说 event queue',
        '**AI 参考**：分三点：事件循环模型、microtask 优先、isolate 隔离。',
        '',
        '---',
        '',
        '### 问题 3',
        '**问题**：你有什么想问我的吗',
        '**我的回答**：（未作答）',
      ].join('\n');
      expect(markdown, '$expected\n');
    });

    test('全空数据：标题降级为未命名面试，信息行保留空值，无卡片段', () {
      final interview = Interview(
        id: 'iv-2',
        status: 'draft',
        createdAt: '2026-09-27T10:00:00.000',
        updatedAt: '2026-09-27T10:00:00.000',
      );
      final markdown = buildInterviewMarkdown(
        interview: interview,
        cards: const [],
        annotations: const [],
        segments: const [],
      );

      final expected = [
        '# 面试复盘 - 未命名面试',
        '',
        '## 面试信息',
        '- 公司：',
        '- 岗位：',
        '- 轮次：',
        '- 时长：',
        '',
        '## 问题卡片',
      ].join('\n');
      expect(markdown, '$expected\n');
    });

    test('部分字段：标题只拼接非空部分，日期取前 10 位', () {
      final interview = Interview(
        id: 'iv-3',
        company: '美团',
        interviewDate: '2026-09-27T14:30:00.000',
        status: 'transcribed',
        createdAt: '2026-09-27T14:30:00.000',
        updatedAt: '2026-09-27T14:30:00.000',
      );
      final markdown = buildInterviewMarkdown(
        interview: interview,
        cards: const [],
        annotations: const [],
        segments: const [],
      );
      expect(markdown, startsWith('# 面试复盘 - 美团 2026-09-27\n'));
    });
  });

  group('MarkdownExportService', () {
    test('exportInterview 写入 exports 目录并翻转状态为 summarized，二次导出复用目录',
        () async {
      await seedFullInterview();
      final tmp = await Directory.systemTemp.createTemp('iv_export_test');
      addTearDown(() => tmp.delete(recursive: true));
      final service = MarkdownExportService(
        db: db,
        documentsPathResolver: () async => tmp.path,
      );

      final result = await service.exportInterview('iv-1');

      final file = File(result.path);
      expect(await file.exists(), isTrue);
      expect(file.parent.path, contains('exports'));
      expect(result.fileName, startsWith('面试复盘-字节跳动'));
      expect(result.fileName, endsWith('.md'));
      expect(await file.readAsString(), startsWith('# 面试复盘 - 字节跳动'));

      final reloaded = await db.interviewsDao.getById('iv-1');
      expect(reloaded!.status, 'summarized');

      final again = await service.exportInterview('iv-1');
      expect(await File(again.path).exists(), isTrue);
    });

    test('文件名净化：公司/岗位中的非法字符替换为下划线', () async {
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-bad',
          company: const Value('A/B\\C:D*E?"F<G>H|I'),
        ),
      );
      final tmp = await Directory.systemTemp.createTemp('iv_export_test');
      addTearDown(() => tmp.delete(recursive: true));
      final service = MarkdownExportService(
        db: db,
        documentsPathResolver: () async => tmp.path,
      );

      final result = await service.exportInterview('iv-bad');

      final illegal = RegExp(r'[\\/:*?"<>|]');
      expect(illegal.hasMatch(result.fileName), isFalse);
      expect(await File(result.path).exists(), isTrue);
    });

    test('面试不存在时抛 StateError', () async {
      final tmp = await Directory.systemTemp.createTemp('iv_export_test');
      addTearDown(() => tmp.delete(recursive: true));
      final service = MarkdownExportService(
        db: db,
        documentsPathResolver: () async => tmp.path,
      );
      await expectLater(
        service.exportInterview('nope'),
        throwsStateError,
      );
    });
  });
}
