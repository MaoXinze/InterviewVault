import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/core/router.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/mock/mock_interview_service.dart';
import 'package:interview_vault/features/mock/presentation/mock_session_page.dart';
import 'package:interview_vault/features/mock/presentation/mock_setup_page.dart';

import '../../helpers/pump_app.dart';

/// 手写桩：记录调用并回放预设结果（比 mocktail 直观）。
class _FakeMockService implements MockInterviewService {
  _FakeMockService();

  static const questions = ['第一题：介绍项目经历', '第二题：谈谈状态管理'];

  @override
  // 页面测试桩不触库；引用一律走被覆盖的 appDatabaseProvider
  AppDatabase get db => throw UnimplementedError();

  int generateCalls = 0;
  String? capturedPosition;
  String? capturedResume;
  String? capturedJd;
  final List<String> feedbackQuestions = [];
  final List<String> feedbackAnswers = [];

  /// 每次 generateFeedback 新建一个 controller（单订阅流不可复用），
  /// 测试按提交次序取 [feedbackControllers] 的末位投递事件。
  final List<StreamController<MockFeedbackEvent>> feedbackControllers = [];

  int persistCalls = 0;
  String? capturedPersistPosition;
  List<MockQa>? capturedQas;
  String persistId = 'iv-mock-1';
  Object? persistError;

  @override
  Future<List<String>> generateQuestions({
    required String position,
    String resume = '',
    String jd = '',
  }) async {
    generateCalls++;
    capturedPosition = position;
    capturedResume = resume;
    capturedJd = jd;
    return questions;
  }

  @override
  Stream<MockFeedbackEvent> generateFeedback({
    required String question,
    required String answer,
    String position = '',
    String resume = '',
  }) {
    feedbackQuestions.add(question);
    feedbackAnswers.add(answer);
    final controller = StreamController<MockFeedbackEvent>();
    feedbackControllers.add(controller);
    return controller.stream;
  }

  @override
  Future<String> persistSession({
    required String position,
    required List<MockQa> qas,
  }) async {
    persistCalls++;
    capturedPersistPosition = position;
    capturedQas = qas;
    if (persistError != null) throw persistError!;
    return persistId;
  }
}

