import 'dart:async';

import 'package:drift/drift.dart';

import '../../data/database/app_database.dart';
import '../../data/secure/key_storage.dart';
import '../../network/ai_providers.dart';
import '../../network/llm_client.dart';

/// 把 ai_configs（DB，无 Key）与 KeyStorage（Key 本体）拼成一个配置面。
///
/// 每个服务商一行配置（id=cfg-provider），激活配置全局唯一；
/// Key 本体永远只经过 KeyStorage。
class AiConfigService {
  AiConfigService({required this.db, required this.keyStorage});

  final AppDatabase db;
  final KeyStorage keyStorage;

  Future<void> saveActiveConfig({
    required String provider,
    required String modelName,
    required String baseUrl,
    required String apiKey,
  }) async {
    final id = 'cfg-$provider';
    await db.aiConfigsDao.upsert(
      AiConfigsCompanion.insert(
        id: id,
        provider: provider,
        modelName: Value(modelName),
        baseUrl: Value(baseUrl),
      ),
    );
    await db.aiConfigsDao.setActive(id);
    await keyStorage.write(provider, apiKey);
  }

  Future<AiConfig?> activeConfig() => db.aiConfigsDao.getActive();

  Future<String?> activeApiKey() async {
    final config = await activeConfig();
    if (config == null) return null;
    return keyStorage.read(config.provider);
  }

  /// 用户可随时删除 Key：secure storage 清除 + 取消激活，配置行保留。
  Future<void> deleteActive() async {
    final config = await activeConfig();
    if (config != null) {
      await keyStorage.delete(config.provider);
    }
    await db.aiConfigsDao.clearActive();
  }

  /// 表单直连测试（不落盘）：用页面当前填的值发起一次真实请求。
  Future<LlmTestResult> testConnection({
    required String provider,
    required String modelName,
    required String baseUrl,
    required String apiKey,
  }) {
    if (apiKey.isEmpty) {
      return Future.value(const LlmTestResult.failure('请先填写 API Key'));
    }
    if (baseUrl.isEmpty) {
      return Future.value(const LlmTestResult.failure('请先填写 Base URL'));
    }
    return LlmClient(
      endpoint: AiEndpoint(
        providerId: provider,
        baseUrl: baseUrl,
        modelName: modelName,
      ),
      apiKey: apiKey,
    ).testConnection();
  }

  /// 已有 Key 时仅更新非敏感配置（模型 / BaseURL），不动 secure storage。
  Future<void> updateActiveMeta({
    required String provider,
    required String modelName,
    required String baseUrl,
  }) async {
    final id = 'cfg-$provider';
    await db.aiConfigsDao.upsert(
      AiConfigsCompanion.insert(
        id: id,
        provider: provider,
        modelName: Value(modelName),
        baseUrl: Value(baseUrl),
      ),
    );
    await db.aiConfigsDao.setActive(id);
  }

  /// 未配置 / 未保存 Key → success=false 的提示；否则真实请求一次。
  Future<LlmTestResult> testActiveConnection() async {
    final config = await activeConfig();
    if (config == null) {
      return const LlmTestResult.failure('未配置 AI 服务商');
    }
    final apiKey = await keyStorage.read(config.provider);
    if (apiKey == null || apiKey.isEmpty) {
      return const LlmTestResult.failure('未配置 API Key');
    }
    final baseUrl = config.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      return const LlmTestResult.failure('未配置 Base URL');
    }
    final client = LlmClient(
      endpoint: AiEndpoint(
        providerId: config.provider,
        baseUrl: baseUrl,
        modelName: config.modelName ?? '',
      ),
      apiKey: apiKey,
    );
    return client.testConnection();
  }

  /// W3 模拟面试用：当前激活配置的流式对话客户端；未就绪返回 null。
  Future<LlmClient?> activeChatClient() async {
    final config = await activeConfig();
    final apiKey = config == null ? null : await keyStorage.read(config.provider);
    final baseUrl = config?.baseUrl;
    if (config == null || apiKey == null || baseUrl == null || baseUrl.isEmpty) {
      return null;
    }
    return LlmClient(
      endpoint: AiEndpoint(
        providerId: config.provider,
        baseUrl: baseUrl,
        modelName: config.modelName ?? providerById(config.provider).defaultModel,
      ),
      apiKey: apiKey,
    );
  }
}
