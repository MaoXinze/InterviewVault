import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/main.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: InterviewVaultApp()));
    await tester.pumpAndSettle();
  }

  testWidgets('底栏按 AGENTS 命名展示四 Tab：首页/面试/回顾/我的，中央为录音按钮', (
    tester,
  ) async {
    await pumpApp(tester);

    // 命名铁律：回顾（不是"卡片库"）
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('面试'), findsOneWidget);
    expect(find.text('回顾'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    expect(find.byKey(const Key('tab_record')), findsOneWidget);
  });

  testWidgets('点击"面试"Tab 切换到面试分支页面', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('面试'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page_interviews')), findsOneWidget);
  });

  testWidgets('点击"回顾"Tab 切换到回顾分支页面', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('回顾'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page_review')), findsOneWidget);
  });

  testWidgets('点击中央录音按钮进入全屏录音页', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('tab_record')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page_record')), findsOneWidget);
    // 录音页不在底栏 Shell 内：返回后仍在分支页
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page_record')), findsNothing);
  });
}
