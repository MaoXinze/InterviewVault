import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../data/local/audio_files.dart';

/// 麦克风权限被拒。
class RecorderPermissionException implements Exception {
  const RecorderPermissionException();

  @override
  String toString() => '未获得麦克风权限';
}

/// 录音链路异常（插件未返回文件路径等）。
class RecorderException implements Exception {
  const RecorderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次录音的产物：文件路径（web 为会话级地址）+ 时长。
class RecordingResult {
  const RecordingResult({required this.filePath, required this.duration});

  final String filePath;
  final Duration duration;
}

/// 录音服务：封装 record 插件的状态机（待开始 → 录音中 → 已暂停），
/// 负责计时（Stopwatch 精确累计暂停区间）、电平轮询与文件落位；
/// UI 只消费状态与动作。
///
/// record 6.2.1 的 start() 在原生线程失败（编码器不支持、路径不可写等）
/// 时 Future 正常返回，错误经 onStateChanged 流以 error 事件异步透传，
/// 因此必须订阅该流，否则会静默假录音。
class RecorderService extends ChangeNotifier {
  RecorderService({
    AudioRecorder? recorder,
    this.pathResolver,
    this.onPlatformError,
  }) : _recorder = recorder ?? AudioRecorder() {
    _stateSub = _recorder.onStateChanged().listen(
          (_) {},
          onError: (Object error) {
            // 平台侧异步失败：终结状态机回待开始，并把错误转给 UI 提示
            _clock.stop();
            _stopTimers();
            _state = RecordState.stop;
            _stopping = false;
            _level = 0;
            onPlatformError?.call(error);
            _notify();
          },
        );
  }

  final AudioRecorder _recorder;

  /// 音频文件落位解析（测试可注入）；web 为会话级地址
  final Future<String> Function(AudioEncoder encoder)? pathResolver;

  /// 平台侧异步失败回调（start 后原生线程报错经状态流透传）。
  /// UI 借此弹提示；页面销毁时置 null。
  void Function(Object error)? onPlatformError;

  StreamSubscription<RecordState>? _stateSub;

  Timer? _tick;
  Timer? _meter;
  RecordState _state = RecordState.stop; // stop = 待开始
  // clock.stopwatch() 感知 zone 时钟：fake_async 测试中跟随假时钟推进
  final Stopwatch _clock = clock.stopwatch();  bool _meterBusy = false;
  bool _stopping = false;
  double _level = 0;
  bool _disposed = false;

  /// 电平历史（0..1，最新在尾，容量 28），UI 直接渲染波形。
  final List<double> history = [];

  RecordState get state => _state;
  bool get isIdle => _state == RecordState.stop;
  bool get isRecording => _state == RecordState.record;
  bool get isPaused => _state == RecordState.pause;

  /// 停止落库进行中（防双击重复入库）
  bool get isStopping => _stopping;
  Duration get elapsed => _clock.elapsed;

  /// 当前电平（dBFS -60..0 线性映射到 0..1）
  double get level => _level;

  Future<void> start() async {
    if (_state != RecordState.stop || _stopping) return;
    if (!await _recorder.hasPermission()) {
      throw const RecorderPermissionException();
    }
    // web 端 MediaRecorder 不一定支持 wav，不支持时回退 aacLc
    final encoder = await _recorder.isEncoderSupported(AudioEncoder.wav)
        ? AudioEncoder.wav
        : AudioEncoder.aacLc;
    if (!kIsWeb && pathResolver == null) {
      // 先建目录：插件不自建父目录，缺失即静默失败（见 audio_files_io）
      await ensureRecordingsDir();
    }
    final path = await _resolvePath(encoder);
    await _recorder.start(
      RecordConfig(
        encoder: encoder,
        sampleRate: 44100,
        numChannels: 1,
        // 锁屏后台录音（PLAN 决策 2）：插件内置前台服务 + 常驻通知；
        // app manifest 需声明 AudioRecordingService 且
        // foregroundServiceType="microphone"。字段已被上游标弃用
        // （下个 major 移除），届时迁移外部前台服务方案。
        androidConfig: AndroidRecordConfig(
          // ignore: deprecated_member_use
          service: const AndroidService(title: '面试录音进行中'),
        ),
      ),
      path: path,
    );
    _clock
      ..reset()
      ..start();
    history.clear();
    _level = 0;
    _state = RecordState.record;
    _startTimers();
    _notify();
  }

  Future<void> pause() async {
    if (_state != RecordState.record) return;
    await _recorder.pause();
    _clock.stop();
    _stopTimers();
    _state = RecordState.pause;
    _notify();
  }

  Future<void> resume() async {
    if (_state != RecordState.pause) return;
    await _recorder.resume();
    _clock.start();
    _state = RecordState.record;
    _startTimers();
    _notify();
  }

  /// 停止并落盘；待开始或已在停止流程返回 null。
  /// 插件未给出文件路径时抛 [RecorderException]（防止空路径入库）。
  Future<RecordingResult?> stop() async {
    if (isIdle || _stopping) return null;
    _stopping = true;
    _notify();
    String? path;
    try {
      path = await _recorder.stop();
    } finally {
      // 无论 stop 是否抛出都终结状态机：计时停止、回待开始，可再次开始
      _clock.stop();
      _stopTimers();
      _level = 0;
      _state = RecordState.stop;
      _stopping = false;
      _notify();
    }
    if (path == null || path.isEmpty) {
      throw const RecorderException('录音文件缺失，本次录音未能保存');
    }
    return RecordingResult(filePath: path, duration: _clock.elapsed);
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
    // 计时权威值来自 Stopwatch，tick 只负责驱动 UI 刷新
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    _meter = Timer.periodic(const Duration(milliseconds: 150), (_) {
      _pollLevel();
    });
  }

  Future<void> _pollLevel() async {
    if (_meterBusy) return;
    _meterBusy = true;
    try {
      final amplitude = await _recorder.getAmplitude();
      _level = ((amplitude.current + 60) / 60).clamp(0.0, 1.0);
      history.add(_level);
      if (history.length > 28) history.removeAt(0);
      _notify();
    } on Exception {
      // 单次电平读取失败忽略（平台/状态切换瞬间可能发生）
    } finally {
      _meterBusy = false;
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
    _stateSub?.cancel();
    _stopTimers();
    _clock.stop();
    if (_state == RecordState.stop) {
      _recorder.dispose();
    } else {
      // 录音中销毁（App 退出）：先尽力落盘文件头再释放，避免半截文件
      unawaited(Future(() async {
        try {
          await _recorder.stop();
        } on Exception {
          // 尽力而为
        }
        await _recorder.dispose();
      }));
    }
    super.dispose();
  }
}
