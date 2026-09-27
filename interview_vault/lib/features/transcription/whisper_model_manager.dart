import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// 可按需下载的本地转写模型（PRD 2.4：whisper.cpp base/small）。
/// 命名与落位遵守 whisper.cpp / whisper_ggml 约定：
/// `<appSupport>/ggml-<name>.bin`，引擎直接按枚举加载。
enum TranscribeModel {
  base('base', '约 150 MB', 'Base · 中文可用 · 速度与精度均衡'),
  small('small', '约 500 MB', 'Small · 更准更慢 · 建议 WiFi 下载');

  const TranscribeModel(this.modelName, this.sizeHint, this.description);

  /// 与 WhisperModel.modelName / ggml 文件名一致
  final String modelName;
  final String sizeHint;
  final String description;

  /// 下载源：主源 HuggingFace，国内回退 hf-mirror。
  /// 与 whisper_ggml 的 modelUri 同一仓库（ggerganov/whisper.cpp）。
  List<Uri> get downloadUrls => [
        Uri.parse(
            'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$modelName.bin'),
        Uri.parse(
            'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-$modelName.bin'),
      ];
}

enum ModelDownloadPhase { downloading, done, failed }

/// 模型下载状态事件（broadcast：模型页与转写入口同时监听）
class ModelDownloadEvent {
  const ModelDownloadEvent(this.model, this.phase, [this.percent = 0]);

  final TranscribeModel model;
  final ModelDownloadPhase phase;

  /// downloading 时 0-100
  final int percent;
}

class WhisperDownloadException implements Exception {
  const WhisperDownloadException(this.model, this.cause);

  final TranscribeModel model;
  final Object cause;

  @override
  String toString() => '模型 ${model.modelName} 下载失败: $cause';
}

typedef ModelDownloader = Future<void> Function(
  Uri url,
  File target,
  void Function(int received, int totalBytes)? onProgress,
);

/// 模型可用性/下载网关接口（UI 与服务依赖它，测试注入桩）
abstract class WhisperModelGateway {
  Stream<ModelDownloadEvent> get events;

  Future<bool> isDownloaded(TranscribeModel model);

  /// 已存在则直接复用；同模型并发调用去重为同一任务
  Future<void> download(
    TranscribeModel model, {
    void Function(int received, int totalBytes)? onProgress,
  });

  Future<void> delete(TranscribeModel model);

  bool isDownloading(TranscribeModel model);

  /// 最近一次广播的下载百分比（0-100），无记录为 null
  int? percentOf(TranscribeModel model);
}

/// 本地转写模型管理：按需下载（进度/镜像回退/完整性校验）、查询、删除。
///
/// 不用 whisper_ggml 自带的 downloadModel：无进度回调、无校验、无镜像，
/// 500MB 级别的下载必须可观测。下载到 `<appSupport>/ggml-<name>.bin`，
/// 与引擎（WhisperModel 枚举）的取用路径完全一致。
class WhisperModelManager implements WhisperModelGateway {
  WhisperModelManager({
    ModelDownloader? downloader,
    Future<String> Function()? supportPathResolver,
    int? minModelBytes,
  })  : _download = downloader ?? _defaultDownloader,
        _supportPathResolver =
            supportPathResolver ?? _defaultSupportPathResolver,
        _minModelBytes = minModelBytes ?? 10 * 1024 * 1024;

  final ModelDownloader _download;
  final Future<String> Function() _supportPathResolver;
  final int _minModelBytes;

  final _events = StreamController<ModelDownloadEvent>.broadcast();
  @override
  Stream<ModelDownloadEvent> get events => _events.stream;

  /// 进行中的下载任务（同模型去重），完成后移除
  final _active = <TranscribeModel, Future<void>>{};

  @override
  bool isDownloading(TranscribeModel model) => _active.containsKey(model);

  /// 各模型最近一次广播的百分比（UI 恢复画面用）
  final _percent = <TranscribeModel, int>{};

  @override
  int? percentOf(TranscribeModel model) => _percent[model];

  Future<String> modelDir() async => _supportPathResolver();

  /// whisper.cpp 约定路径：`<appSupport>/ggml-<name>.bin`
  Future<String> modelPath(TranscribeModel model) async =>
      '${await modelDir()}/ggml-${model.modelName}.bin';

