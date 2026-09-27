import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  Future<String> insertInterview({
    String id = 'iv-1',
    String company = '字节跳动',
    String status = 'transcribed',
  }) async {
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: id,
        company: Value(company),
        position: const Value('客户端工程师'),
        round: const Value('一面'),
        interviewDate: const Value('2026-09-26T10:00:00.000'),
        status: Value(status),
      ),
    );
    return id;
  }

  group('interviews CRUD', () {
    test('插入后按 id 可查出全部字段，status 默认 draft，时间戳自动填充', () async {
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(id: 'iv-0'),
      );
      final row = await db.interviewsDao.getById('iv-0');
      expect(row, isNotNull);
      expect(row!.status, 'draft');
      expect(row.createdAt, isNotEmpty);
      expect(row.updatedAt, isNotEmpty);
    });

    test('update 修改字段并刷新 updated_at，watch 流实时发出新值', () async {
      final id = await insertInterview(id: 'iv-2');
      final initial = await db.interviewsDao.getById(id);
      await db.interviewsDao.updateOne(
        id,
        const InterviewsCompanion(company: Value('腾讯')),
      );
      final updated = await db.interviewsDao.getById(id);
      expect(updated!.company, '腾讯');
      expect(updated.updatedAt, isNot(initial!.updatedAt));

      final stream = db.interviewsDao.watchAll();
      expect(await stream.first, isA<List<Interview>>());
    });

    test('watchAll 按面试日期倒序排列', () async {
      await insertInterview(id: 'iv-a', company: 'A');
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-b',
          interviewDate: Value('2026-09-27T10:00:00.000'),
        ),
      );
      final rows = await db.interviewsDao.watchAll().first;
      expect(rows.map((r) => r.id).toList(), ['iv-b', 'iv-a']);
    });

    test('search 按 公司/岗位 关键词匹配', () async {
      await insertInterview(id: 'iv-s1', company: '字节跳动');
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-s2',
          position: Value('产品经理'),
        ),
      );
      final byCompany = await db.interviewsDao.search('字节');
      final byPosition = await db.interviewsDao.search('产品');
      expect(byCompany.map((r) => r.id), ['iv-s1']);
      expect(byPosition.map((r) => r.id), ['iv-s2']);
    });
  });

  group('级联删除', () {
    test('删除面试记录时，转写片段/标注/卡片一并删除', () async {
      final id = await insertInterview();
      await db.segmentsDao.insertOne(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-1',
          interviewId: id,
          startTime: 0,
          endTime: 3.5,
          content: '请介绍你自己',
        ),
      );
      await db.annotationsDao.insertOne(
        AnnotationsCompanion.insert(
          id: 'an-1',
          interviewId: id,
          tag: 'highlight',
        ),
      );
      await db.flashcardsDao.insertOne(
        FlashcardsCompanion.insert(
          id: 'fc-1',
          interviewId: id,
          question: '请介绍你自己',
        ),
      );

      await db.interviewsDao.deleteOne(id);

      expect(await db.segmentsDao.getByInterview(id), isEmpty);
      expect(await db.annotationsDao.getByInterview(id), isEmpty);
      expect(await db.flashcardsDao.getByInterview(id), isEmpty);
      expect(await db.interviewsDao.getById(id), isNull);
    });
  });

  group('segments', () {
    test('按 start_time 升序返回指定面试的片段', () async {
      final id = await insertInterview();
      await db.segmentsDao.insertOne(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-2',
          interviewId: id,
          startTime: 10,
          endTime: 12,
          content: '第二句',
        ),
      );
      await db.segmentsDao.insertOne(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-1',
          interviewId: id,
          startTime: 0,
          endTime: 3.5,
          content: '第一句',
        ),
      );
      final rows = await db.segmentsDao.getByInterview(id);
      expect(rows.map((r) => r.id).toList(), ['seg-1', 'seg-2']);
    });

    test('updateOne 修正文本/标记说话人并刷新 updated_at（W2-M3 编辑校正）', () async {
      final id = await insertInterview();
      await db.segmentsDao.insertOne(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-e1',
          interviewId: id,
          startTime: 0,
          endTime: 3.5,
          content: '请介绍你自己',
        ),
      );
      final before = await db.segmentsDao.getAll();
      final original = before.firstWhere((r) => r.id == 'seg-e1');

      await db.segmentsDao.updateOne(
        'seg-e1',
        const TranscriptSegmentsCompanion(
          content: Value('请介绍一下你自己'),
          speaker: Value('interviewer'),
        ),
      );
      final edited = await db.segmentsDao.getAll();
      final row = edited.firstWhere((r) => r.id == 'seg-e1');
      expect(row.content, '请介绍一下你自己');
      expect(row.speaker, 'interviewer');
      expect(row.updatedAt, isNot(original.updatedAt));
    });

    test('watchById 监听单条面试行（详情页响应转写状态变化）', () async {
      final id = await insertInterview(status: 'draft');
      final first = await db.interviewsDao.watchById(id).first;
      expect(first, isNotNull);
      expect(first!.status, 'draft');

      await db.interviewsDao.updateOne(
        id,
        const InterviewsCompanion(status: Value('transcribed')),
      );
      final second = await db.interviewsDao.watchById(id).first;
      expect(second!.status, 'transcribed');
    });
  });

  group('annotations 按标签筛选', () {
    test('filterByTag 只返回指定标签的标注', () async {
      final id = await insertInterview();
      // createdAt 固定为同一时间戳：排序结果由次序键 id 决定，不受时钟影响
      const ts = '2026-09-26T10:00:00.000';
      for (final entry in {
        'an-q': 'question',
        'an-h': 'highlight',
        'an-m': 'mistake',
        'an-m2': 'mistake',
      }.entries) {
        await db.annotationsDao.insertOne(
          AnnotationsCompanion.insert(
            id: entry.key,
            interviewId: id,
            tag: entry.value,
            createdAt: const Value(ts),
            updatedAt: const Value(ts),
          ),
        );
      }
      final mistakes = await db.annotationsDao.filterByTag('mistake');
      expect(mistakes.map((a) => a.id), ['an-m', 'an-m2']);
      expect(await db.annotationsDao.filterByTag('question').then((r) => r.map((a) => a.id)), ['an-q']);
    });

    test('自定义标签可带 customTagName', () async {
      final id = await insertInterview();
      await db.annotationsDao.insertOne(
        AnnotationsCompanion.insert(
          id: 'an-custom',
          interviewId: id,
          tag: 'custom',
          customTagName: Value('反问环节'),
        ),
      );
      final row = (await db.annotationsDao.getByInterview(id)).single;
      expect(row.tag, 'custom');
      expect(row.customTagName, '反问环节');
    });
  });

  group('flashcards', () {
    test('watchAll + countAll 提供待回顾数', () async {
      final id = await insertInterview();
      await db.flashcardsDao.insertOne(
        FlashcardsCompanion.insert(
          id: 'fc-1',
          interviewId: id,
          question: 'Q1',
        ),
      );
      await db.flashcardsDao.insertOne(
        FlashcardsCompanion.insert(
          id: 'fc-2',
          interviewId: id,
          question: 'Q2',
        ),
      );
      expect(await db.flashcardsDao.countAll(), 2);
      expect((await db.flashcardsDao.watchAll().first).length, 2);
    });

    test('markReviewed 增加复习次数并记录时间', () async {
      final id = await insertInterview();
      await db.flashcardsDao.insertOne(
        FlashcardsCompanion.insert(
          id: 'fc-1',
          interviewId: id,
          question: 'Q1',
        ),
      );
      await db.flashcardsDao.markReviewed('fc-1');
      final row = (await db.flashcardsDao.getByInterview(id)).single;
      expect(row.reviewCount, 1);
      expect(row.lastReviewedAt, isNotNull);
    });

    test('tags JSON 数组序列化往返', () async {
      final id = await insertInterview();
      await db.flashcardsDao.insertOne(
        FlashcardsCompanion.insert(
          id: 'fc-1',
          interviewId: id,
          question: 'Q1',
          tags: Value(encodeCardTags(['亮点', '计算机网络'])),
        ),
      );
      final row = (await db.flashcardsDao.getByInterview(id)).single;
      expect(decodeCardTags(row.tags), ['亮点', '计算机网络']);
    });
  });

  group('ai_configs', () {
    test('setActive 独占激活：新配置激活后其余全部失效', () async {
      await db.aiConfigsDao.upsert(
        AiConfigsCompanion.insert(id: 'cfg-1', provider: 'deepseek'),
      );
      await db.aiConfigsDao.upsert(
        AiConfigsCompanion.insert(id: 'cfg-2', provider: 'openai'),
      );
      await db.aiConfigsDao.setActive('cfg-1');

      final active = await db.aiConfigsDao.getActive();
      expect(active!.id, 'cfg-1');

      await db.aiConfigsDao.setActive('cfg-2');
      final active2 = await db.aiConfigsDao.getActive();
      expect(active2!.id, 'cfg-2');
      final first = await db.aiConfigsDao.getById('cfg-1');
      expect(first!.isActive, isFalse);
    });

    test('upsert 更新已有配置而不新建行，且 createdAt 不被重置', () async {
      await db.aiConfigsDao.upsert(
        AiConfigsCompanion.insert(id: 'cfg-1', provider: 'deepseek'),
      );
      final created = await db.aiConfigsDao.getById('cfg-1');
      final createdAt = created!.createdAt;

      await db.aiConfigsDao.upsert(
        AiConfigsCompanion.insert(
          id: 'cfg-1',
          provider: 'deepseek',
          modelName: Value('deepseek-chat'),
        ),
      );
      final rows = await db.aiConfigsDao.getAll();
      expect(rows.length, 1);
      expect(rows.single.modelName, 'deepseek-chat');
      expect(rows.single.createdAt, createdAt, reason: '重复保存不应重置创建时间');
    });
  });

  group('tags', () {
    test('建库时预置 5 个系统标签且带定义文案', () async {
      final rows = await db.tagsDao.watchAll().first;
      final names = rows.map((t) => t.name).toList();
      expect(
        names,
        containsAllInOrder([
          '问题',
          '回答',
          '亮点',
          '失误',
          '待改进',
        ]),
      );
      expect(rows.every((t) => t.isSystem), isTrue);
      expect(rows.every((t) => t.description != null && t.description!.isNotEmpty), isTrue);
    });

    test('同名标签唯一', () async {
      await db.tagsDao.insertOne(
        TagsCompanion.insert(id: 'tag-x', name: '计算机网络'),
      );
      await expectLater(
        db.tagsDao.insertOne(
          TagsCompanion.insert(id: 'tag-y', name: '计算机网络'),
        ),
        throwsA(anything),
      );
    });

    test('系统标签不可删除，自定义标签可删除', () async {
      final system = (await db.tagsDao.watchAll().first).first;
      await db.tagsDao.insertOne(
        TagsCompanion.insert(id: 'tag-x', name: '自定义'),
      );
      await expectLater(
        db.tagsDao.deleteOne(system.id),
        throwsA(isA<SystemTagDeletionError>()),
      );
      await db.tagsDao.deleteOne('tag-x');
      expect(
        await db.tagsDao.getById('tag-x'),
        isNull,
      );
    });
  });

  group('迁移与建库', () {
    test('v1 建出全部六张表', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
          )
          .get();
      final names = tables.map((r) => r.data['name'] as String).toSet();
      expect(names, containsAll([
        'interviews',
        'transcript_segments',
        'annotations',
        'flashcards',
        'ai_configs',
        'tags',
      ]));
    });

    test('schemaVersion 为 1 且外键开启', () async {
      expect(db.schemaVersion, 1);
      final fk = await db
          .customSelect('PRAGMA foreign_keys')
          .getSingle();
      expect(fk.data['foreign_keys'], 1);
    });
  });

  group('全量导出 schema', () {
    test('schema_version=1，六个数据数组与行数一致，字段名稳定', () async {
      final id = await insertInterview();
      await db.segmentsDao.insertOne(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-1',
          interviewId: id,
          startTime: 0,
          endTime: 3.5,
          content: '请介绍你自己',
        ),
      );
      await db.annotationsDao.insertOne(
        AnnotationsCompanion.insert(
          id: 'an-1',
          interviewId: id,
          tag: 'highlight',
        ),
      );
      await db.flashcardsDao.insertOne(
        FlashcardsCompanion.insert(
          id: 'fc-1',
          interviewId: id,
          question: '请介绍你自己',
        ),
      );

      final payload = await buildExportPayload(db);
      expect(payload['schema_version'], 1);
      expect(payload['exported_at'], isA<String>());

      final data = payload['data'] as Map<String, dynamic>;
      expect((data['interviews'] as List).length, 1);
      expect((data['transcript_segments'] as List).length, 1);
      expect((data['annotations'] as List).length, 1);
      expect((data['flashcards'] as List).length, 1);
      expect((data['ai_configs'] as List).isEmpty, isTrue);
      expect((data['tags'] as List).length, 5);

      // 稳定性承诺：导出键使用列名（snake_case），后续版本不得改名
      final interview = (data['interviews'] as List).first as Map<String, dynamic>;
      expect(interview.keys, containsAll(['id', 'company', 'position', 'status', 'createdAt']));
      final card = (data['flashcards'] as List).first as Map<String, dynamic>;
      expect(card.keys, containsAll(['question', 'myAnswer', 'sourceStartTime']));
      final tag = (data['tags'] as List).first as Map<String, dynamic>;
      expect(tag.keys, containsAll(['name', 'isSystem', 'description']));
    });
  });
}
