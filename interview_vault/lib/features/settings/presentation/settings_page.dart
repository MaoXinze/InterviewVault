import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';

/// 我的 Tab：API 服务配置（真实可用）、主题切换、数据管理占位、隐私占位。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      key: const Key('page_settings'),
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.vpn_key),
                  title: const Text('API 服务配置'),
                  subtitle: const Text('配置你自己的 AI 服务商与 API Key'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/api-key'),
                ),
                SwitchListTile(
                  key: const Key('settings_dark_mode'),
                  secondary: const Icon(Icons.dark_mode),
                  title: const Text('深色模式'),
                  value: themeMode == ThemeMode.dark,
                  onChanged: (dark) => ref
                      .read(themeModeProvider.notifier)
                      .set(dark ? ThemeMode.dark : ThemeMode.light),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_download),
                  title: const Text('数据导出'),
                  subtitle: const Text('全量 JSON + Markdown（W4 提供）'),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('数据导出将在 W4 提供')),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('数据删除'),
                  subtitle: const Text('单条 / 全部，删除即真删（W4 提供）'),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('数据删除将在 W4 提供')),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('隐私政策'),
                  onTap: () => context.push('/privacy'),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('关于'),
                  subtitle: Text('InterviewVault v1.0.0 · 本地优先 · 无账号无后端'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
