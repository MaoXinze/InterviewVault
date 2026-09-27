import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/data/secure/key_storage.dart';
import 'package:interview_vault/features/export/data_management_service.dart';

/// PRD 2.10 数据管理：全量导出（JSON + Markdown）与删除全部。
/// 导出 JSON 的 schema 是稳定性承诺（AGENTS 工程纪律 4 / export.dart 文档）。
class FakeKeyStorage implements KeyStorage {
  final store = <String, String>{};

  @override
  Future<void> write(String provider, String key) async =>
      store['apikey.$provider'] = key;

  @override
  Future<String?> read(String provider) async => store['apikey.$provider'];

  @override
  Future<void> delete(String provider) async =>
      store.remove('apikey.$provider');

  @override
  Future<bool> has(String provider) async => store.containsKey('apikey.$provider');
}

void main() {
  late AppDatabase db;
  late FakeKeyStorage keys;
  late List<String?> cleanedAudioPaths;

  DateTime fixedClock() => DateTime.parse('2026-09-27T12:00:00.000');

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    keys = FakeKeyStorage();
    cleanedAudioPaths = [];
  });
  tearDown(() async => db.close());

  DataManagementService buildService() => DataManagementService(
        db: db,
        keyStorage: keys,
        documentsPathResolver: () async => '/stub/docs',
        audioFileCleaner: (path) async => cleanedAudioPaths.add(path),
        clock: fixedClock,
      );

  Future<void> seedTwoInterviews() async {
    Future<void> interview(
      String id, {
      String? company,
      String? date,
      String? audioPath,
    }) =>
        db.interviewsDao.insertOne(
          InterviewsCompanion.insert(
            id: id,
            company: Value(company),
            interviewDate: Value(date),
            audioFilePath: Value(audioPath),
            status: const Value('transcribed'),
          ),
        );
    await interview('iv-2',
        company: '美团',
        date: '2026-09-27T14:00:00.000',
        audioPath: '/stub/audio/b.m4a');
    await interview('iv-1',
        company: '字节跳动',
        date: '2026-09-26T10:00:00.000',
        audioPath: '/stub/audio/a.m4a');

    await db.segmentsDao.insertOne(
      TranscriptSegmentsCompanion.insert(
        id: 'seg-1',
        interviewId: 'iv-1',
        startTime: 0,
        endTime: 10,
        content: '自我介绍一下',
      ),
    );
    await db.annotationsDao.insertOne(
      AnnotationsCompanion.insert(
        id: 'an-1',
        interviewId: 'iv-1',
        tag: 'question',
        segmentId: const Value('seg-1'),
      ),
    );
    await db.flashcardsDao.insertOne(
      FlashcardsCompanion.insert(
        id: 'fc-1',
        interviewId: 'iv-1',
        question: '自我介绍一下',
        sourceStartTime: const Value(0),
        sourceEndTime: const Value(10),
      ),
    );
  }

  group('exportAllJson', () {
    test('写入 pretty JSON：schema_version=1、六个数组与行数一致', () async {
      await seedTwoInterviews();
      final service = buildService();

      final result = await service.exportAllJson();

      expect(result.fileName, startsWith('interviewvault-export-'));
      expect(result.fileName, endsWith('.json'));
      final decoded =
          jsonDecode(await File(result.path).readAsString()) as Map<String, dynamic>;
      expect(decoded['schema_version'], 1);
      expect(decoded['exported_at'], '2026-09-27T12:00:00.000');
      final data = decoded['data'] as Map<String, dynamic>;
      expect((data['interviews'] as List).length, 2);
      expect((data['transcript_segments'] as List).length, 1);
      expect((data['annotations'] as List).length, 1);
      expect((data['flashcards'] as List).length, 1);
      expect((data['ai_configs'] as List).length, 0);
      expect((data['tags'] as List).length, 5);
    });

    test('空库导出：合法 JSON，业务数组为空、系统标签保留', () async {
      final service = buildService();

      final result = await service.exportAllJson();
      final decoded =
          jsonDecode(await File(result.path).readAsString()) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>;
      expect((data['interviews'] as List).isEmpty, isTrue);
      expect((data['tags'] as List).length, 5);
    });
  });

  group('exportAllMarkdown', () {
    test('bundle 快照：头部 + 按面试日期升序 + 文档间隔线', () async {
      await seedTwoInterviews();
      await db.flashcardsDao.insertOne(
        FlashcardsCompanion.insert(
          id: 'fc-2',
          interviewId: 'iv-2',
          question: '聊聊项目亮点',
          sourceStartTime: const Value(5),
          sourceEndTime: const Value(20),
        ),
      );
      final service = buildService();

      final result = await service.exportAllMarkdown();

      expect(result.fileName, startsWith('interviewvault-复盘全量-'));
      final markdown = await File(result.path).readAsString();
      final expected = [
        '# InterviewVault 复盘全量导出',
        '',
        '导出时间：2026-09-27 12:00:00',
        '面试场次：2',
        '',
        '---',
        '',
        '# 面试复盘 - 字节跳动 2026-09-26',
        '',
        '## 面试信息',
        '- 公司：字节跳动',
        '- 岗位：',
        '- 轮次：',
        '- 时长：',
        '',
        '## 问题卡片',
        '',
        '### 问题 1',
        '**问题**：自我介绍一下',
        '**我的回答**：（未作答）',
        '**标注**：❓ 问题',
        '',
        '---',
        '',
        '# 面试复盘 - 美团 2026-09-27',
        '',
        '## 面试信息',
        '- 公司：美团',
        '- 岗位：',
        '- 轮次：',
        '- 时长：',
        '',
        '## 问题卡片',
        '',
        '### 问题 1',
        '**问题**：聊聊项目亮点',
        '**我的回答**：（未作答）',
      ].join('\n');
      expect(markdown, '$expected\n');
    });

    test('空库：仅头部，场次 0', () async {
      final service = buildService();

      final result = await service.exportAllMarkdown();
      final markdown = await File(result.path).readAsString();
      expect(
        markdown,
        '# InterviewVault 复盘全量导出\n'
        '\n'
        '导出时间：2026-09-27 12:00:00\n'
        '面试场次：0\n',
      );
    });
  });

  group('deleteAllData', () {
    test('级联清库 + 音频清理 + AI 配置与 Key + 自定义标签，系统标签保留',
        () async {
      await seedTwoInterviews();
      await db.tagsDao.insertOne(
        TagsCompanion.insert(id: 'tag-custom', name: '心态'),
      );
      await db.aiConfigsDao.upsert(
        AiConfigsCompanion.insert(
          id: 'cfg-1',
          provider: 'deepseek',
          modelName: const Value('deepseek-chat'),
        ),
      );
      await keys.write('deepseek', 'sk-test');
      final service = buildService();

      final result = await service.deleteAllData();

      expect(result.deletedInterviews, 2);
      expect(await db.interviewsDao.getAll(), isEmpty);
      expect(await db.segmentsDao.getAll(), isEmpty);
      expect(await db.annotationsDao.getAll(), isEmpty);
      expect(await db.flashcardsDao.getAll(), isEmpty);
      expect(await db.aiConfigsDao.getAll(), isEmpty);
      final tags = await db.tagsDao.getAll();
      expect(tags.where((t) => !t.isSystem), isEmpty);
      expect(tags.length, 5);
      expect(keys.store, isEmpty);
      expect(cleanedAudioPaths, ['/stub/audio/b.m4a', '/stub/audio/a.m4a']);
    });

    test('空库删除：0 场，不抛异常', () async {
      final service = buildService();

      final result = await service.deleteAllData();

      expect(result.deletedInterviews, 0);
      expect(cleanedAudioPaths, isEmpty);
    });
  });
}
