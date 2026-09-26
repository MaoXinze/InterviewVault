/// 本地音频文件工具：目录保障与"删除即真删"（AGENTS 铁律 3）。
/// IO 实现走 dart:io；web 无本地文件系统，替换为空实现。
library;

export 'audio_files_stub.dart' if (dart.library.io) 'audio_files_io.dart';
