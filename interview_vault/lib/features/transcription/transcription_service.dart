import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../data/database/app_database.dart';
import '../../data/database/tables.dart' show nowIso;
import 'whisper_engine.dart';
import 'whisper_model_manager.dart';

enum TranscriptionPhase { running, done, failed }

/// 转写进度事件（broadcast：详情页与列表页可同时监听）
class TranscriptionEvent {
  const TranscriptionEvent(
    this.interviewId,
    this.phase, {
    this.percent = 0,
    this.message,
  });

  final String interviewId;
  final TranscriptionPhase phase;

  /// running 时 0-100
  final int percent;

  /// failed 时的人话原因
  final String? message;
}

/// 前置校验类异常标记：直接透传给 UI（不同于引擎失败的包装语义）
abstract class TranscriptionPreconditionException implements Exception {}

class InterviewNotFoundException implements TranscriptionPreconditionException {}

class AudioFileNotFoundException implements TranscriptionPreconditionException {}

class WhisperModelNotDownloadedException
    implements TranscriptionPreconditionException {}

class AlreadyTranscribingException implements Exception {}

class TranscriptionFailedException implements Exception {
  const TranscriptionFailedException(this.cause);

  final Object cause;

  @override
  String toString() => '转写失败: $cause';
}

/// 转写编排的窄接口（页面依赖它，测试注入桩）
abstract class TranscriptionRunner {
  Stream<TranscriptionEvent> get events;

  bool isTranscribing(String interviewId);

  Future<void> transcribeInterview(
    String interviewId, {
    TranscribeModel model,
  });
}

/// 本地转写编排：面试草稿 → whisper 分段 → transcript_segments 落库 +
/// interviews 状态转 transcribed。推理在引擎内部 isolate，本服务只做
/// 编排、进度广播与落库原子性。
class TranscriptionService implements TranscriptionRunner {
  TranscriptionService({
    required this.db,
    required this.engine,
    required this.isModelDownloaded,
    this.lang = 'zh',
  });

  final AppDatabase db;
  final WhisperEngine engine;
  final Future<bool> Function(TranscribeModel model) isModelDownloaded;

  /// 面试场景语言默认中文（PRD 目标用户），可注入调整
  final String lang;

  final _events = StreamController<TranscriptionEvent>.broadcast();

  @override
  Stream<TranscriptionEvent> get events => _events.stream;

  final _active = <String>{};

  @override
  bool isTranscribing(String interviewId) => _active.contains(interviewId);

  @override
  Future<void> transcribeInterview(
    String interviewId, {
    TranscribeModel model = TranscribeModel.base,
  }) async {
    if (!_active.add(interviewId)) {
      throw AlreadyTranscribingException();
    }
    try {
      final interview = await db.interviewsDao.getById(interviewId);
      if (interview == null) throw InterviewNotFoundException();

      final audioPath = interview.audioFilePath;
      if (audioPath == null || audioPath.isEmpty || !File(audioPath).existsSync()) {
        throw AudioFileNotFoundException();
      }

      if (!await isModelDownloaded(model)) {
        throw WhisperModelNotDownloadedException();
      }

      final segments = await engine.transcribe(
        model: model,
        audioPath: audioPath,
        lang: lang,
        onProgress: (percent) => _events.add(
          TranscriptionEvent(interviewId, TranscriptionPhase.running, percent: percent),
        ),
      );

      // 过滤空白分段（whisper 对静音/噪声可能输出空串或占位符）
      final clean = segments
          .map((s) => EngineSegment(
                start: s.start,
                end: s.end,
                text: s.text.trim(),
              ))
          .where((s) => s.text.isNotEmpty)
          .toList();
      if (clean.isEmpty) {
        throw const TranscriptionFailedException('未识别到语音内容');
      }

      await _persist(interviewId, clean);
      _events.add(TranscriptionEvent(interviewId, TranscriptionPhase.done, percent: 100));
    } on TranscriptionFailedException catch (e) {
      _events.add(TranscriptionEvent(
        interviewId,
        TranscriptionPhase.failed,
        message: e.toString(),
      ));
      rethrow;
    } on AlreadyTranscribingException {
      // 不发 failed 事件：第一次转写仍在进行，广播失败会误导监听方
      rethrow;
    } on TranscriptionPreconditionException catch (e) {
      _events.add(TranscriptionEvent(
        interviewId,
        TranscriptionPhase.failed,
        message: e.toString(),
      ));
      rethrow;
    } on Exception catch (e) {
      _events.add(TranscriptionEvent(
        interviewId,
        TranscriptionPhase.failed,
        message: e.toString(),
      ));
      throw TranscriptionFailedException(e);
    } finally {
      _active.remove(interviewId);
    }
  }

  /// 分段替换 + 面试行更新放在一个事务里：状态翻转是提交标记，
  /// 中途失败时不会出现"有分段但状态还是 draft"的半截态。
  Future<void> _persist(String interviewId, List<EngineSegment> segments) {
    final stamp = nowIso();
    final entries = <TranscriptSegmentsCompanion>[
      for (var i = 0; i < segments.length; i++)
        TranscriptSegmentsCompanion.insert(
          id: 'seg_${stamp}_$i',
          interviewId: interviewId,
          startTime: segments[i].start.inMilliseconds / 1000.0,
          endTime: segments[i].end.inMilliseconds / 1000.0,
          content: segments[i].text,
          // speaker 留空 = 未标记（PRD 2.4：P0 手动标记）
        ),
    ];
    final transcriptText = segments.map((s) => s.text).join('\n');

    return db.transaction(() async {
      await db.segmentsDao.replaceAllForInterview(interviewId, entries);
      await db.interviewsDao.updateOne(
        interviewId,
        InterviewsCompanion(
          status: const Value('transcribed'),
          transcriptText: Value(transcriptText),
        ),
      );
    });
  }

  Future<void> dispose() => _events.close();
}
