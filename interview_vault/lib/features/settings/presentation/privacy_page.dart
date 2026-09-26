import 'package:flutter/material.dart';

/// 隐私政策占位页（W4 提供全文与用户协议）。
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('本地优先承诺', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '你的录音、转写稿、标注、问题卡片全部保存在本机（SQLite + 文件系统），'
            'App 没有任何后端服务器，不上传、不遥测、不统计。',
          ),
          const SizedBox(height: 16),
          Text('API Key 安全', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'AI 服务使用你自己配置的 API Key。Key 只保存在系统安全存储'
            '（Android Keystore / iOS Keychain），不写入数据库与日志；'
            'AI 请求从你的设备直连你配置的服务商，App 不经手任何中转。',
          ),
          const SizedBox(height: 16),
          Text('数据自主', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '你可以随时把全部数据导出为 JSON + Markdown 带走，'
            '也可以随时彻底删除，删除即真删。',
          ),
          const SizedBox(height: 16),
          Text('完整版', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('隐私政策与用户协议全文将在上架前（W4）提供。'),
        ],
      ),
    );
  }
}
