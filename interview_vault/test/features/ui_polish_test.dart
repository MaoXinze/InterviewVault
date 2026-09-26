import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';

import '../helpers/pump_app.dart';

/// W1.5 UI 打磨的动效与交互回归测试。
void main() {
  testWidgets('主题圆形扩散：切换后开关翻转、遮罩移除', (tester) async {
    final db = await pumpInterviewVaultApp(tester);
    addTearDown(db.close);

    await tester.tap(find.byKey(const Key('tab_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_dark_mode')));
    await tester.pumpAndSettle();

    final sw = tester.widget<SwitchListTile>(
      find.byKey(const Key('settings_dark_mode')),
    );
    expect(sw.value, isFalse);
    // 揭示完成后旧帧遮罩必须移除
    expect(find.byType(RawImage), findsNothing);

    await drainAppTimers(tester);
  });

  testWidgets('回顾标签筛选：按标签过滤，"全部"恢复', (tester) async {
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
        tags: Value(encodeCardTags(['亮点'])),
      ),
    );
    await db.flashcardsDao.insertOne(
      FlashcardsCompanion.insert(
        id: 'fc-2',
        interviewId: 'iv-root',
        question: '简述 Flutter 三棵树',
        tags: Value(encodeCardTags(['失误'])),
      ),
    );
    await tester.tap(find.byKey(const Key('tab_review')));
    await tester.pumpAndSettle();
    expect(find.text('什么是洋葱模型？'), findsOneWidget);
    expect(find.text('简述 Flutter 三棵树'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tag_chip_亮点')));
    await tester.pumpAndSettle();
    expect(find.text('什么是洋葱模型？'), findsOneWidget);
    expect(find.text('简述 Flutter 三棵树'), findsNothing);

    await tester.tap(find.byKey(const Key('tag_chip_全部')));
    await tester.pumpAndSettle();
    expect(find.text('简述 Flutter 三棵树'), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('面试弧线删除：菜单触发 → 确认 → 数据真删', (tester) async {
    final db = await pumpInterviewVaultApp(tester);
    addTearDown(db.close);

    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: 'iv-1',
        company: Value('字节跳动'),
      ),
    );
    await tester.tap(find.byKey(const Key('tab_interviews')));
    await tester.pumpAndSettle();
    expect(find.text('字节跳动'), findsOneWidget);

    await tester.tap(find.byKey(const Key('menu_iv-1')));
    await tester.pumpAndSettle();
    expect(find.text('删除这场面试？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(await db.interviewsDao.getById('iv-1'), isNull);
    expect(find.text('还没有面试记录'), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('隐私政策：第一节默认展开，其余点击展开', (tester) async {
    final db = await pumpInterviewVaultApp(tester);
    addTearDown(db.close);

    await tester.tap(find.byKey(const Key('tab_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();

    expect(find.textContaining('不上传、不遥测'), findsOneWidget);
    // 收起的内容被裁剪，不可点击
    final collapsed = find.textContaining('不经手任何中转');
    expect(collapsed.hitTestable(), findsNothing);
    await tester.tap(find.text('API Key 安全'));
    await tester.pumpAndSettle();
    expect(collapsed.hitTestable(), findsOneWidget);

    await drainAppTimers(tester);
  });
}
