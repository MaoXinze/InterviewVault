import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../network/ai_providers.dart';
import '../../../core/providers.dart';

/// API 服务商配置页（PRD 2.2）。
///
/// 安全：Key 输入框不回显（保存后清空），Key 只经 KeyStorage 进
/// 系统安全存储；页面状态里持有的 Key 不打日志。
class ApiKeyPage extends ConsumerStatefulWidget {
  const ApiKeyPage({super.key});

  @override
  ConsumerState<ApiKeyPage> createState() => _ApiKeyPageState();
}

class _ApiKeyPageState extends ConsumerState<ApiKeyPage> {
  late final TextEditingController _key;
  late final TextEditingController _model;
  late final TextEditingController _baseUrl;
  String _providerId = 'openai';
  bool _saving = false;
  bool _testing = false;
  String? _testMessage;
  bool _testOk = false;
  /// 当前选中服务商在 secure storage 中是否已有 Key（按 provider 判定，
  /// 防止切换服务商后误用旧状态形成"孤儿 Key"）
  bool _currentProviderHasKey = false;

  @override
  void initState() {
    super.initState();
    final preset = providerById(_providerId);
    _key = TextEditingController();
    _model = TextEditingController(text: preset.defaultModel);
    _baseUrl = TextEditingController(text: preset.baseUrl);
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final service = ref.read(aiConfigServiceProvider);
    final config = await service.activeConfig();
    if (!mounted) return;
    if (config != null) {
      final preset = providerById(config.provider);
      setState(() {
        _providerId = config.provider;
        _model.text = config.modelName ?? preset.defaultModel;
        _baseUrl.text = config.baseUrl ?? preset.baseUrl;
      });
    }
    await _refreshKeyState();
  }

  Future<void> _refreshKeyState() async {
    final hasKey = await ref.read(keyStorageProvider).has(_providerId);
    if (!mounted) return;
    setState(() => _currentProviderHasKey = hasKey);
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _onProviderChanged(String? id) async {
    if (id == null || id == _providerId) return;
    final preset = providerById(id);
    setState(() {
      _providerId = id;
      _model.text = preset.defaultModel;
      _baseUrl.text = preset.baseUrl;
      _testMessage = null;
    });
    await _refreshKeyState();
  }

  Future<void> _save() async {
    final apiKey = _key.text.trim();
    if (apiKey.isEmpty && !_currentProviderHasKey) {
      _showSnack('请先填写 API Key');
      return;
    }
    setState(() => _saving = true);
    try {
      final service = ref.read(aiConfigServiceProvider);
      if (apiKey.isNotEmpty) {
        await service.saveActiveConfig(
          provider: _providerId,
          modelName: _model.text.trim(),
          baseUrl: _baseUrl.text.trim(),
          apiKey: apiKey,
        );
        _key.clear();
      } else {
        // 当前服务商已有 Key 且输入框为空：仅更新模型/BaseURL 等非敏感配置
        await service.updateActiveMeta(
          provider: _providerId,
          modelName: _model.text.trim(),
          baseUrl: _baseUrl.text.trim(),
        );
      }
      if (!mounted) return;
      setState(() => _currentProviderHasKey = true);
      _showSnack('已保存（Key 仅存于本机安全存储）');
    } on Exception {
      if (!mounted) return;
      // 不透出异常细节，避免任何携带 Key 的平台层消息进入 UI
      _showSnack('保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final service = ref.read(aiConfigServiceProvider);
      final apiKey = _key.text.trim();
      final result = (apiKey.isNotEmpty)
          ? await service.testConnection(
              provider: _providerId,
              modelName: _model.text.trim(),
              baseUrl: _baseUrl.text.trim(),
              apiKey: apiKey,
            )
          : await service.testActiveConnection();
      if (!mounted) return;
      setState(() {
        _testMessage = result.message;
        _testOk = result.success;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _deleteKey() async {
    await ref.read(aiConfigServiceProvider).deleteKeyFor(_providerId);
    if (!mounted) return;
    setState(() {
      _testMessage = null;
    });
    await _refreshKeyState();
    if (!mounted) return;
    _showSnack('已删除 API Key');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 服务配置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            key: const Key('field_provider'),
            initialValue: _providerId,
            decoration: const InputDecoration(
              labelText: '服务商',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in aiProviders)
                DropdownMenuItem(value: p.id, child: Text(p.label)),
            ],
            onChanged: (v) => _onProviderChanged(v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('field_api_key'),
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Key',
              helperText: _currentProviderHasKey ? '已保存 Key（重填可覆盖）' : '仅保存在本机安全存储',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('field_model'),
            controller: _model,
            decoration: const InputDecoration(
              labelText: '模型名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('field_base_url'),
            controller: _baseUrl,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              helperText: '自定义服务商必填，其余已按官方默认填好',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('连接测试'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                key: const Key('btn_save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
              const Spacer(),
              if (_currentProviderHasKey)
                TextButton(
                  onPressed: _deleteKey,
                  child: const Text('删除 Key'),
                ),
            ],
          ),
          if (_testMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _testMessage!,
                style: TextStyle(
                  color: _testOk
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'AI 调用由你的账户扣费',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'App 不内置 AI、不提供额度；请求由你的设备直连所选服务商，'
            '数据全程不经过任何第三方服务器。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
