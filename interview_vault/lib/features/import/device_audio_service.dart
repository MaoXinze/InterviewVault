import 'package:flutter/services.dart';

/// 本机音频读取授权状态。
enum DeviceAudioPermission { granted, denied }

/// 本机音频摘要（MediaStore），用于 App 内直接点选导入——
/// 免去用户在系统文件管理器里逐级翻目录。
class DeviceAudio {
  const DeviceAudio({
    required this.path,
    required this.title,
    required this.sizeBytes,
    this.album,
    this.durationMs,
    this.addedAt,
  });

  /// MediaStore 物理路径（授予权限后可直接按路径读取）
  final String path;

  /// 展示名（带扩展名的文件名，最贴近"找文件"的心智）
  final String title;
  final int sizeBytes;
  final String? album;

  /// MediaStore 时长（毫秒）；读不到为 null
  final int? durationMs;

  /// 加入媒体库的时间（按此倒序 = 最近录音/下载排最前）
  final DateTime? addedAt;
}

/// 本机音频浏览服务：经 "device_audio" MethodChannel 查 MediaStore
/// + 管理音频媒体权限。全程本机，不上传任何内容（PRD 铁律）。
class DeviceAudioService {
  DeviceAudioService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('device_audio');

  final MethodChannel _channel;

  /// 检查并请求音频媒体读权限（READ_MEDIA_AUDIO / 旧版 READ_EXTERNAL_STORAGE）。
  /// 平台不支持（测试环境/无宿主实现）时返回 denied，由 UI 引导。
  Future<DeviceAudioPermission> ensurePermission() async {
    try {
      if (await _channel.invokeMethod<bool>('permissionStatus') ?? false) {
        return DeviceAudioPermission.granted;
      }
      final granted =
          await _channel.invokeMethod<bool>('requestPermission') ?? false;
      return granted
          ? DeviceAudioPermission.granted
          : DeviceAudioPermission.denied;
    } catch (_) {
      return DeviceAudioPermission.denied;
    }
  }

  /// 全部本机音频，按加入媒体库时间倒序（最近的排最前）。
  /// 未授权/查询失败返回空列表（UI 走"没找到"空态，仍可用系统选择器兜底）。
  Future<List<DeviceAudio>> listAudios() async {
    try {
      final rows = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'listAudios',
      );
      return [
        for (final row in rows ?? const <Map<dynamic, dynamic>>[])
          DeviceAudio(
            path: row['path'] as String,
            title: (row['title'] as String?) ?? '未命名音频',
            sizeBytes: (row['sizeBytes'] as num?)?.toInt() ?? 0,
            album: row['album'] as String?,
            durationMs: (row['durationMs'] as num?)?.toInt(),
            addedAt: row['addedAtSec'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    (row['addedAtSec'] as num).toInt() * 1000,
                  ),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 取走录音机等应用"分享到面试宝库"送来的音频；没有则返回 null，取走即清空。
  /// 背景：MIUI/HyperOS 录音机把录音存在应用私有目录（Android/data/…/files/），
  /// Android 11+ 任何第三方都读不到该目录且 MediaStore 不收录——系统分享
  /// 是拿到这类文件的唯一入口。原生侧已把内容拷贝到 App 缓存目录，
  /// path 可直接读取/入库（复用 PickedAudio → 确认卡 → importFile 管线）。
  Future<DeviceAudio?> takeSharedAudio() async {
    try {
      final row =
          await _channel.invokeMapMethod<String, dynamic>('takeSharedAudio');
      if (row == null) return null;
      return DeviceAudio(
        path: row['path'] as String,
        title: (row['title'] as String?) ?? '未命名音频',
        sizeBytes: (row['sizeBytes'] as num?)?.toInt() ?? 0,
        addedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}
