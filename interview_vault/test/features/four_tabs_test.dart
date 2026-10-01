import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('首页：三个快捷入口 + "0 道题待回顾"', (tester) async {
    final db = await pumpInterviewVaultApp(tester);
    addTearDown(db.close);

    expect(find.text('新录音'), findsOneWidget);
    expect(find.text('导入音频'), findsOneWidget);
    expect(find.text('模拟面试'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('道题待回顾'), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('首页：插入卡片后待回顾数实时更新为 N', (tester) async {
    final db = await pumpInterviewVaultApp(tester);
    addTearDown(db.close);

    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(id: 'iv-root'),
    );
    await db.flashcardsDao.insertOne(
      FlashcardsCompanion.insert(
        id: 'fc-1',
        interviewId: 'iv-root',
        question: '什么是洋葱模型？',
      ),
    );
    await db.flashcardsDao.insertOne(
      FlashcardsCompanion.insert(
        id: 'fc-2',
        interviewId: 'iv-root',
        question: '简述 Flutter 三棵树',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.text('道题待回顾'), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('面试页：空状态提示，插入面试后显示公司名', (tester) async {
    final db = await pumpInterviewVaultApp(tester);
    addTearDown(db.close);

    await tester.tap(find.byKey(const Key('tab_interviews')));
    await tester.pumpAndSettle();
    expect(find.text('还没有面试记录'), findsOneWidget);
    // 空列表时搜索框不出现（避免"不知道搜什么"的困惑）
    expect(find.byKey(const Key('field_search')), findsNothing);

    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: 'iv-1',
        company: Value('字节跳动'),
        position: Value('客户端工程师'),
      ),
    );
    await tester.pumpAndSettle();

    final pageScope = find.byKey(const Key('page_interviews'));
    expect(
      find.descendant(of: pageScope, matching: find.text('字节跳动')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: pageScope, matching: find.textContaining('客户端工程师')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('field_search')), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('回顾页：卡片列表实时显示问题文本，"开始回顾"按钮存在', (tester) async {
    final db = await pumpInterviewVaultApp(tester);
    addTearDown(db.close);

    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(id: 'iv-root'),
    );
    await db.flashcardsDao.insertOne(
      FlashcardsCompanion.insert(
        id: 'fc-1',
        interviewId: 'iv-root',
        question: '什么是洋葱模型？',
      ),
    );
    await tester.tap(find.byKey(const Key('tab_review')));
    await tester.pumpAndSettle();

    expect(find.text('什么是洋葱模型？'), findsOneWidget);
    expect(find.text('开始回顾'), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('我的页：API 服务配置入口可进入配置页；深色模式开关默认关闭（默认亮色）', (tester) async {
    final db = await pumpInterviewVaultApp(tester);
    addTearDown(db.close);

    await tester.tap(find.byKey(const Key('tab_settings')));
    await tester.pumpAndSettle();

    expect(find.text('API 服务配置'), findsOneWidget);
    expect(find.byKey(const Key('settings_dark_mode')), findsOneWidget);
    final sw = tester.widget<SwitchListTile>(
      find.byKey(const Key('settings_dark_mode')),
    );
    // 默认亮色：开关（深色模式）默认关闭
    expect(sw.value, isFalse);

    await tester.tap(find.text('API 服务配置'));
    await tester.pumpAndSettle();
    expect(find.text('AI 服务配置'), findsOneWidget);

    await drainAppTimers(tester);
  });
}
