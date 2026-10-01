import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interview_vault/features/import/device_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('device_audio');

  /// 通道桩：mock handler 直接回原始对象，框架用通道 codec 自动编码
  void stubChannel(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('takeSharedAudio（录音机分享接收）', () {
    test('有待处理分享：映射为 DeviceAudio（路径/文件名/大小）', () async {
      stubChannel((call) {
        expect(call.method, 'takeSharedAudio');
        return {
          'path': '/data/user/0/app/cache/shared_audio/9月16日 下午5点00分.m4a',
          'title': '9月16日 下午5点00分.m4a',
          'sizeBytes': 58287391,
        };
      });
      final service = DeviceAudioService();
      final audio = await service.takeSharedAudio();
      expect(audio, isNotNull);
      expect(audio!.path, '/data/user/0/app/cache/shared_audio/9月16日 下午5点00分.m4a');
      expect(audio.title, '9月16日 下午5点00分.m4a');
      expect(audio.sizeBytes, 58287391);
    });

    test('没有待处理分享：返回 null（不抛错）', () async {
      stubChannel((call) => null);
      final service = DeviceAudioService();
      expect(await service.takeSharedAudio(), isNull);
    });

    test('宿主无通道实现（平台不支持）：降级返回 null', () async {
      stubChannel((call) => throw MissingPluginException());
      final service = DeviceAudioService();
      expect(await service.takeSharedAudio(), isNull);
    });
  });
}
