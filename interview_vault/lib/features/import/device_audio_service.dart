import 'package:on_audio_query/on_audio_query.dart';

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

  /// MediaStore 物理路径（Android 11+ 授予媒体读权限后可直接按路径读取）
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

/// 本机音频浏览服务：MediaStore 查询 + 音频媒体权限。
/// 全程本机，不上传任何内容（PRD 铁律）。
class DeviceAudioService {
  DeviceAudioService({OnAudioQuery? query}) : _query = query ?? OnAudioQuery();

  final OnAudioQuery _query;

  /// 检查并请求音频媒体权限（READ_MEDIA_AUDIO / 旧版 READ_EXTERNAL_STORAGE）。
  /// 平台不支持（测试环境/无插件实现）时返回 denied，由 UI 引导。
  Future<DeviceAudioPermission> ensurePermission() async {
    try {
      if (await _query.permissionsStatus()) {
        return DeviceAudioPermission.granted;
      }
      final granted = await _query.permissionsRequest();
      return granted
          ? DeviceAudioPermission.granted
          : DeviceAudioPermission.denied;
    } catch (_) {
      return DeviceAudioPermission.denied;
    }
  }

  /// 全部本机音频，按加入媒体库时间倒序（最近的排最前）。
  /// 查询失败返回空列表（UI 走"没找到"空态，仍可用系统选择器兜底）。
  Future<List<DeviceAudio>> listAudios() async {
    try {
      final songs = await _query.querySongs(
        sortType: SongSortType.DATE_ADDED,
        orderType: OrderType.DESC_OR_GREATER,
        uriType: UriType.EXTERNAL,
      );
      return [
        for (final song in songs)
          if (song.data.isNotEmpty)
            DeviceAudio(
              path: song.data,
              title: song.displayName,
              sizeBytes: song.size,
              album: song.album,
              durationMs: song.duration,
              addedAt: song.dateAdded == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(song.dateAdded! * 1000),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}
