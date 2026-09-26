import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/features/recording/recorder_service.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/data/secure/key_storage.dart';
import 'package:interview_vault/main.dart';
import 'package:mocktail/mocktail.dart';

/// 测试用 KeyStorage 桩：内存实现，不触碰平台通道。
class FakeKeyStorage extends Mock implements KeyStorage {
  final Map<String, String> store = {};

  @override
  Future<void> write(String provider, String key) async =>
      store['apikey.$provider'] = key;

  @override
  Future<String?> read(String provider) async => store['apikey.$provider'];

  @override
  Future<void> delete(String provider) async =>
      store.remove('apikey.$provider');

  @override
  Future<bool> has(String provider) async => store.containsKey('apikey.$provider');
}

/// 泵起完整 App（内存数据库 + 桩 KeyStorage），可注入自定义录音服务
/// 与音频文件清理桩。
Future<AppDatabase> pumpInterviewVaultApp(
  WidgetTester tester, {
  RecorderService? recorder,
  Future<void> Function(String?)? audioFileCleaner,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        keyStorageProvider.overrideWithValue(FakeKeyStorage()),
        if (recorder != null) recorderServiceProvider.overrideWithValue(recorder),
        if (audioFileCleaner != null)
          audioFileCleanerProvider.overrideWithValue(audioFileCleaner),
      ],
      child: const InterviewVaultApp(),
    ),
  );
  await tester.pumpAndSettle();
  // 断言失败中断测试时 tearDown 仍会执行本排空，
  // 避免挂起的 Timer 拖垮同文件后续用例
  addTearDown(() => drainAppTimers(tester));
  return db;
}

/// 测试结束前在 fake-async 内卸载组件树并排空 Riverpod vsync 的
/// Duration.zero 定时器，避免 "A Timer is still pending" 校验失败。
///
/// 背景：riverpod 3.4 的 ProviderScope 用 Timer(Duration.zero) 调度
/// provider 刷新/销毁；测试体结束后这些定时器已无机会执行。
Future<void> drainAppTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}
