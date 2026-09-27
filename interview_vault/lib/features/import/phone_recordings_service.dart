import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'audio_import_service.dart' show supportedAudioExtensions;

/// 手机自带录音机里的一段录音（尚未入库）
class PhoneRecording {
  const PhoneRecording({
    required this.sourceUri,
    required this.fileName,
    this.durationMs,
    this.sizeBytes = 0,
    this.recordedAt,
  });

  /// content:// uri（Android MediaStore）或文件路径
  final String sourceUri;
  final String fileName;
  final int? durationMs;
  final int sizeBytes;
  final DateTime? recordedAt;
}

/// 手机录音机直导：App 内列出系统录音机的录音，点选即复制进库，
/// 免去在系统文件管理器里翻目录（MIUI 录音目录带 .nomedia，
/// 系统选择器里很难找到）。原生侧走 MethodChannel 查 MediaStore。
class PhoneRecordingsService {
  PhoneRecordingsService({
    MethodChannel? channel,
    Future<bool> Function()? permissionAsker,
    bool Function(String targetPath)? verifyCopied,
  })  : _channel = channel ??
            const MethodChannel('interviewvault/phone_recordings'),
        _permissionAsker = permissionAsker ?? _defaultPermissionAsker,
        _verifyCopied =
            verifyCopied ?? _defaultVerifyCopied;

  final MethodChannel _channel;
  final Future<bool> Function() _permissionAsker;
  final bool Function(String targetPath) _verifyCopied;

  /// 请求"音乐和音频"读权限；用户拒绝返回 false
  Future<bool> ensurePermission() => _permissionAsker();

  static Future<bool> _defaultPermissionAsker() async {
    final status = await Permission.audio.request();
    return status.isGranted;
  }

  static bool _defaultVerifyCopied(String targetPath) {
    final f = File(targetPath);
    return f.existsSync() && f.lengthSync() > 0;
  }

  /// 列出手机录音机目录下的音频（按录制时间倒序，原生层排序）。
  /// 平台无实现（web/桌面测试环境）或查询失败一律返回空列表。
  Future<List<PhoneRecording>> list() async {
    try {
      final raw = await _channel.invokeListMethod<Map>('list');
      if (raw == null) return [];
      return [
        for (final item in raw)
          if (_toRecording(item) case final r?) r,
      ];
    } on MissingPluginException {
      return [];
    } on PlatformException {
      return [];
    }
  }

  /// 把选中的录音复制到 [targetPath]（App 库目录）
  Future<void> copyTo(String sourceUri, String targetPath) async {
    await _channel.invokeMethod<void>('copy', {
      'uri': sourceUri,
      'target': targetPath,
    });
    // 复制完成后校验落盘，避免半截文件进入确认页
    if (!_verifyCopied(targetPath)) {
      throw const FileSystemException('录音复制失败');
    }
  }

  PhoneRecording? _toRecording(Map item) {
    final uri = item['sourceUri'] as String?;
    final name = item['fileName'] as String? ?? '';
    if (uri == null || uri.isEmpty || name.isEmpty) return null;
    final ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    if (!supportedAudioExtensions.contains(ext)) return null;
    final recordedMs = (item['recordedAt'] as num?)?.toInt();
    return PhoneRecording(
      sourceUri: uri,
      fileName: name,
      durationMs: (item['durationMs'] as num?)?.toInt(),
      sizeBytes: (item['sizeBytes'] as num?)?.toInt() ?? 0,
      recordedAt:
          recordedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(recordedMs),
    );
  }
}
