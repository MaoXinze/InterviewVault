import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/data/secure/key_storage.dart';
import 'package:interview_vault/features/api_key/presentation/api_key_page.dart';
import 'package:interview_vault/features/api_key/providers.dart';
import 'package:mocktail/mocktail.dart';

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

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    keyStorage = _FakeKeyStorage();
  });
  tearDown(() async => db.close());

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          keyStorageProvider.overrideWithValue(keyStorage),
        ],
        child: const MaterialApp(home: ApiKeyPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('页面包含服务商选择、Key/模型/BaseURL 输入、连接测试、保存、扣费提示', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('服务商'), findsOneWidget);
    expect(find.byKey(const Key('field_api_key')), findsOneWidget);
    expect(find.byKey(const Key('field_model')), findsOneWidget);
    expect(find.byKey(const Key('field_base_url')), findsOneWidget);
    expect(find.text('连接测试'), findsOneWidget);
    expect(find.byKey(const Key('btn_save')), findsOneWidget);
    expect(find.text('AI 调用由你的账户扣费'), findsOneWidget);
    // 默认预填 OpenAI
    expect(find.byKey(const Key('field_base_url')), findsOneWidget);
  });

  testWidgets('保存：Key 只进 secure storage，DB 生成激活配置（无 Key 字段）', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('field_api_key')),
      'sk-WIDGET-TEST',
    );
    await tester.tap(find.byKey(const Key('btn_save')));
    await tester.pumpAndSettle();

    expect(keyStorage.read('openai'), completion('sk-WIDGET-TEST'));
    final row = await db.aiConfigsDao.getActive();
    expect(row, isNotNull);
    expect(row!.provider, 'openai');
    expect(
      row.toJson().keys.any((k) => k.toLowerCase().contains('key')),
      isFalse,
    );
  });

  testWidgets('切换到自定义服务商时 Base URL 清空可填', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义 OpenAI 兼容接口').last);
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.byKey(const Key('field_base_url')),
    );
    expect(field.controller!.text, isEmpty);
  });
}
