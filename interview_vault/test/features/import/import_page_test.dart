import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/features/import/audio_import_service.dart';
import 'package:interview_vault/features/import/device_audio_service.dart';

import '../../helpers/pump_app.dart';

/// 页面级桩：pick/inspect/importFile 全部内存化。
/// 注意 widget 测试跑在 FakeAsync zone，真实文件 IO（File.copy）永远
/// 不会完成——落盘行为由 audio_import_service_test（纯 test，真实异步）
/// 覆盖，这里只验证页面流程与落库。
class _StubImportService extends AudioImportService {
  _StubImportService({
    this.pickResults = const [],
    this.inspectedDuration = const Duration(minutes: 3, seconds: 24),
  }) : super(
          picker: () async => null,
          durationProbe: (_) async => null,
          documentsPathResolver: () async => '/stub',
        );

  /// 每次 pick() 依次弹出一个结果；null 表示用户取消
  final List<PickedAudio?> pickResults;

  /// inspect() 返回的时长；null 模拟探测失败降级
  final Duration? inspectedDuration;

  int _pickIndex = 0;
  final List<PickedAudio> imported = [];

  @override
  Future<PickedAudio?> pick() async {
    if (_pickIndex >= pickResults.length) return null;
    return pickResults[_pickIndex++];
  }

  @override
  Future<ImportedAudioInfo> inspect(PickedAudio audio) async =>
      ImportedAudioInfo(
        source: audio,
        format: 'mp3',
        duration: inspectedDuration,
      );

  @override
  Future<String> importFile(PickedAudio audio) async {
    imported.add(audio);
    return '/stub/recordings/imports/interview_stored.mp3';
  }
}

DeviceAudio _deviceAudio(String title, {int sizeBytes = 1234567}) {
  return DeviceAudio(
    path: '/storage/emulated/0/Music/$title',
    title: title,
    sizeBytes: sizeBytes,
    album: '面试录音',
    durationMs: 204000,
    addedAt: DateTime(2026, 9, 30),
  );
}

Future<void> _goImport(WidgetTester tester) async {
  // appRouter 是全局单例：前序用例可能把路由留在任意页（含 /import 本页、
  // 无底栏的全屏路由）。已在导入页就直接等加载完成，否则先回首页再点入口。
  if (find.byKey(const Key('page_import')).evaluate().isNotEmpty) {
    await tester.pumpAndSettle();
    return;
  }
  if (find.byKey(const Key('tab_home')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('tab_home')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('导入音频'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('导入：本机音频列表点选 → 确认页 → 确认 → 落库并跳转面试列表',
      (tester) async {
    final service = _StubImportService();
    final device = FakeDeviceAudioService(audios: [
      _deviceAudio('字节跳动_二面.mp3'),
      _deviceAudio('美团一面.m4a'),
    ]);
    final db = await pumpInterviewVaultApp(
      tester,
      audioImportService: service,
      deviceAudioService: device,
    );
    addTearDown(db.close);

    await _goImport(tester);

    // 本机音频列表（MediaStore）：文件名 + 专辑 + 时长 + 大小
    expect(find.byKey(const Key('page_import')), findsOneWidget);
    expect(find.text('字节跳动_二面.mp3'), findsOneWidget);
    expect(find.text('美团一面.m4a'), findsOneWidget);
    expect(find.textContaining('面试录音'), findsWidgets);
    expect(find.textContaining('03:24'), findsWidgets);
    expect(find.textContaining('1.2 MB'), findsWidgets);

    // 点选第一个文件 → 格式确认卡（PRD 2.3）
    await tester.tap(find.byKey(const Key('device_audio_0')));
    await tester.pumpAndSettle();

    expect(find.text('字节跳动_二面.mp3'), findsOneWidget);
    expect(find.text('MP3'), findsOneWidget);
    expect(find.text('1.2 MB'), findsOneWidget);
    expect(find.text('03:24'), findsOneWidget);

    // 确认导入：调用服务的 importFile + 落草稿面试记录 + 跳转
    await tester.tap(find.byKey(const Key('btn_import_confirm')));
    await tester.pumpAndSettle();

    expect(service.imported, hasLength(1));
    expect(service.imported.single.fileName, '字节跳动_二面.mp3');

    final rows = await db.interviewsDao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.audioFilePath,
        '/stub/recordings/imports/interview_stored.mp3');
    expect(rows.single.durationSeconds, 204);
    expect(rows.single.status, 'draft');
    expect(find.byKey(const Key('page_interviews')), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('导入：搜索过滤本机列表；文件管理器入口仍可用且时长探测失败降级',
      (tester) async {
    final service = _StubImportService(
      pickResults: [
        const PickedAudio(
          path: '/stub/cache/retry.mp3',
          fileName: 'retry.mp3',
          sizeBytes: 4,
        ),
      ],
      inspectedDuration: null, // 时长探测失败 → 降级文案
    );
    final device = FakeDeviceAudioService(audios: [
      _deviceAudio('字节跳动_二面.mp3'),
      _deviceAudio('retry.mp3', sizeBytes: 4),
    ]);
    final db = await pumpInterviewVaultApp(
      tester,
      audioImportService: service,
      deviceAudioService: device,
    );
    addTearDown(db.close);

    await _goImport(tester);

    // 搜索过滤：只命中 retry
    await tester.enterText(find.byKey(const Key('field_import_search')), 'retry');
    await tester.pumpAndSettle();
    expect(find.text('retry.mp3'), findsOneWidget);
    expect(find.text('字节跳动_二面.mp3'), findsNothing);

    // 系统文件选择器兜底入口
    await tester.tap(find.byKey(const Key('btn_import_pick')));
    await tester.pumpAndSettle();

    expect(find.text('retry.mp3'), findsOneWidget);
    expect(find.text('MP3'), findsOneWidget);
    expect(find.text('待转写确认'), findsOneWidget);

    // 未确认导入前不落库
    final rows = await db.interviewsDao.getAll();
    expect(rows, isEmpty);
    expect(service.imported, isEmpty);

    await drainAppTimers(tester);
  });

  testWidgets('导入：媒体权限被拒 → 引导文案与去授权按钮，可再次请求', (tester) async {
    final service = _StubImportService();
    final device = FakeDeviceAudioService(
      permission: DeviceAudioPermission.denied,
      audios: const [],
    );
    final db = await pumpInterviewVaultApp(
      tester,
      audioImportService: service,
      deviceAudioService: device,
    );
    addTearDown(db.close);

    await _goImport(tester);

    // 拒绝态：说明文案 + 去授权按钮，不展示列表
    expect(find.byKey(const Key('btn_import_permission')), findsOneWidget);
    expect(find.textContaining('音频媒体'), findsOneWidget);
    expect(find.text('字节跳动_二面.mp3'), findsNothing);

    // 再次请求（仍被拒 → 停留在引导态）
    await tester.tap(find.byKey(const Key('btn_import_permission')));
    await tester.pumpAndSettle();
    expect(device.ensureCalls, 2);
    expect(find.byKey(const Key('btn_import_permission')), findsOneWidget);

    await drainAppTimers(tester);
  });
}
