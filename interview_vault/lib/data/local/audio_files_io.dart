import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 确保录音目录存在——record 插件按传入路径直接建文件，不会自建父目录；
/// 父目录缺失时原生线程抛 FileNotFoundException，且该错误不回传 start() 的
/// Future（详见 RecorderService 的 onStateChanged 订阅），因此必须在
/// start 前主动建目录，否则新装设备首录会静默产生空记录。
Future<void> ensureRecordingsDir() async {
  final dir = await getApplicationDocumentsDirectory();
  await Directory('${dir.path}/recordings').create(recursive: true);
}

/// 删除本地音频文件。尽力而为：只删应用文档目录内的文件（录音与导入
/// 副本都落在这里），路径不存在或删除失败都静默放过——文件清理不能
/// 阻断删除记录的 UI 流程，孤儿文件可由后续清理功能兜底。
Future<void> deleteAudioFile(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    final docsPath = (await getApplicationDocumentsDirectory()).path;
    final file = File(path);
    if (!file.absolute.path.startsWith(Directory(docsPath).absolute.path)) {
      return;
    }
    if (await file.exists()) await file.delete();
  } on Exception {
    // 尽力而为，见上
  }
}
