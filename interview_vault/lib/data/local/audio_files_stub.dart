/// web 端无本地文件系统：录音为会话级地址（MediaRecorder blob），
/// 无目录可建、无文件可删，替换为空实现。
Future<void> ensureRecordingsDir() async {}

Future<void> deleteAudioFile(String? path) async {}
