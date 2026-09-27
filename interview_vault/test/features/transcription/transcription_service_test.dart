import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/transcription/whisper_engine.dart';
import 'package:interview_vault/features/transcription/whisper_model_manager.dart';
import 'package:interview_vault/features/transcription/transcription_service.dart';

/// 假引擎：记录调用参数，按配置返回分段/抛错/挂起
class FakeEngine implements WhisperEngine {
  FakeEngine({this.segments = const [], this.error});

  List<EngineSegment> segments;
  Object? error;

  /// 进入 transcribe 后挂起在此 future 上（模拟推理耗时）
  Future<void>? pending;

  /// 进入 transcribe 的信号（测试等它再断言 isTranscribing）
  Completer<void>? entered;

  int callCount = 0;
  TranscribeModel? lastModel;
  String? lastAudioPath;
  String? lastLang;
  void Function(void Function(int percent)? onProgress)? hook;

  @override
  Future<List<EngineSegment>> transcribe({
    required TranscribeModel model,
    required String audioPath,
    required String lang,
    void Function(int percent)? onProgress,
  }) async {
    callCount++;
    lastModel = model;
    lastAudioPath = audioPath;
    lastLang = lang;
    hook?.call(onProgress);
    entered?.complete();
    await pending;
    final err = error;
    if (err != null) throw err;
    return segments;
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late File audioFile;
  late FakeEngine engine;
  late TranscriptionService service;
  var modelReady = true;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('iv_transcribe_test');
    audioFile = File('${tempDir.path}/interview_1.m4a')
      ..writeAsBytesSync(List.filled(16, 1));
    engine = FakeEngine();
    modelReady = true;
    service = TranscriptionService(
      db: db,
      engine: engine,
      isModelDownloaded: (model) async => modelReady,
    );
  });
  tearDown(() async {
    await service.dispose();
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<String> insertInterview({
    String id = 'iv-1',
    String status = 'draft',
    String? audioPath,
    bool withAudio = true,
  }) async {
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: id,
        status: Value(status),
        audioFilePath: withAudio
            ? Value(audioPath ?? audioFile.path)
            : const Value.absent(),
      ),
    );
    return id;
  }

  final segments = [
    EngineSegment(
      start: const Duration(seconds: 1),
      end: const Duration(seconds: 4, milliseconds: 500),
      text: ' 请介绍一下你做过的最难的项目 ',
    ),
    EngineSegment(
      start: const Duration(seconds: 5),
      end: const Duration(seconds: 9),
      text: '   ',
    ),
    EngineSegment(
      start: const Duration(seconds: 10),
      end: const Duration(seconds: 15),
      text: '我说了 Flutter 的架构',
    ),
  ];

  group('转写成功路径', () {
    test('分段落库（过滤空白/时间转秒/speaker 未标记），状态转 transcribed，全文拼接', () async {
      final id = await insertInterview();
      engine.segments = segments;

      final collected = <TranscriptionEvent>[];
      final sub = service.events.listen(collected.add);
      await service.transcribeInterview(id);
      await pumpEventQueue();
      await sub.cancel();

      // 引擎参数
      expect(engine.callCount, 1);
      expect(engine.lastModel, TranscribeModel.base);
      expect(engine.lastAudioPath, audioFile.path);
      expect(engine.lastLang, 'zh');

      // 分段落库：空白段被过滤
      final rows = await db.segmentsDao.getByInterview(id);
      expect(rows.length, 2);
      expect(rows[0].content, '请介绍一下你做过的最难的项目');
      expect(rows[0].startTime, 1.0);
      expect(rows[0].endTime, 4.5);
      expect(rows[0].speaker, isNull, reason: 'P0 手动标记，初始未标记');
      expect(rows[1].content, '我说了 Flutter 的架构');

      // 面试行更新
      final iv = await db.interviewsDao.getById(id);
      expect(iv!.status, 'transcribed');
      expect(iv.transcriptText,
          '请介绍一下你做过的最难的项目\n我说了 Flutter 的架构');

      // 事件：done 收尾
      expect(collected.last.phase, TranscriptionPhase.done);
      expect(collected.last.interviewId, id);
      expect(service.isTranscribing(id), isFalse);
    });

    test('进度事件按引擎回调转发', () async {
      final id = await insertInterview();
      engine.segments = segments;
      engine.hook = (onProgress) => onProgress?.call(42);

      final collected = <TranscriptionEvent>[];
      final sub = service.events.listen(collected.add);
      await service.transcribeInterview(id);
      await pumpEventQueue();
      await sub.cancel();

      final running =
          collected.where((e) => e.phase == TranscriptionPhase.running).toList();
      expect(running.map((e) => e.percent), contains(42));
    });

    test('重新转写替换旧分段与全文', () async {
      final id = await insertInterview(status: 'transcribed');
      await db.segmentsDao.insertOne(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-old',
          interviewId: id,
          startTime: 0.0,
          endTime: 1.0,
          content: '旧内容',
        ),
      );

      engine.segments = [
        EngineSegment(
          start: Duration.zero,
          end: const Duration(seconds: 2),
          text: '新内容',
        ),
      ];
      await service.transcribeInterview(id, model: TranscribeModel.small);

      final rows = await db.segmentsDao.getByInterview(id);
      expect(rows.map((r) => r.content), ['新内容']);
      final iv = await db.interviewsDao.getById(id);
      expect(iv!.transcriptText, '新内容');
    });
  });

  group('前置校验（引擎零调用）', () {
    test('面试不存在', () async {
      await expectLater(
        service.transcribeInterview('no-such'),
        throwsA(isA<InterviewNotFoundException>()),
      );
      expect(engine.callCount, 0);
    });

    test('无音频路径 / 音频文件丢失', () async {
      final noAudio = await insertInterview(id: 'iv-2', withAudio: false);
      await expectLater(
        service.transcribeInterview(noAudio),
        throwsA(isA<AudioFileNotFoundException>()),
      );
      expect(engine.callCount, 0);

      final missing = await insertInterview(
        id: 'iv-3',
        audioPath: '${tempDir.path}/ghost.m4a',
      );
      await expectLater(
        service.transcribeInterview(missing),
        throwsA(isA<AudioFileNotFoundException>()),
      );
      expect(engine.callCount, 0);
    });

    test('模型未下载', () async {
      modelReady = false;
      final id = await insertInterview();
      await expectLater(
        service.transcribeInterview(id),
        throwsA(isA<WhisperModelNotDownloadedException>()),
      );
      expect(engine.callCount, 0);
    });
  });

  group('失败与并发', () {
    test('引擎抛错包装为 TranscriptionFailedException，状态保持 draft、不写分段', () async {
      final id = await insertInterview();
      engine.error = Exception('native crash');

      final collected = <TranscriptionEvent>[];
      final sub = service.events.listen(collected.add);
      await expectLater(
        service.transcribeInterview(id),
        throwsA(isA<TranscriptionFailedException>()),
      );
      await pumpEventQueue();
      await sub.cancel();

      final iv = await db.interviewsDao.getById(id);
      expect(iv!.status, 'draft');
      expect(await db.segmentsDao.getByInterview(id), isEmpty);
      expect(collected.last.phase, TranscriptionPhase.failed);
      expect(service.isTranscribing(id), isFalse);
    });

    test('引擎返回空结果视为失败', () async {
      final id = await insertInterview();
      engine.segments = [];
      await expectLater(
        service.transcribeInterview(id),
        throwsA(isA<TranscriptionFailedException>()),
      );
      expect((await db.interviewsDao.getById(id))!.status, 'draft');
    });

    test('同一场面试转写中重复触发被拒绝', () async {
      final id = await insertInterview();
      engine.segments = segments;
      final gate = Completer<void>();
      engine.entered = Completer<void>();
      engine.pending = gate.future;

      final running = service.transcribeInterview(id);
      await engine.entered!.future;
      expect(service.isTranscribing(id), isTrue);

      await expectLater(
        service.transcribeInterview(id),
        throwsA(isA<AlreadyTranscribingException>()),
      );

      gate.complete();
      await running;
      expect(service.isTranscribing(id), isFalse);
    });

    test('不同面试互不影响并发', () async {
      final a = await insertInterview(id: 'iv-a');
      final b = await insertInterview(id: 'iv-b');
      engine.segments = segments;

      await Future.wait([
        service.transcribeInterview(a),
        service.transcribeInterview(b),
      ]);
      expect(
        (await db.segmentsDao.getByInterview(a)).map((r) => r.interviewId),
        everyElement('iv-a'),
      );
    });
  });
}
