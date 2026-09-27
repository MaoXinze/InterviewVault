import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/features/import/phone_recordings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('interviewvault/phone_recordings');
  late PhoneRecordingsService service;
  late Object? Function(MethodCall call) handler;

  setUp(() {
    service = PhoneRecordingsService(verifyCopied: (_) => true);
    handler = (_) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => handler(call));
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('list', () {
    test('解析原生返回的录音列表，按扩展名白名单过滤', () async {
      handler = (call) => [
            {
              'sourceUri': 'content://media/external/audio/media/1',
              'sourcePath': '/sdcard/Recordings/2026-09-27.m4a',
              'fileName': '2026-09-27 面试录音.m4a',
              'durationMs': 65000,
              'sizeBytes': 1024,
              'recordedAt': 1790000000000,
            },
            {
              // 不在支持格式内（amr），应被过滤
              'sourceUri': 'content://media/external/audio/media/2',
              'sourcePath': '/sdcard/MIUI/sound_recorder/old.amr',
              'fileName': 'old.amr',
              'durationMs': 1000,
              'sizeBytes': 100,
              'recordedAt': 1790000000000,
            },
          ];

      final rows = await service.list();
      expect(rows.length, 1);
      expect(rows.first.fileName, '2026-09-27 面试录音.m4a');
      expect(rows.first.durationMs, 65000);
      expect(rows.first.sourceUri, contains('media/1'));
    });

    test('无原生实现（web/测试环境）返回空列表不抛错', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      final rows = await service.list();
      expect(rows, isEmpty);
    });

    test('原生查询出错返回空列表', () async {
      handler = (call) => throw PlatformException(code: 'query_failed');
      final rows = await service.list();
      expect(rows, isEmpty);
    });
  });

  group('copyTo', () {
    test('传递 uri 与目标路径给原生层', () async {
      MethodCall? received;
      handler = (call) {
        if (call.method == 'copy') received = call;
        return null;
      };
      await service.copyTo(
        'content://media/external/audio/media/9',
        '/data/user/0/app/files/rec.m4a',
      );
      expect(received?.method, 'copy');
      expect(received?.arguments['uri'], contains('media/9'));
      expect(received?.arguments['target'], '/data/user/0/app/files/rec.m4a');
    });

    test('原生复制失败抛出', () async {
      handler = (call) => throw PlatformException(code: 'copy_failed');
      await expectLater(
        service.copyTo('content://x', '/tmp/a.m4a'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
