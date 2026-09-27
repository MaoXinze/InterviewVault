import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/core/router.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/interviews/presentation/daily_summary_page.dart';

import '../../helpers/pump_app.dart';

/// PRD 2.8 按日汇总：当天所有面试/录音的摘要视图（按日分组倒序）。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  /// 直泵（绕开全局 appRouter；入口链路由全 App 用例覆盖）
  Future<void> pumpDaily(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: DailySummaryPage()),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => drainAppTimers(tester));
  }

  group('按日汇总页', () {
    testWidgets('按日倒序分组：日期 + 场数 + 累计时长 + 当日面试列表', (tester) async {
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-1',
          company: const Value('字节跳动'),
          position: const Value('后端工程师'),
          interviewDate: const Value('2026-09-26T10:00:00.000'),
          durationSeconds: const Value(600),
          status: const Value('transcribed'),
        ),
      );
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-2',
          company: const Value('美团'),
          interviewDate: const Value('2026-09-27T14:00:00.000'),
          durationSeconds: const Value(1925),
          status: const Value('transcribed'),
        ),
      );
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-3',
          company: const Value('快手'),
          interviewDate: const Value('2026-09-27T09:00:00.000'),
          status: const Value('draft'),
        ),
      );
      await pumpDaily(tester);

      // 日期倒序：09-27 在前（当天 2 场，其一无时长计 0）；09-26 在后
      expect(find.text('2026-09-27'), findsOneWidget);
      expect(find.text('2 场 · 32:05'), findsOneWidget);
      expect(find.text('2026-09-26'), findsOneWidget);
      expect(find.text('1 场 · 10:00'), findsOneWidget);

      // 当日面试行（公司 · 岗位）
      expect(find.text('美团 · 未填岗位'), findsOneWidget);
      expect(find.text('快手 · 未填岗位'), findsOneWidget);
      expect(find.text('字节跳动 · 后端工程师'), findsOneWidget);

      // 排序断言：09-27 的标题在 09-26 之前出现
      final order27 = tester.getTopLeft(find.text('2026-09-27')).dy;
      final order26 = tester.getTopLeft(find.text('2026-09-26')).dy;
      expect(order27 < order26, isTrue);
      await drainAppTimers(tester);
    });

    testWidgets('空库显示引导空态', (tester) async {
      await pumpDaily(tester);

      expect(find.text('暂无面试记录'), findsOneWidget);
      expect(find.textContaining('录一场面试'), findsOneWidget);
      await drainAppTimers(tester);
    });
  });

  group('全 App 入口链路', () {
    testWidgets('首页今日汇总 → 按日汇总页 → 点面试进详情', (tester) async {
      final appDb = await pumpInterviewVaultApp(tester);
      addTearDown(appDb.close);
      appRouter.go('/home');
      await tester.pumpAndSettle();
      await appDb.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-1',
          company: const Value('字节跳动'),
          interviewDate: const Value('2026-09-27T14:00:00.000'),
          status: const Value('transcribed'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('今日汇总'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page_daily')), findsOneWidget);

      await tester.tap(find.text('字节跳动 · 未填岗位'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page_interview_detail')), findsOneWidget);
      appRouter.go('/home');
      await tester.pumpAndSettle();
      await drainAppTimers(tester);
    });
  });
}
