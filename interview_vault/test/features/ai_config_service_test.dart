import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/data/secure/key_storage.dart';
import 'package:interview_vault/features/api_key/ai_config_service.dart';
import 'package:mocktail/mocktail.dart';

/// 内存 Map 实现的 KeyStorage 替身（不落任何真实 Key）
class _FakeKeyStorage extends Mock implements KeyStorage {
  final Map<String, String> store = {};

  @override
  Future<void> write(String provider, String key) async =>
      store['apikey.$provider'] = key;

  @override
  Future<String?> read(String provider) async => store['apikey.$provider'];

  @override
  Future<void> delete(String provider) async => store.remove('apikey.$provider');

  @override
  Future<bool> has(String provider) async => store.containsKey('apikey.$provider');
}

void main() {
  late AppDatabase db;
  late _FakeKeyStorage keyStorage;
  late AiConfigService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    keyStorage = _FakeKeyStorage();
    service = AiConfigService(db: db, keyStorage: keyStorage);
  });
  tearDown(() async => db.close());

  test('保存配置：DB 只存 provider/model/baseUrl，Key 只进 secure storage', () async {
    await service.saveActiveConfig(
      provider: 'deepseek',
      modelName: 'deepseek-chat',
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'sk-IN-MEMORY-ONLY',
    );

    // DB 侧：结构性保证无 Key 字段（执行修订 #5）
    final row = await db.aiConfigsDao.getActive();
    expect(row, isNotNull);
    expect(row!.provider, 'deepseek');
    expect(row.toJson().keys.any((k) => k.toLowerCase().contains('key')),
        isFalse);
    expect(row.isActive, isTrue);

    // Key 侧：secure storage
    expect(await keyStorage.read('deepseek'), 'sk-IN-MEMORY-ONLY');
  });

  test('删除 Key：secure storage 清除，配置行保留但取消激活', () async {
    await service.saveActiveConfig(
      provider: 'openai',
      modelName: 'gpt-4o-mini',
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-TO-BE-DELETED',
    );

    await service.deleteActive();

    expect(await keyStorage.read('openai'), isNull);
    expect(await db.aiConfigsDao.getActive(), isNull);
    // 配置行仍在，用户下次只需重填 Key
    expect((await db.aiConfigsDao.getAll()).length, 1);
  });

  test('未配置时 testActiveConnection 返回未配置提示', () async {
    final result = await service.testActiveConnection();
    expect(result.success, isFalse);
    expect(result.message, contains('未配置'));
  });
}
