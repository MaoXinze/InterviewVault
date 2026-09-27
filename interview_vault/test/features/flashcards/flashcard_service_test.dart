import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/flashcards/flashcard_service.dart';
import 'package:interview_vault/network/llm_client.dart';

/// 与 llm_client_test 相同的打桩方式：拦截 dio 请求，返回可编程响应体。
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.responder);

  final ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }
}

/// SSE 流式响应：逐 chunk 下发 data 行
ResponseBody _sseChunks(List<List<String>> chunks) {
  final stream = Stream<List<String>>.fromIterable(chunks)
      .map((deltas) => utf8.encode(
            deltas.map((d) => 'data: {"choices":[{"delta":{"content":"$d"}}]}\n\n').join(),
          ))
      .cast<Uint8List>();
  return ResponseBody(stream, 200);
}

void main() {
  late AppDatabase db;
  late FlashcardService service;
  Future<LlmClient?>? nextChatClient;
  int factoryCalls = 0;

  Future<LlmClient?> chatFactory() async {
    factoryCalls++;
    return nextChatClient;
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    factoryCalls = 0;
    nextChatClient = null;
    service = FlashcardService(db: db, chatClientFactory: chatFactory);
  });
  tearDown(() => db.close());

  Future<String> insertInterview() async {
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: 'iv-1',
        company: const Value('字节跳动'),
        position: const Value('客户端工程师'),
        status: const Value('transcribed'),
      ),
    );
    return 'iv-1';
  }

  Future<void> insertSegments() async {
    // 面试官问 → 我答两句 → 面试官追问
    for (final (id, start, end, content, speaker) in const [
      ('seg-q', 0.0, 4.0, '请介绍你最有挑战的项目', null),
      ('seg-a1', 4.0, 20.0, '我负责直播秒杀的链路改造', 'candidate'),
      ('seg-a2', 20.0, 35.0, '通过削峰和热点缓存把 P99 降了一半', null),
      ('seg-q2', 35.0, 38.0, '削峰具体怎么做的', 'interviewer'),
    ]) {
      await db.segmentsDao.insertOne(
        TranscriptSegmentsCompanion.insert(
          id: id,
          interviewId: 'iv-1',
          startTime: start,
          endTime: end,
          content: content,
          speaker: speaker == null ? const Value(null) : Value(speaker),
        ),
      );
    }
  }

  Future<Annotation> insertAnnotation({
    required String id,
    required String segmentId,
    required String tag,
    String? customTagName,
    String? note,
  }) async {
    await db.annotationsDao.insertOne(
      AnnotationsCompanion.insert(
        id: id,
        interviewId: 'iv-1',
        segmentId: Value(segmentId),
        tag: tag,
        customTagName: customTagName == null ? const Value(null) : Value(customTagName),
        note: note == null ? const Value(null) : Value(note),
      ),
    );
    return (await db.annotationsDao.getById(id))!;
  }

  group('从标注生成卡片', () {
    test('问题标注 → 卡片：正面=问题段，背面=后续我的回答拼接，来源时间锚定', () async {
      await insertInterview();
      await insertSegments();
      // 问题段标"问题"，回答段标"亮点" → 标签打通
      final question = await insertAnnotation(
          id: 'an-q', segmentId: 'seg-q', tag: 'question');
      await insertAnnotation(id: 'an-h', segmentId: 'seg-a1', tag: 'highlight');
      // 给问题段补一条"失误"标注，验证卡片标签聚合整段标注
      await insertAnnotation(id: 'an-m', segmentId: 'seg-q', tag: 'mistake');

      final card = await service.createOrUpdateFromAnnotation(question);

      expect(card.question, '请介绍你最有挑战的项目');
      // 面试官追问段（interviewer）与被标注为问题的段都不吞进回答
      expect(card.myAnswer, '我负责直播秒杀的链路改造\n通过削峰和热点缓存把 P99 降了一半');
      expect(card.sourceStartTime, 0.0);
      expect(card.sourceEndTime, 35.0); // 最后一段被吞的回答的结束时间
      expect(decodeCardTags(card.tags), ['问题', '失误']);
      expect(card.interviewId, 'iv-1');
    });

    test('停止条件：后续段被标注为问题时不吞入回答', () async {
      await insertInterview();
      await insertSegments();
      await insertAnnotation(id: 'an-q', segmentId: 'seg-q', tag: 'question');
      await insertAnnotation(id: 'an-q2', segmentId: 'seg-a1', tag: 'question');

      final card = await service.createOrUpdateFromAnnotation(
        (await db.annotationsDao.getById('an-q'))!,
      );

      expect(card.myAnswer, isNull);
      expect(card.sourceEndTime, 4.0);
    });

    test('幂等：同段重复生成更新卡片而不是新增，AI 参考保留', () async {
      await insertInterview();
      await insertSegments();
      final question = await insertAnnotation(
          id: 'an-q', segmentId: 'seg-q', tag: 'question');
      final first = await service.createOrUpdateFromAnnotation(question);
      await db.flashcardsDao.updateOne(
        first.id,
        FlashcardsCompanion(aiReference: const Value('旧的参考思路')),
      );
      // 用户校正了分段文字后再生成
      await db.segmentsDao.updateOne(
        'seg-a1',
        TranscriptSegmentsCompanion(content: Value('我负责秒杀链路改造（修正版）')),
      );

      final second = await service.createOrUpdateFromAnnotation(question);

      expect(second.id, first.id);
      expect(await db.flashcardsDao.countAll(), 1);
      expect(second.myAnswer, contains('修正版'));
      expect(second.aiReference, '旧的参考思路');
    });

    test('标注未关联分段时拒绝生成（类型化异常）', () async {
      await insertInterview();
      final orphan = await insertAnnotation(
        id: 'an-x',
        segmentId: 'seg-missing',
        tag: 'question',
      );
      // 分段不存在 → 找不到来源段
      expect(
        () => service.createOrUpdateFromAnnotation(orphan),
        throwsA(isA<FlashcardSourceException>()),
      );
    });
  });

  group('annotationsForCard 来源范围过滤', () {
    test('只取时间范围重叠分段的标注', () async {
      await insertInterview();
      await insertSegments();
      await insertAnnotation(id: 'an-q', segmentId: 'seg-q', tag: 'question');
      await insertAnnotation(id: 'an-h', segmentId: 'seg-a1', tag: 'highlight');
      await insertAnnotation(id: 'an-q2', segmentId: 'seg-q2', tag: 'question');
      final card = await service.createOrUpdateFromAnnotation(
        (await db.annotationsDao.getById('an-q'))!,
      );

      final picked = annotationsForCard(
        card,
        await db.segmentsDao.getByInterview('iv-1'),
        await db.annotationsDao.getByInterview('iv-1'),
      );

      expect(picked.map((a) => a.id), containsAll(['an-q', 'an-h']));
      expect(picked.map((a) => a.id), isNot(contains('an-q2')));
    });
  });

  group('AI 参考流式生成', () {
    LlmClient clientWith(ResponseBody Function(RequestOptions) responder) {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'))
        ..httpClientAdapter = _CapturingAdapter(responder);
      return LlmClient(
        endpoint: const AiEndpoint(
          providerId: 'openai',
          baseUrl: 'https://api.example.com/v1',
          modelName: 'test-model',
        ),
        apiKey: 'sk-test',
        dio: dio,
      );
    }

    Future<Flashcard> seedCard() async {
      await insertInterview();
      await insertSegments();
      final question = await insertAnnotation(
          id: 'an-q', segmentId: 'seg-q', tag: 'question');
      return service.createOrUpdateFromAnnotation(question);
    }

    test('流式产出 delta 与 done，完成后 ai_reference 持久化', () async {
      final card = await seedCard();
      nextChatClient = Future.value(clientWith(
        (_) => _sseChunks([
          ['先讲背景'],
          ['，再讲', '权衡'],
        ]),
      ));

      final events = await service.generateAiReference(card).toList();

      final deltas = events.whereType<CardAiDelta>().map((e) => e.text).toList();
      expect(deltas, ['先讲背景', '，再讲', '权衡']);
      expect(events.last, isA<CardAiDone>());
      expect((events.last as CardAiDone).full, '先讲背景，再讲权衡');
      final persisted = await db.flashcardsDao.getById(card.id);
      expect(persisted!.aiReference, '先讲背景，再讲权衡');
    });

    test('流中断：保留部分内容并产出 error 事件', () async {
      final card = await seedCard();
      nextChatClient = Future.value(clientWith((_) {
        // 先发一个正常 chunk，再以网络错误中断
        final controller = StreamController<Uint8List>()
          ..add(utf8.encode(
              'data: {"choices":[{"delta":{"content":"只有一半"}}]}\n\n'))
          ..addError(const SocketException('连接中断'))
          ..close();
        return ResponseBody(controller.stream, 200);
      }));

      final events = await service.generateAiReference(card).toList();

      expect(
        events.whereType<CardAiDelta>().map((e) => e.text).join(),
        '只有一半',
      );
      expect(events.last, isA<CardAiError>());
      final persisted = await db.flashcardsDao.getById(card.id);
      expect(persisted!.aiReference, '只有一半');
    });

    test('模型返回空内容：不覆盖已有参考，产出 error', () async {
      final card = await seedCard();
      await db.flashcardsDao.updateOne(
        card.id,
        FlashcardsCompanion(aiReference: const Value('已有的好参考')),
      );
      nextChatClient = Future.value(clientWith((_) => _sseChunks([[]])));

      final events = await service.generateAiReference(card).toList();

      expect(events.last, isA<CardAiError>());
      final persisted = await db.flashcardsDao.getById(card.id);
      expect(persisted!.aiReference, '已有的好参考');
    });

    test('未配置 AI：产出带引导文案的 error，且不调用数据库', () async {
      final card = await seedCard();
      nextChatClient = null;

      final events = await service.generateAiReference(card).toList();

      expect(events, hasLength(1));
      expect((events.single as CardAiError).message, contains('未配置'));
      expect(factoryCalls, 1);
    });
  });
}
