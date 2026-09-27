import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/features/transcription/whisper_model_manager.dart';

/// ggml 模型文件的合法头两个 magic 之一（见实现注释）。
final validMagic = Uint8List.fromList('lmgg'.codeUnits);

/// 带填充的合法模型体（12 字节，测试注入 minModelBytes=8）
final validModel = Uint8List(12)..setRange(0, 4, validMagic);

void main() {
  late Directory supportDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('iv_models_test');
  });
  tearDown(() async {
    if (await supportDir.exists()) await supportDir.delete(recursive: true);
  });

  WhisperModelManager manager({
    required Future<void> Function(Uri url, File target,
            void Function(int received, int total)? onProgress)
        downloader,
  }) =>
      WhisperModelManager(
        supportPathResolver: () async => supportDir.path,
        downloader: downloader,
        minModelBytes: 8,
      );

  /// 伪下载器：按 host 决定行为，写什么由 [payload] 决定
  Future<void> Function(Uri, File, void Function(int, int)?) fakeWriter(
    Uint8List payload, {
    Uri? failHost,
  }) =>
      (url, target, onProgress) async {
        if (url.host == failHost?.host) {
          throw Exception('网络错误: $url');
        }
        await target.writeAsBytes(payload, flush: true);
        onProgress?.call(payload.length, payload.length);
      };

  group('modelPath / isDownloaded / delete', () {
    test('modelPath 符合 whisper.cpp 约定 <support>/ggml-<name>.bin', () async {
      final m = manager(downloader: (url, target, _) async {});
      final path = await m.modelPath(TranscribeModel.base);
      expect(path, endsWith('ggml-base.bin'));
      final pathSmall = await m.modelPath(TranscribeModel.small);
      expect(pathSmall, endsWith('ggml-small.bin'));
    });

    test('未下载/已下载/删除 roundtrip', () async {
      final m = manager(downloader: fakeWriter(validModel));
      expect(await m.isDownloaded(TranscribeModel.base), isFalse);

      await m.download(TranscribeModel.base);
      expect(await m.isDownloaded(TranscribeModel.base), isTrue);
      expect(await m.modelPath(TranscribeModel.base),
          endsWith('ggml-base.bin'));

      await m.delete(TranscribeModel.base);
      expect(await m.isDownloaded(TranscribeModel.base), isFalse);
    });

    test('delete 不存在时不抛错', () async {
      final m = manager(downloader: fakeWriter(validModel));
      await m.delete(TranscribeModel.small);
    });
  });

  group('download', () {
    test('下载成功：文件落位、进度事件广播、无 .part 残留', () async {
      final m = manager(downloader: fakeWriter(validModel));
      final events = <ModelDownloadEvent>[];
      m.events.listen(events.add);

      await m.download(TranscribeModel.base,
          onProgress: (r, t) => events.add(const ModelDownloadEvent(
              TranscribeModel.base, ModelDownloadPhase.downloading, 100)));

      final file = File(await m.modelPath(TranscribeModel.base));
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), validModel);
      expect(
          File('${file.path}.part').existsSync(), isFalse,
          reason: '.part 临时文件必须被改名消费掉');
      expect(
          events.any((e) => e.phase == ModelDownloadPhase.done), isTrue,
          reason: '成功后广播 done 事件');
    });

    test('主源失败自动回退镜像源', () async {
      final usedUrls = <Uri>[];
      final m = manager(
        downloader: (url, target, onProgress) async {
          usedUrls.add(url);
          if (url.host.contains('huggingface.co')) {
            throw Exception('主源不可达');
          }
          await target.writeAsBytes(validModel, flush: true);
        },
      );

      await m.download(TranscribeModel.base);

      expect(usedUrls.length, 2, reason: '先主源后镜像');
      expect(usedUrls.first.host, contains('huggingface.co'));
      expect(usedUrls.last.host, contains('hf-mirror.com'));
      expect(await m.isDownloaded(TranscribeModel.base), isTrue);
    });

    test('全部源失败抛 WhisperDownloadException 并广播 failed', () async {
      final m = manager(
        downloader: (url, target, _) async => throw Exception('全挂'),
      );
      final events = <ModelDownloadEvent>[];
      m.events.listen(events.add);

      await expectLater(
        m.download(TranscribeModel.small),
        throwsA(isA<WhisperDownloadException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
          events.any((e) => e.phase == ModelDownloadPhase.failed), isTrue);
      expect(await m.isDownloaded(TranscribeModel.small), isFalse);
    });

    test('内容非法（HTML 错误页）视为失败且不落地', () async {
      final html = Uint8List.fromList('<html>Not Found</html>'.codeUnits);
      final m = manager(downloader: fakeWriter(html));

      await expectLater(
        m.download(TranscribeModel.base),
        throwsA(isA<WhisperDownloadException>()),
      );
      expect(await m.isDownloaded(TranscribeModel.base), isFalse);
      expect(
          File(await m.modelPath(TranscribeModel.base)).existsSync(),
          isFalse);
    });

    test('同一模型重复下载直接复用已完成文件（不重复下载）', () async {
      var calls = 0;
      final m = manager(
        downloader: (url, target, _) async {
          calls++;
          await target.writeAsBytes(validModel, flush: true);
        },
      );
      await m.download(TranscribeModel.base);
      await m.download(TranscribeModel.base);
      expect(calls, 1);
    });

    test('下载中重复调用返回同一个进行中的任务', () async {
      final gate = Completer<void>();
      final m = manager(
        downloader: (url, target, _) async {
          await gate.future;
          await target.writeAsBytes(validModel, flush: true);
        },
      );
      final f1 = m.download(TranscribeModel.base);
      final f2 = m.download(TranscribeModel.base);
      expect(identical(f1, f2), isTrue, reason: '同模型去重为同任务');

      gate.complete();
      await Future.wait([f1, f2]);
      expect(await m.isDownloaded(TranscribeModel.base), isTrue);
    });

    test('delete 清除下载中状态后可重新下载', () async {
      var calls = 0;
      final m = manager(
        downloader: (url, target, _) async {
          calls++;
          await target.writeAsBytes(validModel, flush: true);
        },
      );
      await m.download(TranscribeModel.base);
      await m.delete(TranscribeModel.base);
      await m.download(TranscribeModel.base);
      expect(calls, 2);
    });
  });
}
