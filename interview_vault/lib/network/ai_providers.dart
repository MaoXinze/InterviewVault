/// AI 服务商注册表（PRD 2.2：OpenAI、DeepSeek、Kimi、通义千问、Claude、自定义）。
///
/// W1 只用于配置页预填与鉴权方式判定；W3 模拟面试出题也走这里。
class AiProviderInfo {
  const AiProviderInfo({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.defaultModel,
  });

  final String id;
  final String label;
  final String baseUrl;
  final String defaultModel;
}

const List<AiProviderInfo> aiProviders = [
  AiProviderInfo(
    id: 'openai',
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
  ),
  AiProviderInfo(
    id: 'deepseek',
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
  ),
  AiProviderInfo(
    id: 'kimi',
    label: 'Kimi (Moonshot)',
    baseUrl: 'https://api.moonshot.cn/v1',
    defaultModel: 'moonshot-v1-8k',
  ),
  AiProviderInfo(
    id: 'qwen',
    label: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-plus',
  ),
  AiProviderInfo(
    id: 'anthropic',
    label: 'Claude (Anthropic)',
    baseUrl: 'https://api.anthropic.com',
    defaultModel: 'claude-3-5-haiku-latest',
  ),
  AiProviderInfo(
    id: 'custom',
    label: '自定义 OpenAI 兼容接口',
    baseUrl: '',
    defaultModel: '',
  ),
];

AiProviderInfo providerById(String id) =>
    aiProviders.firstWhere((p) => p.id == id, orElse: () => aiProviders.last);