  @override
  Future<bool> isDownloaded(TranscribeModel model) async =>
      _active.containsKey(model) ||
      File(await modelPath(model)).existsSync();

  /// 下载模型（已存在则直接复用；同模型并发调用去重为同一任务）。
  /// [onProgress] 可选，received/totalBytes 单位字节。
  @override
  Future<void> download(
    TranscribeModel model, {
    void Function(int received, int totalBytes)? onProgress,
  }) {
    final existing = _active[model];
    if (existing != null) return existing;
    // 块体必须丢弃 Map.remove 的返回值：它是 whenComplete 产生的 future 本身，
    // 箭头函数把它当返回值回传会让 future 等自己（死锁）。
    return _active[model] = _downloadWithFallback(model, onProgress)
        .whenComplete(() {
      _active.remove(model);
    });
  }

  Future<void> _downloadWithFallback(
    TranscribeModel model,
    void Function(int, int)? onProgress,
  ) async {
    final target = File(await modelPath(model));
    if (target.existsSync()) return;
    final part = File('${target.path}.part');
    Object? lastCause;
    for (final url in model.downloadUrls) {
      try {
        // 上次中断的 .part 一律废弃重来（不追求断点续传，正确性优先）
        if (part.existsSync()) part.deleteSync();
        await _download(url, part, (received, total) {
          final pct = total <= 0 ? 0 : (received * 100 ~/ total).clamp(0, 100);
          _percent[model] = pct;
          _events.add(ModelDownloadEvent(model, ModelDownloadPhase.downloading, pct));
          onProgress?.call(received, total);
        });
        _assertValidGgml(part);
        // 原子落位：先 .part 校验通过再改名，杜绝半截文件被引擎加载
        part.renameSync(target.path);
        _percent[model] = 100;
        _events.add(ModelDownloadEvent(model, ModelDownloadPhase.done, 100));
        return;
      } catch (e) {
        lastCause = e;
        if (part.existsSync()) part.deleteSync();
      }
    }
    _events.add(ModelDownloadEvent(model, ModelDownloadPhase.failed));
    throw WhisperDownloadException(model, lastCause ?? '未知错误');
  }

  /// 完整性校验：ggml 模型头 magic + 最小体积。
  /// whisper.cpp 读到的 uint32 magic 0x67676d6c 以小端落盘即 'lmgg'；
  /// 兼容 'ggml' 大端写法，防御 HuggingFace 返回 HTML 错误页。
  void _assertValidGgml(File file) {
    if (!file.existsSync()) {
      throw Exception('下载文件不存在');
    }
    final magic = readGgmlMagic(file);
    final s = String.fromCharCodes(magic);
    if (s != 'lmgg' && s != 'ggml') {
      throw Exception('文件头不是 ggml 模型（magic=${magic.toList()}）');
    }
    if (file.lengthSync() < _minModelBytes) {
      throw Exception('文件体积异常（${file.lengthSync()} 字节）');
    }
  }

  /// 删除模型文件（AGENTS 铁律 3"删除即真删"）。
  /// 有下载在进行时不允许删（任务完成回调会写文件，竞态难收场）。
  @override
  Future<void> delete(TranscribeModel model) async {
    if (_active.containsKey(model)) {
      throw StateError('模型正在下载中，无法删除');
    }
    final file = File(await modelPath(model));
    if (file.existsSync()) await file.delete();
    _percent.remove(model);
  }

  static Future<void> _defaultDownloader(
    Uri url,
    File target,
    void Function(int, int)? onProgress,
  ) async {
    final dio = Dio();
    try {
      await dio.download(
        url.toString(),
        target.path,
        onReceiveProgress: onProgress,
      );
    } on DioException catch (e) {
      throw Exception('${url.host}: ${e.message}');
    }
  }

  static Future<String> _defaultSupportPathResolver() async =>
      (await getApplicationSupportDirectory()).path;
}

/// 读文件头 4 字节做 magic 校验（RandomAccessFile，不整文件载入内存）
Uint8List readGgmlMagic(File file) {
  final raf = file.openSync();
  try {
    return raf.readSync(4);
  } finally {
    raf.closeSync();
  }
}
