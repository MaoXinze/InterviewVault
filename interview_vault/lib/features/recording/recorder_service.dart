import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 麦克风权限被拒。
class RecorderPermissionException implements Exception {
  const RecorderPermissionException();

  @override
  String toString() => '未获得麦克风权限';
}

/// 一次录音的产物：文件路径（web 为会话级地址）+ 时长。
class RecordingResult {
  const RecordingResult({required this.filePath, required this.duration});

  final String filePath;
  final Duration duration;
}

/// 录音服务：封装 record 插件的状态机（待开始 → 录音中 → 已暂停），
/// 负责计时、电平轮询与文件落位；UI 只消费状态与动作。
///
/// API 依据 record 6.2.1：start(config, path:) / pause / resume /
/// stop()→String? / hasPermission / isEncoderSupported / getAmplitude。
class RecorderService extends ChangeNotifier {
  RecorderService({
    AudioRecorder? recorder,
    this.pathResolver,
  })  : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  /// 音频文件落位解析（测试可注入）；web 为会话级地址
  final Future<String> Function(AudioEncoder encoder)? pathResolver;

  Timer? _tick;
  Timer? _meter;
  RecordState _state = RecordState.stop; // stop = 待开始
  Duration _elapsed = Duration.zero;
  double _level = 0;
  bool _disposed = false;

  /// 电平历史（0..1，最新在尾，容量 28），UI 直接渲染波形。
  final List<double> history = [];

  RecordState get state => _state;
  bool get isIdle => _state == RecordState.stop;
  bool get isRecording => _state == RecordState.record;
  bool get isPaused => _state == RecordState.pause;
  Duration get elapsed => _elapsed;

  /// 当前电平（dBFS -60..0 线性映射到 0..1）
  double get level => _level;

  Future<void> start() async {
    if (_state != RecordState.stop) return;
    if (!await _recorder.hasPermission()) {
      throw const RecorderPermissionException();
    }
    // web 端 MediaRecorder 不一定支持 wav，不支持时回退 aacLc
    final encoder = await _recorder.isEncoderSupported(AudioEncoder.wav)
        ? AudioEncoder.wav
        : AudioEncoder.aacLc;
    final path = await _resolvePath(encoder);
    await _recorder.start(
      RecordConfig(encoder: encoder, sampleRate: 44100, numChannels: 1),
      path: path,
    );
    _elapsed = Duration.zero;
    history.clear();
    _level = 0;
    _state = RecordState.record;
    _startTimers();
    _notify();
  }

  Future<void> pause() async {
    if (_state != RecordState.record) return;
    await _recorder.pause();
    _stopTimers();
    _state = RecordState.pause;
    _notify();
  }

  Future<void> resume() async {
    if (_state != RecordState.pause) return;
    await _recorder.resume();
    _state = RecordState.record;
    _startTimers();
    _notify();
  }

  /// 停止并落盘；待开始状态返回 null。
  Future<RecordingResult?> stop() async {
    if (_state == RecordState.stop) return null;
    final path = await _recorder.stop();
    _stopTimers();
    final result = RecordingResult(filePath: path ?? '', duration: _elapsed);
    _state = RecordState.stop;
    _level = 0;
    _notify();
    return result;
  }

  Future<String> _resolvePath(AudioEncoder encoder) async {
    final resolver = pathResolver;
    if (resolver != null) return resolver(encoder);
    if (kIsWeb) return 'web-session-recording';
    final dir = await getApplicationDocumentsDirectory();
    final ext = encoder == AudioEncoder.wav ? 'wav' : 'm4a';
    return '${dir.path}/recordings/interview_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  void _startTimers() {
    _stopTimers();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      _notify();
    });
    _meter = Timer.periodic(const Duration(milliseconds: 150), (_) {
      _pollLevel();
    });
  }

  Future<void> _pollLevel() async {
    try {
      final amplitude = await _recorder.getAmplitude();
      _level = ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
      history.add(_level);
      if (history.length > 28) history.removeAt(0);
      _notify();
    } on Exception {
      // 单次电平读取失败忽略（平台/状态切换瞬间可能发生）
    }
  }

  void _stopTimers() {
    _tick?.cancel();
    _tick = null;
    _meter?.cancel();
    _meter = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimers();
    _recorder.dispose();
    super.dispose();
  }
}
