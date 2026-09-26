import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/local/audio_files.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String> getApplicationDocumentsPath() async => documentsPath;
}

/// 录音文件落位与"删除即真删"的安全边界。
void main() {
  late Directory tmp;
  late PathProviderPlatform original;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('iv_audio_files_test');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = original;
    tmp.deleteSync(recursive: true);
  });

  test('ensureRecordingsDir：在文档目录下建 recordings（含多级）', () async {
    await ensureRecordingsDir();
    expect(Directory('${tmp.path}/recordings').existsSync(), isTrue);
  });

  test('deleteAudioFile：删除文档目录内的文件', () async {
    final file = File('${tmp.path}/recordings/interview_1.wav')
      ..createSync(recursive: true)
      ..writeAsStringSync('pcm');
    await deleteAudioFile(file.path);
    expect(file.existsSync(), isFalse);
  });

  test('deleteAudioFile：文档目录外的路径拒绝删除（防误删用户文件）', () async {
    final outside = File('${Directory.systemTemp.path}/iv_outside_should_stay.wav')
      ..createSync()
      ..writeAsStringSync('keep');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync();
    });

    await deleteAudioFile(outside.path);
    expect(outside.existsSync(), isTrue);
  });

  test('deleteAudioFile：空路径 / 不存在的路径静默放过', () async {
    await deleteAudioFile(null);
    await deleteAudioFile('');
    await deleteAudioFile('${tmp.path}/recordings/never_existed.wav');
  });
}
