import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// 一次回放状态快照：迷你播放条渲染所需的最小集合。
class AudioPlaybackSnapshot {
  const AudioPlaybackSnapshot({
    required this.playing,
    required this.position,
    required this.duration,
  });

  static const idle =
      AudioPlaybackSnapshot(playing: false, position: Duration.zero, duration: null);

  final bool playing;
  final Duration position;
  final Duration? duration;
}

/// 面试录音回放抽象：详情页迷你播放条与"点标注跳播放"只依赖此接口，
/// 测试用内存桩替换（just_audio 平台层无法在 VM 单测中运行）。
abstract interface class AudioPlayback {
  /// 状态流（广播 + 订阅即重放当前值，StreamProvider 可立即拿到初值）
  Stream<AudioPlaybackSnapshot> get states;

  AudioPlaybackSnapshot get current;

  /// 加载音频文件；同一路径重复 open 幂等（避免每次跳转都重新解码）。
  Future<void> open(String path);

  /// 播放/暂停切换（未加载文件时为无操作）
  Future<void> toggle();

  Future<void> seekTo(Duration position);

  Future<void> dispose();
}

/// just_audio 实现：懒加载（首次 open 才解码文件），播放中切到其他页面继续播。
class JustAudioPlayback implements AudioPlayback {
  AudioPlayer? _player;
  String? _loadedPath;
  final List<StreamSubscription<dynamic>> _subs = [];
  final _states = StreamController<AudioPlaybackSnapshot>.broadcast();
  AudioPlaybackSnapshot _current = AudioPlaybackSnapshot.idle;

  @override
  AudioPlaybackSnapshot get current => _current;

  @override
  Stream<AudioPlaybackSnapshot> get states {
    // 广播流不重放历史；包一层使订阅者先收到当前值，
    // StreamProvider 初次 build 即有数据可渲染
    late StreamController<AudioPlaybackSnapshot> controller;
    StreamSubscription<AudioPlaybackSnapshot>? sub;
    controller = StreamController<AudioPlaybackSnapshot>(
      onListen: () {
        controller.add(_current);
        sub = _states.stream.listen(controller.add);
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> open(String path) async {
    if (_loadedPath == path && _player != null) return;
    final player = _player ??= AudioPlayer();
    await player.setFilePath(path);
    _loadedPath = path;
    if (_subs.isEmpty) {
      void emit() {
        _current = AudioPlaybackSnapshot(
          playing: player.playing,
          position: player.position,
          duration: player.duration,
        );
        if (!_states.isClosed) _states.add(_current);
      }

      _subs.addAll([
        player.playerStateStream.listen((_) => emit()),
        player.positionStream.listen((_) => emit()),
      ]);
    }
  }

  @override
  Future<void> toggle() async {
    final player = _player;
    if (player == null) return;
    if (player.playing) {
      await player.pause();
      return;
    }
    // 上一轮播完停在末尾（completed）：直接 play 是在末尾续播，一播即止，
    // 用户视角就是"只能听一遍"——重播必须先回到开头
    if (player.processingState == ProcessingState.completed) {
      await player.seek(Duration.zero);
    }
    await player.play();
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _states.close();
    await _player?.dispose();
    _player = null;
  }
}
