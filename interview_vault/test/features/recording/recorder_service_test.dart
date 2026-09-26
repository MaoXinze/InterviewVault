import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/features/recording/recorder_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

class MockAudioRecorder extends Mock implements AudioRecorder {}

void main() {
  late MockAudioRecorder recorder;

  setUpAll(() {
    registerFallbackValue(RecordConfig(encoder: AudioEncoder.wav));
  });

  setUp(() {
    recorder = MockAudioRecorder();
    when(() => recorder.hasPermission()).thenAnswer((_) async => true);
    when(() => recorder.isEncoderSupported(AudioEncoder.wav))
        .thenAnswer((_) async => true);
    when(() => recorder.start(any(), path: any(named: 'path')))
        .thenAnswer((_) async {});
    when(() => recorder.getAmplitude())
        .thenAnswer((_) async => Amplitude(current: -30, max: -20));
    when(() => recorder.pause()).thenAnswer((_) async {});
    when(() => recorder.resume()).thenAnswer((_) async {});
    when(() => recorder.stop()).thenAnswer((_) async => '/recordings/x.wav');
  });

  RecorderService buildService() => RecorderService(
        recorder: recorder,
        pathResolver: (_) async => '/recordings/interview.wav',
      );

  test('权限被拒时 start 抛异常且不进入录音态', () async {
    when(() => recorder.hasPermission()).thenAnswer((_) async => false);
    final service = buildService();
    await expectLater(
      service.start(),
      throwsA(isA<RecorderPermissionException>()),
    );
    expect(service.isIdle, isTrue);
  });

  test('start → 录音态、计时与电平推进；stop 返回路径与时长', () {
    fakeAsync((async) {
      final service = buildService();
      unawaited(service.start());
      async.flushMicrotasks();
      expect(service.isRecording, isTrue);

      async.elapse(const Duration(seconds: 3));
      expect(service.elapsed, const Duration(seconds: 3));
      expect(service.level, greaterThan(0));
      expect(service.history, isNotEmpty);

      RecordingResult? result;
      unawaited(service.stop().then((r) => result = r));
      async.flushMicrotasks();
      expect(result, isNotNull);
      expect(result!.filePath, '/recordings/x.wav');
      expect(result!.duration, const Duration(seconds: 3));
      expect(service.isIdle, isTrue);

      final captured = verify(
        () => recorder.start(captureAny(), path: captureAny(named: 'path')),
      ).captured;
      final config = captured.first as RecordConfig;
      expect(config.encoder, AudioEncoder.wav);
      expect(config.sampleRate, 44100);
      expect(config.numChannels, 1);
    });
  });

  test('pause 冻结计时，resume 恢复', () {
    fakeAsync((async) {
      final service = buildService();
      unawaited(service.start());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));

      unawaited(service.pause());
      async.flushMicrotasks();
      expect(service.isPaused, isTrue);
      async.elapse(const Duration(seconds: 5));
      expect(service.elapsed, const Duration(seconds: 2)); // 冻结

      unawaited(service.resume());
      async.flushMicrotasks();
      expect(service.isRecording, isTrue);
      async.elapse(const Duration(seconds: 1));
      expect(service.elapsed, const Duration(seconds: 3));

      unawaited(service.stop());
      async.flushMicrotasks();
      expect(service.isIdle, isTrue);
    });
  });

  test('待开始状态调用 stop 返回 null', () async {
    final service = buildService();
    expect(await service.stop(), isNull);
  });
}
