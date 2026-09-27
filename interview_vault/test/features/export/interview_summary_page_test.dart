import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/core/router.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/export/markdown_export_service.dart';
import 'package:interview_vault/features/export/presentation/interview_summary_page.dart';

import '../../helpers/pump_app.dart';

/// 页面级桩：exportInterview 内存化——落盘行为由
/// markdown_export_service_test（纯 test，真实异步）覆盖，
/// widget 测试跑在 FakeAsync zone，真实文件 IO 永远不会完成。
/// db 仅满足父类构造：exportInterview 已被覆盖，不会触达。
class _StubExportService extends MarkdownExportService {
  _StubExportService(AppDatabase db, {this.error})
      : super(db: db, documentsPathResolver: () async => '/stub');

  /// 非 null 时 exportInterview 抛出
  final Object? error;

  int calls = 0;
  String? lastInterviewId;

  @override
  Future<ExportedMarkdown> exportInterview(String interviewId) async {
    calls++;
    lastInterviewId = interviewId;
    if (error != null) throw error!;
    return const ExportedMarkdown(
      path: '/stub/exports/面试复盘-字节跳动.md',
      fileName: '面试复盘-字节跳动.md',
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  Future<void> seedSummarizableInterview({String status = 'transcribed'}) async {
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: 'iv-1',
        company: const Value('字节跳动'),
        position: const Value('后端工程师'),
        round: const Value('二面'),
        interviewDate: const Value('2026-09-27T10:00:00.000'),
        durationSeconds: const Value(1925),
        status: Value(status),
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
          ),
        );
    await annotation('an-1', 'seg-1', 'question');
    await annotation('an-2', 'seg-2', 'highlight', note: '项目难点讲清了');
    await annotation('an-3', 'seg-2', 'improvement', note: '超时没控制好');
    await annotation('an-4', 'seg-1', 'custom', customTagName: '心态平稳');

    Future<void> card(
      String id, {
      required String question,
      double? start,
      List<String> tags = const ['问题'],
    }) =>
        db.flashcardsDao.insertOne(
          FlashcardsCompanion.insert(
            id: id,
            interviewId: 'iv-1',
            question: question,
            tags: Value('["${tags.join('","')}"]'),
            sourceStartTime: Value(start),
          ),
        );
    await card('card-3', question: '你有什么想问我的吗');
    await card('card-1', question: '先自我介绍一下', start: 0,
        tags: const ['问题', '回答']);
    await card('card-2', question: '讲讲 Flutter 的事件循环', start: 120);
  }

