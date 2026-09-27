import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/features/import/audio_import_service.dart';
import 'package:interview_vault/features/import/phone_recordings_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

void main() {
  testWidgets('导入：确认页展示文件信息 → 确认 → 落库并跳转面试列表',
      (tester) async {
    final service = _StubImportService(pickResults: [
      const PickedAudio(
        path: '/stub/cache/字节跳动_二面.MP3',
        fileName: '字节跳动_二面.MP3',
        sizeBytes: 1234567,
      ),
    ]);
    final db = await pumpInterviewVaultApp(tester, audioImportService: service);
    addTearDown(db.close);

    // appRouter 是全局单例：前序用例可能把路由留在任意 branch，
    // 先显式回首页再点入口（全套件顺序运行时依然成立）
    await tester.tap(find.byKey(const Key('tab_home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入音频'));
    await tester.pumpAndSettle();

    // 格式确认页（PRD 2.3）：文件名 / 格式 / 大小 / 时长
    expect(find.byKey(const Key('page_import')), findsOneWidget);
    expect(find.text('字节跳动_二面.MP3'), findsOneWidget);
    expect(find.text('MP3'), findsOneWidget);
    expect(find.text('1.2 MB'), findsOneWidget);
    expect(find.text('03:24'), findsOneWidget);

    // 确认导入：调用服务的 importFile + 落草稿面试记录 + 跳转
    await tester.tap(find.byKey(const Key('btn_import_confirm')));
    await tester.pumpAndSettle();

    expect(service.imported, hasLength(1));
    expect(service.imported.single.fileName, '字节跳动_二面.MP3');

    final rows = await db.interviewsDao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.audioFilePath,
        '/stub/recordings/imports/interview_stored.mp3');
    expect(rows.single.durationSeconds, 204);
    expect(rows.single.status, 'draft');
    expect(find.byKey(const Key('page_interviews')), findsOneWidget);

    // 体内先卸载树并排空 timer：db.close（teardown LIFO 在其后执行）
    // 时已无活跃查询流，避免 drift markAsClosed 的 Timer(0) 僵尸化
    await drainAppTimers(tester);
  });

  testWidgets('导入：用户取消选择 → 留在选择态；再次选择且时长探测失败时降级展示',
      (tester) async {
    final service = _StubImportService(
      pickResults: [
        null, // 首次自动唤起，用户取消
        const PickedAudio(
          path: '/stub/cache/retry.mp3',
          fileName: 'retry.mp3',
          sizeBytes: 4,
        ),
      ],
      inspectedDuration: null, // 时长探测失败 → 降级文案
    );
    final db = await pumpInterviewVaultApp(tester, audioImportService: service);
    addTearDown(db.close);

    // 同上：先回首页（前序用例可能把路由留在任意 branch）
    await tester.tap(find.byKey(const Key('tab_home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入音频'));
    await tester.pumpAndSettle();

    // 首次取消 → 空态引导
    expect(find.byKey(const Key('btn_import_pick')), findsOneWidget);

    // 手动再次选择
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

  testWidgets('从手机录音机导入：权限通过 → 列表选择 → 确认入库', (tester) async {
    final importService = _StubImportService(pickResults: [null]);
    final recorder = _StubPhoneRecordings();
    final db = await pumpInterviewVaultApp(
      tester,
      audioImportService: importService,
      phoneRecordings: recorder,
    );
    addTearDown(db.close);

    // 录音机流程会取临时目录（path_provider 平台通道桩）
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform();
    addTearDown(() {
      PathProviderPlatform.instance = originalProvider;
    });

    await tester.tap(find.byKey(const Key('tab_home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入音频'));
    await tester.pumpAndSettle();

    // 空态双入口：录音机为主、文件选择为辅
    expect(find.byKey(const Key('btn_import_recorder')), findsOneWidget);
    expect(find.byKey(const Key('btn_import_pick')), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn_import_recorder')));
    await tester.pumpAndSettle();

    // 列表展示手机录音机录音
    expect(find.text('手机录音机（2 条）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recorder_item_recording_1.m4a')));
    await tester.pumpAndSettle();

    // 复制自录音机 → 走统一确认页 → 确认入库
    expect(find.text('recording_1.m4a'), findsOneWidget);
    expect(recorder.copiedUri, 'content://media/external/audio/media/1');
    expect(importService.imported, isEmpty);

    await tester.tap(find.byKey(const Key('btn_import_confirm')));
    await tester.pumpAndSettle();

    expect(importService.imported, hasLength(1));
    final rows = await db.interviewsDao.getAll();
    expect(rows, hasLength(1));
    expect(find.byKey(const Key('page_interviews')), findsOneWidget);

    await drainAppTimers(tester);
  });

  testWidgets('从手机录音机导入：权限被拒 → 提示且不弹列表', (tester) async {
    final importService = _StubImportService(pickResults: [null]);
    final recorder = _StubPhoneRecordings()..permissionGranted = false;
    final db = await pumpInterviewVaultApp(
      tester,
      audioImportService: importService,
      phoneRecordings: recorder,
    );
    addTearDown(db.close);

    await tester.tap(find.byKey(const Key('tab_home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入音频'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn_import_recorder')));
    await tester.pumpAndSettle();

    expect(find.text('需要"音乐和音频"权限才能读取手机录音'), findsOneWidget);
    expect(find.text('手机录音机（2 条）'), findsNothing);
    expect(find.byKey(const Key('btn_import_recorder')), findsOneWidget);

    await drainAppTimers(tester);
  });
}

/// path_provider 平台通道桩（录音机流程取临时目录用）
class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => '/stub/cache';
}

/// 手机录音机服务桩：权限/列表/复制全部内存化
class _StubPhoneRecordings extends PhoneRecordingsService {
  _StubPhoneRecordings() : super(verifyCopied: (_) => true);

  bool permissionGranted = true;
  List<PhoneRecording> recordings = [
    const PhoneRecording(
      sourceUri: 'content://media/external/audio/media/1',
      fileName: 'recording_1.m4a',
      durationMs: 125000,
      sizeBytes: 2048,
      recordedAt: null,
    ),
    const PhoneRecording(
      sourceUri: 'content://media/external/audio/media/2',
      fileName: 'call_2.mp3',
      durationMs: 30000,
      sizeBytes: 512,
      recordedAt: null,
    ),
  ];
  String? copiedUri;

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Future<List<PhoneRecording>> list() async => recordings;

  @override
  Future<void> copyTo(String sourceUri, String targetPath) async {
    copiedUri = sourceUri;
  }
}
