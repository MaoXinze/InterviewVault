import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('底栏按 AGENTS 命名展示四 Tab：首页/面试/回顾/我的，中央为录音按钮', (
    tester,
  ) async {
    await pumpInterviewVaultApp(tester);

    // 命名铁律：回顾（不是"卡片库"）
    expect(find.text('首页'), findsWidgets);
    expect(find.text('面试'), findsWidgets);
    expect(find.text('回顾'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    expect(find.byKey(const Key('tab_record')), findsOneWidget);
    expect(find.byKey(const Key('tab_home')), findsOneWidget);
    expect(find.byKey(const Key('tab_interviews')), findsOneWidget);
    expect(find.byKey(const Key('tab_review')), findsOneWidget);
    expect(find.byKey(const Key('tab_settings')), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('点击"面试"Tab 切换到面试分支页面', (tester) async {
    await pumpInterviewVaultApp(tester);

    await tester.tap(find.byKey(const Key('tab_interviews')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page_interviews')), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('点击"回顾"Tab 切换到回顾分支页面', (tester) async {
    await pumpInterviewVaultApp(tester);

    await tester.tap(find.byKey(const Key('tab_review')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page_review')), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('点击中央录音按钮进入全屏录音页', (tester) async {
    await pumpInterviewVaultApp(tester);

    await tester.tap(find.byKey(const Key('tab_record')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page_record')), findsOneWidget);
    // 录音页不在底栏 Shell 内：返回后仍在分支页
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page_record')), findsNothing);

    await drainAppTimers(tester);
  });
}
