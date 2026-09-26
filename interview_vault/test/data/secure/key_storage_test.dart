import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/secure/key_storage.dart';
import 'package:mocktail/mocktail.dart';

/// flutter_secure_storage 是平台插件，单测里用 mock 替身；
/// Key 严禁出现在日志/数据库——本文件也不得把真实 Key 写进仓库。
class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecureStorage raw;
  late KeyStorage storage;

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() {
    raw = _MockSecureStorage();
    storage = KeyStorage(raw);
  });

  test('write 按 provider 命名空间写入（apikey.<provider>）', () async {
    when(() => raw.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});

    await storage.write('deepseek', 'sk-test-***');

    final captured = verify(
      () => raw.write(key: captureAny(named: 'key'), value: any(named: 'value')),
    ).captured;
    expect(captured.single, 'apikey.deepseek');
  });

  test('read 只读取自己命名空间下的键', () async {
    when(() => raw.read(key: any(named: 'key'))).thenAnswer((_) async => null);

    await storage.read('openai');

    final captured =
        verify(() => raw.read(key: captureAny(named: 'key'))).captured;
    expect(captured.single, 'apikey.openai');
  });

  test('delete 删除对应 provider 的键', () async {
    when(() => raw.delete(key: any(named: 'key'))).thenAnswer((_) async {});

    await storage.delete('kimi');

    final captured =
        verify(() => raw.delete(key: captureAny(named: 'key'))).captured;
    expect(captured.single, 'apikey.kimi');
  });

  test('has 反映 containsKey 结果', () async {
    when(() => raw.containsKey(key: any(named: 'key')))
        .thenAnswer((_) async => true);

    expect(await storage.has('qwen'), isTrue);
  });
}
