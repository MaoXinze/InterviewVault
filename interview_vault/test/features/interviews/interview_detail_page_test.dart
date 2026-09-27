import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/interviews/audio_playback.dart';
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

/// 回放桩：记录 open/toggle/seek 调用；states 非广播流会缓存先发的事件，
/// StreamProvider 订阅时立即拿到初值。
class FakeAudioPlayback implements AudioPlayback {
  final _controller = StreamController<AudioPlaybackSnapshot>();
  @override
  AudioPlaybackSnapshot current = const AudioPlaybackSnapshot(
    playing: false,
    position: Duration.zero,
    duration: null,
  );

  int openCalls = 0;
  int toggleCalls = 0;
  String? lastPath;
  final List<Duration> seeks = [];

  @override
  Stream<AudioPlaybackSnapshot> get states => _controller.stream;

  void _emit() {
    _controller.add(current);
  }

  @override
  Future<void> open(String path) async {
    openCalls++;
    lastPath = path;
  }

  @override
  Future<void> toggle() async {
    toggleCalls++;
    current = AudioPlaybackSnapshot(
      playing: !current.playing,
      position: current.position,
      duration: current.duration,
    );
    _emit();
  }

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
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

  Future<void> pumpDetail(
    WidgetTester tester, {
    AudioPlayback? player,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          transcriptionServiceProvider.overrideWithValue(runner),
          whisperModelGatewayProvider.overrideWithValue(gateway),
          if (player != null) audioPlaybackProvider.overrideWithValue(player),
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

  group('W3-M1 标注与播放', () {
    late FakeAudioPlayback player;

    setUp(() {
      player = FakeAudioPlayback();
    });

    Future<void> pumpTranscribed(WidgetTester tester) async {
      await insertInterview(status: 'transcribed');
      await insertSegments('iv-1');
      await pumpDetail(tester, player: player);
    }

    Future<void> addAnnotation(
      WidgetTester tester, {
      required String segmentId,
      required String tag,
      String? note,
      String? customTagName,
    }) async {
      await db.annotationsDao.insertOne(
        AnnotationsCompanion.insert(
          id: 'an-$segmentId-$tag',
          interviewId: 'iv-1',
          segmentId: Value(segmentId),
          tag: tag,
          customTagName: customTagName == null ? const Value(null) : Value(customTagName),
          note: note == null ? const Value(null) : Value(note),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('标注弹层：系统标签按固定顺序展示', (tester) async {
      await pumpTranscribed(tester);
      await tester.tap(find.byKey(const Key('btn_annotate_seg-1')));
      await tester.pumpAndSettle();

      // 弹层出现，5 个系统标签 + 新建入口
      expect(find.byKey(const Key('annotation_sheet')), findsOneWidget);
      for (final key in [
        'tag_chip_question',
        'tag_chip_answer',
        'tag_chip_highlight',
        'tag_chip_mistake',
        'tag_chip_improvement',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget);
      }
      expect(find.byKey(const Key('btn_new_tag')), findsOneWidget);
      // 未选标签时保存不可用
      expect(
        tester.widget<FilledButton>(
          find.byKey(const Key('btn_annotation_save')),
        ).onPressed,
        isNull,
      );
      await drainAppTimers(tester);
    });

    testWidgets('选系统标签保存：标注入库，状态翻转 annotated，chip 出现', (tester) async {
      await pumpTranscribed(tester);
      await tester.tap(find.byKey(const Key('btn_annotate_seg-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag_chip_highlight')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_annotation_save')));
      await tester.pumpAndSettle();

      final rows = await db.annotationsDao.getByInterview('iv-1');
      expect(rows, hasLength(1));
      expect(rows.single.tag, 'highlight');
      expect(rows.single.segmentId, 'seg-1');
      expect(rows.single.note, isNull);
      final interview = await db.interviewsDao.getById('iv-1');
      expect(interview!.status, 'annotated');
      expect(
        find.byKey(Key('annotation_chip_${rows.single.id}')),
        findsOneWidget,
      );
      await drainAppTimers(tester);
    });

    testWidgets('笔记随标注保存，chip 显示笔记标记', (tester) async {
      await pumpTranscribed(tester);
      await tester.tap(find.byKey(const Key('btn_annotate_seg-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag_chip_mistake')));
      await tester.enterText(
        find.byKey(const Key('annotation_note_field')),
        '架构题答浅了，下次先讲权衡',
      );
      await tester.tap(find.byKey(const Key('btn_annotation_save')));
      await tester.pumpAndSettle();

      final rows = await db.annotationsDao.getByInterview('iv-1');
      expect(rows.single.note, '架构题答浅了，下次先讲权衡');
      expect(find.textContaining('失误 · ✎'), findsOneWidget);
      await drainAppTimers(tester);
    });

    testWidgets('点标注 chip：打开音频 + seek 到分段起点 + 开始播放', (tester) async {
      await pumpTranscribed(tester);
      await addAnnotation(tester, segmentId: 'seg-2', tag: 'question');
      expect(player.openCalls, 0);

      await tester.tap(find.byKey(const Key('annotation_chip_an-seg-2-question')));
      await tester.pumpAndSettle();

      expect(player.openCalls, 1);
      expect(player.lastPath, '/data/audio/interview_1.m4a');
      // seg-2 起点 65.2s
      expect(player.seeks.single, const Duration(milliseconds: 65200));
      expect(player.toggleCalls, 1);
      await drainAppTimers(tester);
    });

    testWidgets('长按标注 chip 编辑：换标签与改笔记后保存', (tester) async {
      await pumpTranscribed(tester);
      await addAnnotation(
        tester,
        segmentId: 'seg-1',
        tag: 'highlight',
        note: '先记一版',
      );
      await tester.longPress(
        find.byKey(const Key('annotation_chip_an-seg-1-highlight')),
      );
      await tester.pumpAndSettle();

      // 弹层预填：笔记已在输入框、标签已选中
      expect(
        tester.widget<TextField>(
          find.byKey(const Key('annotation_note_field')),
        ).controller!.text,
        '先记一版',
      );
      await tester.tap(find.byKey(const Key('tag_chip_improvement')));
      await tester.enterText(
        find.byKey(const Key('annotation_note_field')),
        '改成改进项',
      );
      await tester.tap(find.byKey(const Key('btn_annotation_save')));
      await tester.pumpAndSettle();

      final row = (await db.annotationsDao.getByInterview('iv-1')).single;
      expect(row.tag, 'improvement');
      expect(row.customTagName, isNull);
      expect(row.note, '改成改进项');
      await drainAppTimers(tester);
    });

    testWidgets('编辑弹层可删除标注：DB 清空，chip 消失', (tester) async {
      await pumpTranscribed(tester);
      await addAnnotation(tester, segmentId: 'seg-1', tag: 'highlight');
      await tester.longPress(
        find.byKey(const Key('annotation_chip_an-seg-1-highlight')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_annotation_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_confirm_delete_annotation')));
      await tester.pumpAndSettle();

      expect(await db.annotationsDao.getByInterview('iv-1'), isEmpty);
      expect(find.text('亮点'), findsNothing);
      await drainAppTimers(tester);
    });

    testWidgets('标签筛选：点"失误"只看失误分段，点"全部"恢复', (tester) async {
      await pumpTranscribed(tester);
      await addAnnotation(tester, segmentId: 'seg-1', tag: 'highlight');
      await addAnnotation(tester, segmentId: 'seg-2', tag: 'mistake');

      await tester.tap(find.byKey(const Key('filter_chip_mistake')));
      await tester.pumpAndSettle();
      expect(find.text('我从架构与性能两方面说说'), findsOneWidget);
      expect(find.text('请介绍一下你做过的最难的项目'), findsNothing);

      await tester.tap(find.byKey(const Key('filter_chip_all')));
      await tester.pumpAndSettle();
      expect(find.text('请介绍一下你做过的最难的项目'), findsOneWidget);
      expect(find.text('我从架构与性能两方面说说'), findsOneWidget);
      await drainAppTimers(tester);
    });

    testWidgets('新建自定义标签：落 tags 表并用于标注', (tester) async {
      await pumpTranscribed(tester);
      await tester.tap(find.byKey(const Key('btn_annotate_seg-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_new_tag')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new_tag_field')), '系统设计');
      await tester.tap(find.byKey(const Key('btn_new_tag_save')));
      await tester.pumpAndSettle();
      // 创建后自动选中
      await tester.tap(find.byKey(const Key('btn_annotation_save')));
      await tester.pumpAndSettle();

      final tags = await db.tagsDao.getAll();
      final custom = tags.singleWhere((t) => t.name == '系统设计');
      expect(custom.isSystem, isFalse);

      final row = (await db.annotationsDao.getByInterview('iv-1')).single;
      expect(row.tag, 'custom');
      expect(row.customTagName, '系统设计');
      // 分段上的标注 chip + 筛选条各一处
      expect(find.byKey(const Key('filter_chip_custom:系统设计')), findsOneWidget);
      await drainAppTimers(tester);
    });

    testWidgets('重名标签被拦截：提示已存在，tags 表不变', (tester) async {
      await pumpTranscribed(tester);
      await tester.tap(find.byKey(const Key('btn_annotate_seg-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_new_tag')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new_tag_field')), '亮点');
      await tester.tap(find.byKey(const Key('btn_new_tag_save')));
      await tester.pumpAndSettle();

      expect(find.text('标签已存在，换个名字试试'), findsOneWidget);
      expect((await db.tagsDao.getAll()).where((t) => t.name == '亮点').length, 1);
      await drainAppTimers(tester);
    });

    testWidgets('长按系统标签：提示不可删除', (tester) async {
      await pumpTranscribed(tester);
      await tester.tap(find.byKey(const Key('btn_annotate_seg-1')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('tag_chip_question')));
      await tester.pumpAndSettle();

      expect(find.text('系统标签「问题」不可删除'), findsOneWidget);
      expect((await db.tagsDao.getAll()).length, 5);
      await drainAppTimers(tester);
    });

    testWidgets('长按自定义标签：确认后删除', (tester) async {
      await pumpTranscribed(tester);
      await db.tagsDao.insertOne(
        TagsCompanion.insert(id: 'tag-custom-反问环节', name: '反问环节'),
      );
      await tester.tap(find.byKey(const Key('btn_annotate_seg-1')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('tag_chip_custom:反问环节')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_confirm_delete_tag')));
      await tester.pumpAndSettle();

      expect(
        (await db.tagsDao.getAll()).where((t) => t.name == '反问环节'),
        isEmpty,
      );
      await drainAppTimers(tester);
    });

    testWidgets('迷你播放条：有音频显示，点播放调用 open+toggle', (tester) async {
      await pumpTranscribed(tester);

      expect(find.byKey(const Key('mini_player')), findsOneWidget);
      expect(find.byKey(const Key('btn_play_pause')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn_play_pause')));
      await tester.pumpAndSettle();

      expect(player.openCalls, 1);
      expect(player.lastPath, '/data/audio/interview_1.m4a');
      expect(player.toggleCalls, 1);
      await drainAppTimers(tester);
    });

    testWidgets('无音频文件的面试不显示播放条', (tester) async {
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: 'iv-1',
          status: const Value('transcribed'),
        ),
      );
      await insertSegments('iv-1');
      await pumpDetail(tester, player: player);

      expect(find.byKey(const Key('mini_player')), findsNothing);
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