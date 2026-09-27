import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/interviews/presentation/interview_detail_page.dart';
import 'package:interview_vault/features/transcription/transcription_service.dart';
import 'package:interview_vault/features/transcription/whisper_model_manager.dart';
import '../../helpers/pump_app.dart';

class FakeTranscriptionRunner implements TranscriptionRunner {
  final _events = StreamController<TranscriptionEvent>.broadcast();

  @override
  Stream<TranscriptionEvent> get events => _events.stream;

  int calls = 0;
  String? lastId;
  TranscribeModel? lastModel;

  @override
  bool isTranscribing(String interviewId) => false;

  @override
  Future<void> transcribeInterview(
    String interviewId, {
    TranscribeModel model = TranscribeModel.base,
  }) async {
    calls++;
    lastId = interviewId;
    lastModel = model;
  }
}

class FakeModelGateway implements WhisperModelGateway {
  final _events = StreamController<ModelDownloadEvent>.broadcast();

  @override
  Stream<ModelDownloadEvent> get events => _events.stream;

  bool downloadedFlag = true;
  int downloadCalls = 0;

  @override
  Future<bool> isDownloaded(TranscribeModel model) async => downloadedFlag;

  @override
  Future<void> download(
    TranscribeModel model, {
    void Function(int received, int totalBytes)? onProgress,
  }) async {
    downloadCalls++;
  }

  @override
  Future<void> delete(TranscribeModel model) async {}

  @override
  bool isDownloading(TranscribeModel model) => false;

  @override
  int? percentOf(TranscribeModel model) => null;
}

void main() {
  late AppDatabase db;
  late FakeTranscriptionRunner runner;
  late FakeModelGateway gateway;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    runner = FakeTranscriptionRunner();
    gateway = FakeModelGateway();
  });
  tearDown(() => db.close());

  Future<void> insertInterview({String status = 'draft'}) async {
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: 'iv-1',
        company: const Value('字节跳动'),
        position: const Value('客户端工程师'),
        status: Value(status),
        audioFilePath: const Value('/data/audio/interview_1.m4a'),
      ),
    );
  }

  Future<void> insertSegments(String interviewId) async {
    await db.segmentsDao.insertOne(
      TranscriptSegmentsCompanion.insert(
        id: 'seg-1',
        interviewId: interviewId,
        startTime: 0,
        endTime: 4.5,
        content: '请介绍一下你做过的最难的项目',
      ),
    );
    await db.segmentsDao.insertOne(
      TranscriptSegmentsCompanion.insert(
        id: 'seg-2',
        interviewId: interviewId,
        startTime: 65.2,
        endTime: 70,
        content: '我从架构与性能两方面说说',
      ),
    );
  }

  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          transcriptionServiceProvider.overrideWithValue(runner),
          whisperModelGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          home: InterviewDetailPage(interviewId: 'iv-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // riverpod 3.4 的 Timer(Duration.zero) 需在卸载树后显式排空（见 pump_app.dart）
    addTearDown(() => drainAppTimers(tester));
  }

  group('draft 转写卡片', () {
    testWidgets('模型已下载：开始转写调用服务（默认 base 模型）', (tester) async {
      await insertInterview();
      await pumpDetail(tester);

      expect(find.byKey(const Key('btn_start_transcribe')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_start_transcribe')));
      await tester.pumpAndSettle();

      expect(runner.calls, 1);
      expect(runner.lastId, 'iv-1');
      expect(runner.lastModel, TranscribeModel.base);
      await drainAppTimers(tester);
    });

    testWidgets('切到 Small 后开始转写：服务收到 small 模型', (tester) async {
      await insertInterview();
      await pumpDetail(tester);

      await tester.tap(find.text('Small'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_start_transcribe')));
      await tester.pumpAndSettle();

      expect(runner.lastModel, TranscribeModel.small);
      await drainAppTimers(tester);
    });

    testWidgets('模型未下载：展示下载按钮，点击触发模型下载而非转写', (tester) async {
      await insertInterview();
      gateway.downloadedFlag = false;
      await pumpDetail(tester);

      expect(find.byKey(const Key('btn_download_model')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_download_model')));
      await tester.pumpAndSettle();

      expect(gateway.downloadCalls, 1);
      expect(runner.calls, 0);
      await drainAppTimers(tester);
    });
  });

  group('transcribed 逐字稿', () {
    testWidgets('分段按时间戳展示', (tester) async {
      await insertInterview(status: 'transcribed');
      await insertSegments('iv-1');
      await pumpDetail(tester);

      expect(find.byKey(const Key('transcript_header')), findsOneWidget);
      expect(find.text('请介绍一下你做过的最难的项目'), findsOneWidget);
      expect(find.text('我从架构与性能两方面说说'), findsOneWidget);
      // 时间戳标签（65.2s → 01:05）
      expect(find.text('01:05'), findsOneWidget);
      await drainAppTimers(tester);
    });

    testWidgets('点说话人 chip 循环标记：未标记 → 面试官', (tester) async {
      await insertInterview(status: 'transcribed');
      await insertSegments('iv-1');
      await pumpDetail(tester);

      await tester.tap(find.byKey(const Key('speaker_chip_seg-1')));
      await tester.pumpAndSettle();

      final row =
          (await db.segmentsDao.getByInterview('iv-1')).firstWhere(
        (r) => r.id == 'seg-1',
      );
      expect(row.speaker, 'interviewer');
      await drainAppTimers(tester);
    });

    testWidgets('说话人标记可回到未标记（三轮循环）', (tester) async {
      await insertInterview(status: 'transcribed');
      await insertSegments('iv-1');
      await pumpDetail(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('speaker_chip_seg-1')));
        await tester.pumpAndSettle();
      }
      final row =
          (await db.segmentsDao.getByInterview('iv-1')).firstWhere(
        (r) => r.id == 'seg-1',
      );
      expect(row.speaker, isNull);
      await drainAppTimers(tester);
    });

    testWidgets('点分段文本弹出编辑框，保存后入库', (tester) async {
      await insertInterview(status: 'transcribed');
      await insertSegments('iv-1');
      await pumpDetail(tester);

      await tester.tap(find.byKey(const Key('segment_tap_seg-1')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('segment_edit_field')),
        '请介绍一下你最有挑战的项目经历',
      );
      await tester.tap(find.byKey(const Key('segment_edit_save')));
      await tester.pumpAndSettle();

      final row =
          (await db.segmentsDao.getByInterview('iv-1')).firstWhere(
        (r) => r.id == 'seg-1',
      );
      expect(row.content, '请介绍一下你最有挑战的项目经历');
      // 数据库更新后 watch 流刷新 UI
      expect(find.text('请介绍一下你最有挑战的项目经历'), findsOneWidget);
      await drainAppTimers(tester);
    });
  });

  testWidgets('面试列表点击进入详情页（全 App 导航）', (tester) async {
    final db = await pumpInterviewVaultApp(tester);
    addTearDown(db.close);
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: 'iv-nav',
        company: const Value('字节跳动'),
      ),
    );

    await tester.tap(find.byKey(const Key('tab_interviews')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('字节跳动'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page_interview_detail')), findsOneWidget);
    await drainAppTimers(tester);
  });
}