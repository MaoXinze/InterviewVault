import 'package:whisper_ggml/whisper_ggml.dart';

import 'whisper_model_manager.dart';

/// 引擎输出的归一化分段（时间戳精度取决于 whisper.cpp，厘秒级）
class EngineSegment {
  const EngineSegment({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;
}

/// 本地转写引擎抽象：测试注入桩，生产走 whisper_ggml。
abstract class WhisperEngine {
  /// 转写 [audioPath]；失败抛异常（区别于包的返回 null 吞错）。
  Future<List<EngineSegment>> transcribe({
    required TranscribeModel model,
    required String audioPath,
    required String lang,
    void Function(int percent)? onProgress,
  });
}

/// whisper_ggml 封装：
/// - 音频解码由包内置 FFmpeg 完成（Android），mp3/m4a 等直接进
/// - 模型文件必须已落在标准路径 `<appSupport>/ggml-<name>.bin`
///   （WhisperModelManager.download 保证），包内部按枚举推导同一路径
/// - 推理跑包内后台 isolate，UI 不阻塞（PLAN 铁律 2）
class WhisperGgmlEngine implements WhisperEngine {
  final WhisperController _controller = WhisperController();

  @override
  Future<List<EngineSegment>> transcribe({
    required TranscribeModel model,
    required String audioPath,
    required String lang,
    void Function(int percent)? onProgress,
  }) async {
    // 包的 transcribe 失败时吞异常返回 null，这里转成显式失败
    final result = await _controller.transcribe(
      model: model == TranscribeModel.base
          ? WhisperModel.base
          : WhisperModel.small,
      audioPath: audioPath,
      lang: lang,
      withSegments: true,
      onProgress: onProgress,
    );
    if (result == null) {
      throw Exception('本地转写引擎失败（模型加载或解码出错）');
    }
    final raw = result.transcription.segments ?? const [];
    return raw
        .map((s) => EngineSegment(start: s.fromTs, end: s.toTs, text: s.text))
        .toList();
  }
}
