import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/features/recording/recorder_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record/record.dart';

class MockAudioRecorder extends Mock implements AudioRecorder {}

/// PathProviderPlatform 是 PlatformInterface，禁止裸 implements；
/// 走官方 MockPlatformInterfaceMixin 逃生口。
class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  String documentsPath = '/tmp';

  @override
  Future<String> getApplicationDocumentsPath() async => documentsPath;
}

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
    when(() => recorder.onStateChanged())
        .thenAnswer((_) => const Stream<RecordState>.empty());
  });

  RecorderService buildService() => RecorderService(
        recorder: recorder,
        pathResolver: (_) async => '/recordings/interview.wav',
      );

  /// 驱动 start() 的多层 await（mock 立即返回，纯微任务）
  Future<void> drain() async {
    for (var i = 0; i < 5; i++) {
      await pumpEventQueue();
    }
  }

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

  test('Android 配置带前台服务（锁屏后台录音，PLAN 决策 2）', () async {
    final service = buildService();
    unawaited(service.start());
    await drain();

    final captured = verify(
      () => recorder.start(captureAny(), path: captureAny(named: 'path')),
    ).captured;
    final config = captured.first as RecordConfig;
    // ignore: deprecated_member_use
    expect(config.androidConfig.service?.title, '面试录音进行中');
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

  test('多次暂停/继续：Stopwatch 累计区间，无暂停边界计时漂移', () async {
    final service = buildService();
    // 真实异步：计时由 Stopwatch 推进，这里只验证状态与累计单调
    unawaited(service.start());
    await drain();
    expect(service.isRecording, isTrue);

    await service.pause();
    expect(service.isPaused, isTrue);
    final frozen = service.elapsed;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(service.elapsed, frozen); // 暂停期间冻结

    await service.resume();
    expect(service.isRecording, isTrue);
    expect(service.elapsed, greaterThanOrEqualTo(frozen));

    await service.stop();
    expect(service.isIdle, isTrue);
  });

  test('待开始状态调用 stop 返回 null', () async {
    final service = buildService();
    expect(await service.stop(), isNull);
  });

  test('双击停止：停止流程中再次 stop 返回 null，插件只停一次', () async {
    final service = buildService();
    unawaited(service.start());
    await drain();

    final first = service.stop();
    expect(service.isStopping, isTrue);
    expect(await service.stop(), isNull);
    expect(await first, isNotNull);
    verify(() => recorder.stop()).called(1);
  });

  test('stop 返回空路径：抛 RecorderException，状态机归位且可再次开始', () async {
    when(() => recorder.stop()).thenAnswer((_) async => null);
    final service = buildService();
    unawaited(service.start());
    await drain();

    await expectLater(service.stop(), throwsA(isA<RecorderException>()));
    expect(service.isIdle, isTrue);
    expect(service.isStopping, isFalse);

    // 自愈：修复后可重新录音
    when(() => recorder.stop()).thenAnswer((_) async => '/recordings/again.wav');
    unawaited(service.start());
    await drain();
    expect(service.isRecording, isTrue);
  });

  test('stop 抛异常：finally 兜底归位（定时器停止、isStopping 复位）', () async {
    when(() => recorder.stop()).thenThrow(Exception('stop failed'));
    final service = buildService();
    unawaited(service.start());
    await drain();
    expect(service.isRecording, isTrue);

    await expectLater(service.stop(), throwsA(isA<Exception>()));
    expect(service.isIdle, isTrue);
    expect(service.isStopping, isFalse);
  });

  test('平台侧启动失败经状态流 error 透传：归位并通知 UI', () async {
    final events = StreamController<RecordState>();
    addTearDown(events.close);
    when(() => recorder.onStateChanged()).thenAnswer((_) => events.stream);

    Object? reported;
    final service = RecorderService(
      recorder: recorder,
      pathResolver: (_) async => '/recordings/x.wav',
      onPlatformError: (error) => reported = error,
    );
    unawaited(service.start());
    await drain();
    expect(service.isRecording, isTrue);

    // record 插件：start 后原生线程失败 → 状态流发 error 事件（非 Future 异常）
    events.addError(Exception('FileNotFoundException'));
    await drain();

    expect(service.isIdle, isTrue);
    expect(service.isStopping, isFalse);
    expect(reported, isNotNull);
  });

  test('默认路径解析：start 前先建 recordings 目录（插件不自建父目录）', () async {
    final tmp = await Directory.systemTemp.createTemp('iv_recorder_test');
    addTearDown(() => tmp.delete(recursive: true));
    final original = PathProviderPlatform.instance;
    final fakePathProvider = FakePathProviderPlatform()
      ..documentsPath = tmp.path;
    PathProviderPlatform.instance = fakePathProvider;
    addTearDown(() => PathProviderPlatform.instance = original);

    final service = RecorderService(recorder: recorder);
    unawaited(service.start());
    await drain();

    expect(Directory('${tmp.path}/recordings').existsSync(), isTrue);
    expect(service.isRecording, isTrue);

    await service.stop();
    expect(service.isIdle, isTrue);
  });
}
