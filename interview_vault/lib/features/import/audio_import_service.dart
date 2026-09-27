import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// 可导入的音频格式（PRD 2.3）
const supportedAudioExtensions = ['mp3', 'wav', 'm4a', 'aac', 'ogg'];

/// 用户从系统文件选择器选中的音频（尚未入库）。
class PickedAudio {
  const PickedAudio({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
  });

  /// file_picker 给出的可读路径（Android 为缓存副本路径）
  final String path;
  final String fileName;
  final int sizeBytes;
}

/// 入库前展示给用户的格式确认信息（PRD 2.3：时长、大小、格式）。
class ImportedAudioInfo {
  const ImportedAudioInfo({
    required this.source,
    required this.format,
    required this.duration,
  });

  final PickedAudio source;

  /// 小写扩展名；识别不出为 '未知'
  final String format;

  /// 时长探测失败（编解码器不支持等）为 null，UI 降级展示
  final Duration? duration;
}

/// 音频导入：系统选择器 → 格式确认信息 → 确认后复制进库目录。
/// 导入副本归 App 托管（删除面试时随行删除，与录音同一套"删除即真删"语义）。
/// web 端 file_picker 不给文件路径，导入仅 Android/桌面可用。
class AudioImportService {
  AudioImportService({
    Future<PickedAudio?> Function()? picker,
    Future<Duration?> Function(String path)? durationProbe,
    Future<String> Function()? documentsPathResolver,
  })  : _pick = picker ?? _defaultPicker,
        _durationProbe = durationProbe ?? probeAudioDuration,
        _documentsPathResolver =
            documentsPathResolver ?? _defaultDocumentsPath;

  final Future<PickedAudio?> Function() _pick;
  final Future<Duration?> Function(String path) _durationProbe;
  final Future<String> Function() _documentsPathResolver;

  /// 系统文件选择器；用户取消返回 null
  Future<PickedAudio?> pick() => _pick();

  /// 系统文件选择器；用户取消返回 null。
  /// web 端拿不到 path（bytes 模式），视为不可导入返回 null。
  static Future<PickedAudio?> _defaultPicker() async {
    // file_picker 13.x 为静态 API，直接返回文件列表
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedAudioExtensions,
    );
    if (files.isEmpty) return null;
    final file = files.first;
    final path = file.path;
    if (path == null) return null;
    final size = file.lengthSync() ?? await file.length() ?? 0;
    return PickedAudio(path: path, fileName: file.name, sizeBytes: size);
  }

  static Future<String> _defaultDocumentsPath() async =>
      (await getApplicationDocumentsDirectory()).path;

  /// 汇总格式确认页所需信息
  Future<ImportedAudioInfo> inspect(PickedAudio audio) async {
    return ImportedAudioInfo(
      source: audio,
      format: _extensionOf(audio.fileName),
      duration: await _durationProbe(audio.path),
    );
  }

  /// 确认导入：复制进 `<docs>/recordings/imports/`，返回库内最终路径。
  /// 源文件（缓存副本）不动，失败时抛出由 UI 提示。
  Future<String> importFile(PickedAudio audio) async {
    final docsPath = await _documentsPathResolver();
    final importsPath = '$docsPath/recordings/imports';
    await Directory(importsPath).create(recursive: true);
    final ext = _extensionOf(audio.fileName);
    final base = sanitizeFileName(audio.fileName);
    // 原名可能自带扩展名（大小写不一）：去掉后再统一拼目标后缀，
    // 避免 round_2.wav → round_2.wav.wav
    final suffix = '.$ext';
    final stem = (ext != '未知' && base.toLowerCase().endsWith(suffix))
        ? base.substring(0, base.length - suffix.length)
        : base;
    final stampedName =
        'interview_${DateTime.now().millisecondsSinceEpoch}_$stem';
    final target = ext == '未知'
        ? '$importsPath/$stampedName'
        : '$importsPath/$stampedName.$ext';
    await File(audio.path).copy(target);
    return target;
  }

  /// 时长探测默认实现：just_audio 读元数据（不整体解码）。
  /// 编解码器不支持/路径失效等一律返回 null，由 UI 降级。
  static Future<Duration?> probeAudioDuration(String path) async {
    final player = AudioPlayer();
    try {
      await player.setFilePath(path);
      return player.duration;
    } on Exception {
      return null;
    } finally {
      await player.dispose();
    }
  }

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '未知';
    return fileName.substring(dot + 1).toLowerCase();
  }
}

/// 文件名清洗：剥掉任何路径成分与文件系统非法字符，限长 120。
/// 清洗后不含任何字母/数字/汉字（全非法名）时兜底为固定名。
String sanitizeFileName(String fileName) {
  final baseName = fileName.split(Platform.pathSeparator).last.split('/').last;
  final cleaned = baseName.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  final trimmed = cleaned.trim();
  final hasContent = RegExp(r'[a-zA-Z0-9\u4e00-\u9fff]').hasMatch(trimmed);
  if (trimmed.isEmpty || !hasContent) return 'imported_audio';
  return trimmed.length > 120 ? trimmed.substring(trimmed.length - 120) : trimmed;
}