  /// 直泵总结页（同详情页测试模式：绕开全局 appRouter，
  /// 入口→路由链路由"详情页总结入口"组的全 App 用例单独覆盖）
  Future<void> pumpSummary(
    WidgetTester tester, {
    MarkdownExportService? service,
    Future<void> Function(String path)? sharer,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          if (service != null)
            markdownExportServiceProvider.overrideWithValue(service),
          if (sharer != null) markdownSharerProvider.overrideWithValue(sharer),
        ],
        child: const MaterialApp(
          home: InterviewSummaryPage(interviewId: 'iv-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => drainAppTimers(tester));
  }

  /// appRouter 是全局单例：前序用例的 push/branch 会残留到下一个用例，
  /// 开头强制回首页、结尾复位，保证任意顺序运行都成立（同卡片详情页测试）
  Future<void> resetToHome(WidgetTester tester) async {
    appRouter.go('/home');
    await tester.pumpAndSettle();
  }

  group('详情页总结入口（全 App）', () {
    testWidgets('transcribed 详情页有入口，点击进入总结页', (tester) async {
      db = await pumpInterviewVaultApp(tester);
      addTearDown(db.close);
      await resetToHome(tester);
      await seedSummarizableInterview();

      await tester.tap(find.byKey(const Key('tab_interviews')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('字节跳动'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_open_summary')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_open_summary')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('page_interview_summary')), findsOneWidget);
      expect(find.text('面试总结'), findsOneWidget);

      // 继续链路：总结页点卡片 → 卡片详情页
      await tester.tap(find.text('先自我介绍一下'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page_card_detail')), findsOneWidget);
      await resetToHome(tester);
      await drainAppTimers(tester);
    });

    testWidgets('draft 详情页无总结入口（没有可总结的内容）', (tester) async {
      db = await pumpInterviewVaultApp(tester);
      addTearDown(db.close);
      await resetToHome(tester);
      await seedSummarizableInterview(status: 'draft');

      await tester.tap(find.byKey(const Key('tab_interviews')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('字节跳动'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_open_summary')), findsNothing);
      await resetToHome(tester);
      await drainAppTimers(tester);
    });
  });

  group('总结页渲染', () {
    testWidgets('面试信息 + 标注统计（系统标签序在前）+ 卡片列表 + 录音概要',
        (tester) async {
      await seedSummarizableInterview();
      await pumpSummary(tester);

      // 折叠线上区块
      expect(find.text('面试信息'), findsOneWidget);
      expect(find.text('标注统计'), findsOneWidget);
      expect(find.text('问题卡片'), findsOneWidget);

      // 面试信息：公司 · 岗位 · 轮次 / 日期 · 时长 · 状态
      expect(find.text('字节跳动 · 后端工程师 · 二面'), findsOneWidget);
      expect(find.textContaining('2026-09-27'), findsWidgets);
      expect(find.textContaining('32:05'), findsWidgets);

      // 标注统计：按系统标签固定顺序，自定义殿后，计数正确
      expect(find.text('问题 · 1'), findsOneWidget);
      expect(find.text('亮点 · 1'), findsOneWidget);
      expect(find.text('待改进 · 1'), findsOneWidget);
      expect(find.text('心态平稳 · 1'), findsOneWidget);

      // 卡片列表：时间轴序（null 殿后）
      expect(find.text('先自我介绍一下'), findsOneWidget);
      expect(find.text('讲讲 Flutter 的事件循环'), findsOneWidget);
      expect(find.text('你有什么想问我的吗'), findsOneWidget);

      // 录音概要在折叠线下：测试视口 600px，ListView 懒挂载，滚动后断言
      await tester.scrollUntilVisible(
        find.text('录音概要'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('音频'), findsOneWidget);
      expect(find.text('无'), findsOneWidget);
      expect(find.text('4 段'), findsOneWidget);
      final wordCount = (await db.segmentsDao.getByInterview('iv-1'))
          .fold<int>(0, (n, s) => n + s.content.length);
      expect(find.text('$wordCount 字'), findsOneWidget);
      await drainAppTimers(tester);
    });

    testWidgets('无卡片时显示空态引导', (tester) async {
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-1',
          company: const Value('美团'),
          status: const Value('transcribed'),
        ),
      );
      await db.segmentsDao.insertOne(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-1',
          interviewId: 'iv-1',
          startTime: 0,
          endTime: 10,
          content: '你好',
        ),
      );
      await pumpSummary(tester);

      // 空态区块在折叠线下：滚动后断言
      expect(find.text('暂无标注'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('还没有问题卡片'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('还没有问题卡片'), findsOneWidget);
      expect(
        find.textContaining('标注成「问题」标签'),
        findsOneWidget,
      );
      // riverpod 的 Timer(Duration.zero) 需在体内排空（直泵模式同详情页测试）
      await drainAppTimers(tester);
    });
  });

  group('导出 Markdown', () {
    late AppDatabase stubDb;

    setUp(() {
      stubDb = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() async => stubDb.close());

    testWidgets('导出按钮：调服务写文件 → 触发分享 → snackbar 确认', (tester) async {
      await seedSummarizableInterview();
      final shared = <String>[];
      final service = _StubExportService(stubDb);
      await pumpSummary(
        tester,
        service: service,
        sharer: (path) async => shared.add(path),
      );

      await tester.tap(find.byKey(const Key('btn_export_markdown')));
      await tester.pumpAndSettle();

      expect(service.calls, 1);
      expect(service.lastInterviewId, 'iv-1');
      expect(shared, ['/stub/exports/面试复盘-字节跳动.md']);
      expect(find.text('已导出 面试复盘-字节跳动.md'), findsOneWidget);

      // SnackBar 的 4s 自动消失 Timer 会挂到测试结束，
      // 推进假时钟让它走完（否则 pending-timer 断言失败）
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await drainAppTimers(tester);
    });

    testWidgets('导出失败：snackbar 报错且不触发分享', (tester) async {
      await seedSummarizableInterview();
      final shared = <String>[];
      final service = _StubExportService(
        stubDb,
        error: Exception('磁盘写入失败'),
      );
      await pumpSummary(
        tester,
        service: service,
        sharer: (path) async => shared.add(path),
      );

      await tester.tap(find.byKey(const Key('btn_export_markdown')));
      await tester.pumpAndSettle();

      expect(service.calls, 1);
      expect(shared, isEmpty);
      expect(find.textContaining('导出失败'), findsOneWidget);

      // 同上：排空 SnackBar Timer
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await drainAppTimers(tester);
    });
  });
}