/// 页面独立路由：/mock 与 /mock/session 互跳 + 落库跳转的桩目标。
GoRouter _testRouter({
  Future<String?> Function()? resumeImporter,
}) {
  return GoRouter(
    initialLocation: '/mock',
    routes: [
      GoRoute(
        path: '/mock',
        builder: (_, _) =>
            MockSetupPage(resumeImporter: resumeImporter),
      ),
      GoRoute(
        path: '/mock/session',
        builder: (_, state) =>
            MockSessionPage(plan: state.extra as MockSessionPlan),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(key: Key('stub_home')),
      ),
      GoRoute(
        path: '/interviews/:id',
        builder: (_, _) => const Scaffold(key: Key('stub_detail')),
      ),
    ],
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  /// 泵起配置页 + 会话页的独立路由环境。
  Future<GoRouter> pumpMockFlow(
    WidgetTester tester, {
    _FakeMockService? service,
    Future<String?> Function()? resumeImporter,
  }) async {
    final svc = service ?? _FakeMockService();
    final router = _testRouter(resumeImporter: resumeImporter);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mockInterviewServiceProvider.overrideWithValue(svc),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => drainAppTimers(tester));
    return router;
  }

  group('模拟面试配置页', () {
    testWidgets('岗位为空时提示且不出题', (tester) async {
      final service = _FakeMockService();
      await pumpMockFlow(tester, service: service);

      // 头图与三个输入框之下，CTA 在小视口可折叠进滚动区：先滚到再点（真实用户同款路径）
      await tester.ensureVisible(find.byKey(const Key('btn_generate_questions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_generate_questions')));
      await tester.pump();

      expect(find.text('请先填写岗位方向'), findsOneWidget);
      expect(service.generateCalls, 0);
      await drainAppTimers(tester);
    });

    testWidgets('填写岗位/简历/JD 后出题并进入会话页', (tester) async {
      final service = _FakeMockService();
      await pumpMockFlow(tester, service: service);

      await tester.enterText(
          find.byKey(const Key('mock_position_field')), '客户端工程师');
      await tester.enterText(
          find.byKey(const Key('mock_resume_field')), '三年 Flutter 经验');
      await tester.enterText(find.byKey(const Key('mock_jd_field')), '负责 App 架构');
      // 头图与三个输入框之下，CTA 在小视口可折叠进滚动区：先滚到再点（真实用户同款路径）
      await tester.ensureVisible(find.byKey(const Key('btn_generate_questions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_generate_questions')));
      await tester.pumpAndSettle();

      expect(service.generateCalls, 1);
      expect(service.capturedPosition, '客户端工程师');
      expect(service.capturedResume, '三年 Flutter 经验');
      expect(service.capturedJd, '负责 App 架构');
      expect(find.byKey(const Key('page_mock_session')), findsOneWidget);
      expect(find.text('第一题：介绍项目经历'), findsOneWidget);
      expect(find.text('模拟面试 · 1 / 2'), findsOneWidget);

      await drainAppTimers(tester);
    });

    testWidgets('导入 PDF 简历：提取文字填入简历栏', (tester) async {
      await pumpMockFlow(
        tester,
        resumeImporter: () async => '导入的简历正文内容',
      );

      await tester.tap(find.byKey(const Key('btn_import_resume')));
      await tester.pumpAndSettle();

      expect(find.text('已导入简历（9 字）'), findsOneWidget);
      final field = tester.widget<TextField>(
          find.byKey(const Key('mock_resume_field')));
      expect(field.controller!.text, '导入的简历正文内容');
      await drainAppTimers(tester);
    });

    testWidgets('导入 PDF 失败：提示改用粘贴文字', (tester) async {
      await pumpMockFlow(
        tester,
        resumeImporter: () async =>
            throw const FormatException('该 PDF 提取不到文字（可能是图片扫描件），请改用粘贴文字'),
      );

      await tester.tap(find.byKey(const Key('btn_import_resume')));
      await tester.pumpAndSettle();

      expect(find.textContaining('改用粘贴文字'), findsOneWidget);
      await drainAppTimers(tester);
    });
  });

  group('模拟面试会话页', () {
    Future<void> pumpSession(
      WidgetTester tester, {
      required _FakeMockService service,
    }) async {
      final router = await pumpMockFlow(tester, service: service);
      router.push(
        '/mock/session',
        extra: const MockSessionPlan(
          position: '客户端工程师',
          resume: '三年 Flutter 经验',
          jd: '',
          questions: ['第一题：介绍项目经历', '第二题：谈谈状态管理'],
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('空作答提交给提示且不请求反馈', (tester) async {
      final service = _FakeMockService();
      await pumpSession(tester, service: service);

      await tester.tap(find.byKey(const Key('btn_submit_answer')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('先写下你的回答，或跳过此题'), findsOneWidget);
      expect(service.feedbackQuestions, isEmpty);
      await drainAppTimers(tester);
    });

    testWidgets('提交作答：反馈流式增量渲染，完成后推进下一题', (tester) async {
      final service = _FakeMockService();
      await pumpSession(tester, service: service);

      await tester.enterText(
          find.byKey(const Key('mock_answer_field')), '我做过直播秒杀改造');
      await tester.tap(find.byKey(const Key('btn_submit_answer')));
      await tester.pump(const Duration(milliseconds: 50));
      final feedback = service.feedbackControllers.single;

      feedback.add(const MockFeedbackDelta('【优点】'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('mock_feedback_text')), findsOneWidget);
      expect(find.textContaining('【优点】'), findsOneWidget);
      // 流未完成时不出现推进按钮
      expect(find.byKey(const Key('btn_next_question')), findsNothing);

      feedback.add(const MockFeedbackDelta('表达清晰'));
      feedback.add(const MockFeedbackDone('【优点】表达清晰'));
      await tester.pumpAndSettle();

      expect(find.textContaining('【优点】表达清晰'), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_next_question')));
      await tester.pumpAndSettle();

      expect(find.text('第二题：谈谈状态管理'), findsOneWidget);
      expect(find.text('模拟面试 · 2 / 2'), findsOneWidget);
      // 回答框清空
      expect(
        tester.widget<TextField>(find.byKey(const Key('mock_answer_field')))
            .controller!
            .text,
        isEmpty,
      );

      await feedback.close();
      await drainAppTimers(tester);
    });

    testWidgets('跳过此题：直接推进且不请求反馈', (tester) async {
      final service = _FakeMockService();
      await pumpSession(tester, service: service);

      await tester.tap(find.byKey(const Key('btn_skip_question')));
      await tester.pumpAndSettle();

      expect(find.text('第二题：谈谈状态管理'), findsOneWidget);
      expect(service.feedbackQuestions, isEmpty);

      await drainAppTimers(tester);
    });

    testWidgets('反馈中断：保留已收部分内容，仍可推进', (tester) async {
      final service = _FakeMockService();
      await pumpSession(tester, service: service);

      await tester.enterText(
          find.byKey(const Key('mock_answer_field')), '回答内容');
      await tester.tap(find.byKey(const Key('btn_submit_answer')));
      await tester.pump(const Duration(milliseconds: 50));
      final feedback = service.feedbackControllers.single;

      feedback.add(const MockFeedbackDelta('【优点】只有一半'));
      feedback.add(const MockFeedbackError('生成中断，已保留部分内容：网络断开'));
      await tester.pumpAndSettle();

      expect(find.textContaining('【优点】只有一半'), findsOneWidget);
      expect(find.textContaining('生成中断'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_next_question')));
      await tester.pumpAndSettle();
      expect(find.text('第二题：谈谈状态管理'), findsOneWidget);

      await feedback.close();
      await drainAppTimers(tester);
    });

    testWidgets('全部完成：落库并跳到面试详情', (tester) async {
      final service = _FakeMockService();
      await pumpSession(tester, service: service);

      // 第一题：作答 → 反馈 → 下一题
      await tester.enterText(
          find.byKey(const Key('mock_answer_field')), '回答一');
      await tester.tap(find.byKey(const Key('btn_submit_answer')));
      await tester.pump(const Duration(milliseconds: 50));
      service.feedbackControllers.last
          .add(const MockFeedbackDone('【优点】反馈一'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_next_question')));
      await tester.pumpAndSettle();

      // 第二题（最后一题）：作答 → 反馈 → 完成并生成卡片
      await tester.enterText(
          find.byKey(const Key('mock_answer_field')), '回答二');
      await tester.tap(find.byKey(const Key('btn_submit_answer')));
      await tester.pump(const Duration(milliseconds: 50));
      service.feedbackControllers.last
          .add(const MockFeedbackDone('【优点】反馈二'));
      await tester.pumpAndSettle();
      expect(find.text('完成并生成卡片'), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_next_question')));
      await tester.pumpAndSettle();

      expect(service.persistCalls, 1);
      expect(service.capturedPersistPosition, '客户端工程师');
      final qas = service.capturedQas!;
      expect(qas, hasLength(2));
      expect(qas[0].answer, '回答一');
      expect(qas[0].feedback, '【优点】反馈一');
      expect(qas[1].answer, '回答二');
      // 落库成功后跳转：home 复位 + 详情页
      expect(find.byKey(const Key('stub_detail')), findsOneWidget);
      expect(find.textContaining('已生成 2 张问题卡片'), findsOneWidget);

      for (final c in service.feedbackControllers) {
        await c.close();
      }
      await drainAppTimers(tester);
    });

    testWidgets('有进度返回：确认放弃后退出', (tester) async {
      final service = _FakeMockService();
      await pumpSession(tester, service: service);

      await tester.enterText(
          find.byKey(const Key('mock_answer_field')), '已写的回答');
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mock_abandon_dialog')), findsOneWidget);
      await tester.tap(find.text('放弃退出'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('page_mock_setup')), findsOneWidget);
      expect(service.persistCalls, 0);

      await drainAppTimers(tester);
    });

    testWidgets('无进度返回：直接退出不弹确认', (tester) async {
      final service = _FakeMockService();
      await pumpSession(tester, service: service);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mock_abandon_dialog')), findsNothing);
      expect(find.byKey(const Key('page_mock_setup')), findsOneWidget);

      await drainAppTimers(tester);
    });
  });

  group('首页入口与 Key 引导', () {
    testWidgets('未配置 AI：先给 Key 引导，去配置进 API 配置页', (tester) async {
      await pumpInterviewVaultApp(tester);

      appRouter.go('/home');
      await tester.pumpAndSettle();
      await tester.tap(find.text('模拟面试'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mock_key_guide')), findsOneWidget);
      await tester.tap(find.text('去配置'));
      await tester.pumpAndSettle();

      expect(find.text('AI 服务配置'), findsOneWidget);
      expect(find.byKey(const Key('page_mock_setup')), findsNothing);

      appRouter.go('/home');
      await tester.pumpAndSettle();
      await drainAppTimers(tester);
    });

    testWidgets('已配置 AI：直接进入模拟面试配置页', (tester) async {
      final keys = FakeKeyStorage();
      await keys.write('openai', 'sk-test');
      final db = await pumpInterviewVaultApp(tester, keyStorage: keys);
      await db.aiConfigsDao.upsert(
        AiConfigsCompanion.insert(
          id: 'cfg-openai',
          provider: 'openai',
          modelName: const Value('gpt-test'),
          baseUrl: const Value('https://api.test.com'),
        ),
      );
      await db.aiConfigsDao.setActive('cfg-openai');

      appRouter.go('/home');
      await tester.pumpAndSettle();
      await tester.tap(find.text('模拟面试'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mock_key_guide')), findsNothing);
      expect(find.byKey(const Key('page_mock_setup')), findsOneWidget);

      appRouter.go('/home');
      await tester.pumpAndSettle();
      await drainAppTimers(tester);
    });
  });
}
