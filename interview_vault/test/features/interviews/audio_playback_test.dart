import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:interview_vault/features/interviews/audio_playback.dart';

/// just_audio 平台桩：可控的状态机（load/play/pause/seek/completed），
/// 用于在 VM 单测里驱动 JustAudioPlayback 的真实状态流转。
class _FakeJustAudioPlatform extends JustAudioPlatform {
  final _FakeAudioPlayerPlatform playerPlatform =
      _FakeAudioPlayerPlatform('test-player');

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async => playerPlatform;

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async =>
      DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async =>
      DisposeAllPlayersResponse();
}

class _FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  _FakeAudioPlayerPlatform(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();
  final _dataEvents = StreamController<PlayerDataMessage>.broadcast();
  final List<Duration> seeks = [];
  int playCalls = 0;
  int pauseCalls = 0;

  Duration position = Duration.zero;
  Duration duration = const Duration(minutes: 2);
  ProcessingStateMessage processingState = ProcessingStateMessage.idle;

  /// 测试驱动：模拟平台侧把整段音频播完（停在末尾、completed 态；
  /// 原生播完会同步上报 playing=false）
  void complete() {
    processingState = ProcessingStateMessage.completed;
    position = duration;
    _emit();
    _dataEvents.add(PlayerDataMessage(playing: false));
  }

  void _emit() {
    _events.add(PlaybackEventMessage(
      processingState: processingState,
      updateTime: DateTime.now(),
      updatePosition: position,
      bufferedPosition:
          processingState == ProcessingStateMessage.completed ? duration : position,
      duration: duration,
      icyMetadata: null,
      currentIndex: null,
      androidAudioSessionId: null,
    ));
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _dataEvents.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    processingState = ProcessingStateMessage.ready;
    position = Duration.zero;
    _emit();
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    playCalls++;
    // 复现真实平台行为：在末尾 play 不会自动回到开头（直接到头结束）
    if (processingState == ProcessingStateMessage.completed) {
      return PlayResponse();
    }
    processingState = ProcessingStateMessage.ready;
    _emit();
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    pauseCalls++;
    _emit();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    seeks.add(request.position ?? Duration.zero);
    position = request.position ?? Duration.zero;
    if (processingState != ProcessingStateMessage.idle) {
      processingState = ProcessingStateMessage.ready;
    }
    _emit();
    return SeekResponse();
  }

  // 以下方法 JustAudioPlayback 路径上不会触发，兜底空实现防止漏桩崩溃
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async =>
      SetShuffleModeResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async =>
      SetAndroidAudioAttributesResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async =>
      DisposeResponse();
}

/// 测试环境没有平台实现：just_audio 构造时会配置 audio_session，
/// 桩掉其方法通道避免 MissingPluginException。
void _stubAudioSessionChannel() {
  const channel = MethodChannel('com.ryanheise.audio_session');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => null);
}

/// 广播流的 PlaybackEvent 经微任务投递；open 返回后排空一轮，
/// 让 duration/position 与真实播放器行为一致。
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _stubAudioSessionChannel();

  late _FakeJustAudioPlatform platform;
  late JustAudioPlayback playback;

  setUp(() {
    platform = _FakeJustAudioPlatform();
    JustAudioPlatform.instance = platform;
    playback = JustAudioPlayback();
  });

  tearDown(() async {
    await playback.dispose();
  });

  group('toggle（播完再点播放）', () {
    test('播完后再次播放：先回到开头再播（而不是在末尾一播即止）', () async {
      await playback.open('/stub/meeting.m4a');
      await _settle();
      await playback.toggle(); // 开始播放
      expect(platform.playerPlatform.playCalls, 1);

      platform.playerPlatform.complete(); // 整段播完，停在末尾
      await _settle(); // completed 事件经微任务投递到 AudioPlayer

      await playback.toggle(); // 再点一次播放
      expect(platform.playerPlatform.seeks, [Duration.zero],
          reason: 'completed 态下重播必须先 seek 回开头');
      expect(platform.playerPlatform.playCalls, 2);

      final snapshot = playback.current;
      expect(snapshot.playing, isTrue);
    });

    test('播放中点一下：暂停，不触发 seek', () async {
      await playback.open('/stub/meeting.m4a');
      await _settle();
      await playback.toggle();
      await playback.toggle();
      expect(platform.playerPlatform.pauseCalls, 1);
      expect(platform.playerPlatform.seeks, isEmpty);
      expect(playback.current.playing, isFalse);
    });

    test('暂停后继续：从暂停位置续播，不回到开头', () async {
      await playback.open('/stub/meeting.m4a');
      await _settle();
      await playback.toggle();
      await playback.toggle(); // 暂停
      platform.playerPlatform.position = const Duration(seconds: 30);
      await playback.toggle(); // 续播
      expect(platform.playerPlatform.seeks, isEmpty);
      expect(platform.playerPlatform.playCalls, 2);
      expect(playback.current.playing, isTrue);
    });

    test('跳转标注（seekTo 分段起点）在 completed 态下照常可用', () async {
      await playback.open('/stub/meeting.m4a');
      await _settle();
      platform.playerPlatform.complete();
      await _settle();
      await playback.seekTo(const Duration(seconds: 12));
      await playback.toggle();
      expect(platform.playerPlatform.seeks, [const Duration(seconds: 12)]);
      expect(platform.playerPlatform.playCalls, 1);
    });
  });

  test('open 同一路径幂等：不重复 load，状态保持', () async {
    await playback.open('/stub/meeting.m4a');
      await _settle();
    final firstDuration = playback.current.duration;
    await playback.open('/stub/meeting.m4a');
      await _settle();
    expect(playback.current.duration, firstDuration);
    expect(playback.current.position, Duration.zero);
  });

  test('状态流订阅即收到当前值（StreamProvider 初值）', () async {
    await playback.open('/stub/meeting.m4a');
      await _settle();
    final first = await playback.states.first;
    expect(first.playing, isFalse);
    expect(first.duration, const Duration(minutes: 2));
  });
}
