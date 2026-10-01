import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/core/router.dart';
import 'package:interview_vault/core/widgets/illustration.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/flashcards/flashcard_service.dart';
import 'package:interview_vault/features/flashcards/presentation/flashcard_detail_page.dart';
import 'package:interview_vault/network/llm_client.dart';
import '../../helpers/pump_app.dart';

/// dio 打桩：可编程 SSE 响应（与 llm_client_test 同模式）
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.responder);

  final ResponseBody Function(RequestOptions options) responder;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      responder(options);
}

void main() {
  late AppDatabase db;
  FlashcardService? serviceOverride;
  Future<LlmClient?>? nextChatClient;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    nextChatClient = null;
    serviceOverride = FlashcardService(
      db: db,
      chatClientFactory: () async => nextChatClient,
    );
  });
  tearDown(() => db.close());

  Future<void> seedCardData() async {
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: 'iv-1',
        company: const Value('字节跳动'),
        position: const Value('客户端工程师'),
        round: const Value('一面'),
        status: const Value('annotated'),
      ),
    );
    await db.segmentsDao.insertOne(
      TranscriptSegmentsCompanion.insert(
        id: 'seg-q',
        interviewId: 'iv-1',
        startTime: 0,
        endTime: 4,
        content: '请介绍你最有挑战的项目',
      ),
    );
    await db.segmentsDao.insertOne(
      TranscriptSegmentsCompanion.insert(
        id: 'seg-a',
        interviewId: 'iv-1',
        startTime: 4,
        endTime: 35,
        content: '我负责直播秒杀的链路改造',
      ),
    );
    await db.annotationsDao.insertOne(
      AnnotationsCompanion.insert(
        id: 'an-q',
        interviewId: 'iv-1',
        segmentId: const Value('seg-q'),
        tag: 'question',
      ),
    );
    await db.annotationsDao.insertOne(
      AnnotationsCompanion.insert(
        id: 'an-h',
        interviewId: 'iv-1',
        segmentId: const Value('seg-a'),
        tag: 'highlight',
        note: const Value('这段讲得有数据支撑'),
      ),
    );
    await db.flashcardsDao.insertOne(
      FlashcardsCompanion.insert(
        id: 'fc-1',
        interviewId: 'iv-1',
        question: '请介绍你最有挑战的项目',
        myAnswer: const Value('我负责直播秒杀的链路改造'),
        tags: const Value('["问题","亮点"]'),
        sourceStartTime: const Value(0.0),
        sourceEndTime: const Value(35.0),
      ),
    );
  }

  Future<void> pumpCardDetail(WidgetTester tester) async {
    // 完整种子内容超出默认 600px 视口：拉高测试视口，
    // 避免 ListView 懒挂载导致 AI 区块（最后一节）不在元素树里
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          flashcardServiceProvider.overrideWithValue(serviceOverride!),
        ],
        child: const MaterialApp(
          home: FlashcardDetailPage(cardId: 'fc-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => drainAppTimers(tester));
  }

  group('卡片详情展示', () {
    testWidgets('正面/背面/标签/来源/时间锚点齐全', (tester) async {
      await seedCardData();
      await pumpCardDetail(tester);

      expect(find.byKey(const Key('page_card_detail')), findsOneWidget);
      expect(find.text('请介绍你最有挑战的项目'), findsOneWidget);
      expect(find.text('我负责直播秒杀的链路改造'), findsOneWidget);
      expect(find.text('字节跳动 · 客户端工程师'), findsOneWidget);
      // 时间锚点（formatClock）
      expect(find.text('00:00 - 00:35'), findsOneWidget);
      // 来源范围内的标注（问题段 + 回答段），带笔记
      expect(find.byKey(const Key('card_annotation_an-q')), findsOneWidget);
      expect(find.byKey(const Key('card_annotation_an-h')), findsOneWidget);
      expect(find.text('这段讲得有数据支撑'), findsOneWidget);
      await drainAppTimers(tester);
    });

    testWidgets('问题/回答/AI 思路三区块带鎏金水印插画', (tester) async {
      await seedCardData();
      await pumpCardDetail(tester);

      // 问题水印 + 回答水印 + AI 区块水印 + AI 空态提示行灯泡
      expect(find.byType(CardIllustration), findsNWidgets(4));
      await drainAppTimers(tester);
    });

    testWidgets('编辑问题：对话框保存后入库并刷新 UI', (tester) async {
      await seedCardData();
      await pumpCardDetail(tester);

      await tester.tap(find.byKey(const Key('btn_edit_question')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('question_edit_field')),
        '讲讲你最有挑战的项目和你的角色',
      );
      await tester.tap(find.byKey(const Key('question_edit_save')));
      await tester.pumpAndSettle();

      final card = await db.flashcardsDao.getById('fc-1');
      expect(card!.question, '讲讲你最有挑战的项目和你的角色');
      expect(find.text('讲讲你最有挑战的项目和你的角色'), findsOneWidget);
      await drainAppTimers(tester);
    });

    testWidgets('编辑我的回答：对话框保存后入库', (tester) async {
      await seedCardData();
      await pumpCardDetail(tester);

      await tester.tap(find.byKey(const Key('btn_edit_answer')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('answer_edit_field')),
        '（手工整理）秒杀链路改造：限流 + 热点缓存',
      );
      await tester.tap(find.byKey(const Key('answer_edit_save')));
      await tester.pumpAndSettle();

      final card = await db.flashcardsDao.getById('fc-1');
      expect(card!.myAnswer, '（手工整理）秒杀链路改造：限流 + 热点缓存');
      await drainAppTimers(tester);
    });
  });

  group('AI 参考思路', () {
    testWidgets('流式生成：增量渲染到界面，完成后持久化', (tester) async {
      await seedCardData();
      final controller = StreamController<List<int>>();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'))
        ..httpClientAdapter = _CapturingAdapter(
          (_) => ResponseBody(controller.stream.cast<Uint8List>(), 200),
        );
      nextChatClient = Future.value(
        LlmClient(
          endpoint: const AiEndpoint(
            providerId: 'openai',
            baseUrl: 'https://api.example.com/v1',
            modelName: 'test-model',
          ),
          apiKey: 'sk-test',
          dio: dio,
        ),
      );
      await pumpCardDetail(tester);

      await tester.tap(find.byKey(const Key('btn_gen_ai_reference')));
      await tester.pump();
      controller.add(utf8.encode(
          'data: {"choices":[{"delta":{"content":"先讲背景"}}]}\n\n'));
      await tester.pump(const Duration(milliseconds: 50));

      // 增量可见（流式渲染而非一次性出现）
      expect(find.textContaining('先讲背景'), findsOneWidget);

      controller.add(utf8.encode(
          'data: {"choices":[{"delta":{"content":"，再讲权衡"}}]}\n\n'));
      await controller.close();
      await tester.pumpAndSettle();

      final card = await db.flashcardsDao.getById('fc-1');
      expect(card!.aiReference, '先讲背景，再讲权衡');
      expect(find.text('先讲背景，再讲权衡'), findsOneWidget);
      await drainAppTimers(tester);
    });

    testWidgets('未配置 AI：显示引导文案而非请求', (tester) async {
      await seedCardData();
      nextChatClient = null;
      await pumpCardDetail(tester);

      await tester.tap(find.byKey(const Key('btn_gen_ai_reference')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai_error_text')), findsOneWidget);
      expect(find.textContaining('未配置'), findsOneWidget);
      // 数据库无写入
      final card = await db.flashcardsDao.getById('fc-1');
      expect(card!.aiReference, isNull);
      await drainAppTimers(tester);
    });

    testWidgets('生成中断：保留部分内容并显示错误', (tester) async {
      await seedCardData();
      final controller = StreamController<List<int>>();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'))
        ..httpClientAdapter = _CapturingAdapter(
          (_) => ResponseBody(controller.stream.cast<Uint8List>(), 200),
        );
      nextChatClient = Future.value(
        LlmClient(
          endpoint: const AiEndpoint(
            providerId: 'openai',
            baseUrl: 'https://api.example.com/v1',
            modelName: 'test-model',
          ),
          apiKey: 'sk-test',
          dio: dio,
        ),
      );
      await pumpCardDetail(tester);

      await tester.tap(find.byKey(const Key('btn_gen_ai_reference')));
      await tester.pump();
      controller.add(utf8.encode(
          'data: {"choices":[{"delta":{"content":"只有一半"}}]}\n\n'));
      await tester.pump(const Duration(milliseconds: 50));
      controller.addError(const SocketException('连接中断'));
      await controller.close();
      await tester.pumpAndSettle();

      final card = await db.flashcardsDao.getById('fc-1');
      expect(card!.aiReference, '只有一半');
      expect(find.textContaining('生成中断'), findsOneWidget);
      await drainAppTimers(tester);
    });
  });

  group('删除与导航（全 App）', () {
    // appRouter 是全局单例：前序用例的 push/branch 会残留到下一个用例，
    // 开头强制回首页、结尾复位，保证任意顺序运行都成立
    Future<void> resetToHome(WidgetTester tester) async {
      appRouter.go('/home');
      await tester.pumpAndSettle();
    }

    testWidgets('删除卡片：确认后真删并返回列表', (tester) async {
      final db = await pumpInterviewVaultApp(tester);
      addTearDown(db.close);
      await resetToHome(tester);
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-1',
          company: const Value('字节跳动'),
        ),
      );
      await db.flashcardsDao.insertOne(
        FlashcardsCompanion.insert(
          id: 'fc-1',
          interviewId: 'iv-1',
          question: '请介绍你最有挑战的项目',
        ),
      );

      await tester.tap(find.byKey(const Key('tab_review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review_card_fc-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page_card_detail')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_delete_card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_confirm_delete_card')));
      await tester.pumpAndSettle();

      expect(await db.flashcardsDao.countAll(), 0);
      expect(find.byKey(const Key('page_card_detail')), findsNothing);
      await resetToHome(tester);
      await drainAppTimers(tester);
    });

    testWidgets('卡片来源「查看面试」跳转面试详情', (tester) async {
      final db = await pumpInterviewVaultApp(tester);
      addTearDown(db.close);
      await resetToHome(tester);
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-1',
          company: const Value('字节跳动'),
        ),
      );
      await db.flashcardsDao.insertOne(
        FlashcardsCompanion.insert(
          id: 'fc-1',
          interviewId: 'iv-1',
          question: '请介绍你最有挑战的项目',
        ),
      );

      await tester.tap(find.byKey(const Key('tab_review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review_card_fc-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_view_interview')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('page_interview_detail')), findsOneWidget);
      await resetToHome(tester);
      await drainAppTimers(tester);
    });

    testWidgets('标注弹层「存为卡片」→ snackbar 查看 → 卡片详情', (tester) async {
      final db = await pumpInterviewVaultApp(tester);
      addTearDown(db.close);
      await resetToHome(tester);
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-1',
          company: const Value('字节跳动'),
          status: const Value('transcribed'),
        ),
      );
      await db.segmentsDao.insertOne(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-q',
          interviewId: 'iv-1',
          startTime: 0,
          endTime: 4,
          content: '请介绍你最有挑战的项目',
        ),
      );
      await db.segmentsDao.insertOne(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-a',
          interviewId: 'iv-1',
          startTime: 4,
          endTime: 20,
          content: '我负责直播秒杀的链路改造',
        ),
      );

      await tester.tap(find.byKey(const Key('tab_interviews')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('字节跳动'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_annotate_seg-q')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag_chip_question')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_save_as_card')));
      await tester.pumpAndSettle();

      expect(find.text('已生成问题卡片'), findsOneWidget);
      final card = (await db.flashcardsDao.getAll()).single;
      expect(card.question, '请介绍你最有挑战的项目');
      expect(card.myAnswer, '我负责直播秒杀的链路改造');
      expect(decodeCardTags(card.tags), ['问题']);

      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page_card_detail')), findsOneWidget);
      expect(find.text('请介绍你最有挑战的项目'), findsOneWidget);
      await resetToHome(tester);
      await drainAppTimers(tester);
    });
  });
}
