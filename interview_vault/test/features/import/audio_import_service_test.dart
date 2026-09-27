import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/features/import/audio_import_service.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('iv_import_service_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  PickedAudio picked(String fileName) {
    final source = File('${tmp.path}/source/$fileName')
      ..createSync(recursive: true)
      ..writeAsStringSync('fake-audio-bytes');
    return PickedAudio(path: source.path, fileName: fileName, sizeBytes: 17);
  }

  AudioImportService buildService({String? docsPath}) => AudioImportService(
        picker: () async => null,
        durationProbe: (_) async => const Duration(seconds: 42),
        documentsPathResolver: () async => docsPath ?? tmp.path,
      );

  group('inspect', () {
    test('扩展名归一为小写格式，时长来自探测', () async {
      final info = await buildService().inspect(picked('大厂面试真题.MP3'));
      expect(info.format, 'mp3');
      expect(info.duration, const Duration(seconds: 42));
      expect(info.source.sizeBytes, 17);
    });

    test('无扩展名 / 以点结尾 → 未知格式', () async {
      expect((await buildService().inspect(picked('no-ext'))).format, '未知');
      expect((await buildService().inspect(picked('dot.'))).format, '未知');
    });

    test('时长探测失败降级为 null，不阻断确认流程', () async {
      final service = AudioImportService(
        picker: () async => null,
        durationProbe: (_) async => null,
        documentsPathResolver: () async => tmp.path,
      );
      final info = await service.inspect(picked('a.wav'));
      expect(info.duration, isNull);
      expect(info.format, 'wav');
    });
  });

  group('importFile', () {
    test('复制到 <docs>/recordings/imports/，内容与格式保留', () async {
      final info = await buildService().inspect(picked('round_2.wav'));
      final stored = await buildService().importFile(info.source);

      expect(stored, contains('${tmp.path}/recordings/imports/'));
      expect(stored, endsWith('.wav'));
      final copied = File(stored);
      expect(copied.existsSync(), isTrue);
      expect(copied.readAsStringSync(), 'fake-audio-bytes');
    });

    test('不合法格式（未知扩展名）也能入库，无扩展名后缀', () async {
      final service = buildService();
      final stored = await service.importFile(picked('mystery'));
      expect(stored, endsWith('mystery'));
      expect(File(stored).existsSync(), isTrue);
    });

    test('原名自带扩展名（大小写不一）不产生双后缀', () async {
      final stored = await buildService().importFile(picked('round_2.MP3'));
      expect(stored, endsWith('.mp3'));
      expect(stored.toLowerCase(), isNot(contains('.mp3.mp3')));
    });
  });

  group('sanitizeFileName', () {
    test('剥掉路径成分与非法字符，保留正常中文名', () {
      expect(sanitizeFileName('大厂面试真题.MP3'), '大厂面试真题.MP3');
      expect(sanitizeFileName(r'a\b\c.mp3'), 'c.mp3');
      expect(sanitizeFileName('a/b/c.mp3'), 'c.mp3');
      // :*?"<>| 共 7 个非法字符 → 7 个下划线
      expect(sanitizeFileName('weird:*?"<>|.m4a'), 'weird${'_' * 7}.m4a');
    });

    test('全非法名兜底为固定名；超长名截断保留尾部（含扩展名）', () {
      expect(sanitizeFileName('   '), 'imported_audio');
      expect(sanitizeFileName('\x00\x01'), 'imported_audio');
      expect(sanitizeFileName('____'), 'imported_audio');
      final long = '${'长' * 200}.mp3';
      final cleaned = sanitizeFileName(long);
      expect(cleaned.length, lessThanOrEqualTo(120));
      expect(cleaned, endsWith('.mp3'));
    });
  });
}
