import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/main.dart';

import '../../helpers/pump_app.dart';

/// 开屏回归：浮现 → 自动退场；减弱动态效果直达终态。
///
/// 不走 pump_app（它按约定关闭开屏）。泵序用手动 pump 而非 pumpAndSettle：
/// 开屏活着时 settle 不收敛（连续调帧），手动 pump 到总时长后自然退场；
/// 体末 `drainAppTimers` 与 app_shell_test 同款纪律，卸载树并排空定时器。
void main() {
  Future<AppDatabase> pumpWithSplash(WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          keyStorageProvider.overrideWithValue(FakeKeyStorage()),
        ],
        child: const InterviewVaultApp(),
      ),
    );
    addTearDown(() => drainAppTimers(tester));
    return db;
  }

  testWidgets('开屏浮现 logo 与名字，播完整体退场', (tester) async {
    final db = await pumpWithSplash(tester);
    addTearDown(db.close);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('问渠'), findsOneWidget);

    // 中段：仍在展示
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('问渠'), findsOneWidget);

    // 超过 1.6s 总时长：开屏从树上移除，露出正常界面
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('问渠'), findsNothing);
    expect(find.byKey(const Key('page_home')), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('减弱动态效果：装饰性开屏整屏跳过，直达正常界面', (tester) async {
    // 模拟系统"减弱动态效果"（MaterialApp 自建 MediaQuery，须经 dispatcher 覆盖）
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      () => tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(),
    );
    final db = await pumpWithSplash(tester);
    addTearDown(db.close);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('问渠'), findsNothing);
    expect(find.byKey(const Key('page_home')), findsOneWidget);

    await drainAppTimers(tester);
  });
}
