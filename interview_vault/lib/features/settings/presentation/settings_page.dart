import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../export/markdown_export_service.dart';

/// 我的 Tab：API 服务配置（真实可用）、主题圆形扩散切换、数据管理占位、隐私占位。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// 定位深色开关：圆形主题扩散的触发点
  final GlobalKey _darkTileKey = GlobalKey();

  void _toggleTheme(bool dark) {
    void applyTheme() => ref
        .read(themeModeProvider.notifier)
        .set(dark ? ThemeMode.dark : ThemeMode.light);
    final box =
        _darkTileKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      applyTheme();
      return;
    }
    // 开关在行尾：取行右侧、垂直居中附近的点作为扩散圆心
    final center =
        box.localToGlobal(Offset(box.size.width - 56, box.size.height / 2));
    ref.read(themeRevealControllerProvider).reveal(
          center: center,
          applyTheme: applyTheme,
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
          reducedMotion: prefersReducedMotion(context),
        );
  }

  /// 导出方式选择（PRD 2.10：全量数据导出为 JSON + Markdown）
  void _chooseExport(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('btn_export_json'),
              leading: const Icon(Icons.data_object),
              title: const Text('全量 JSON'),
              subtitle: const Text('六表结构化备份，schema 带版本号'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _runExport(
                  context,
                  ref.read(dataManagementServiceProvider).exportAllJson,
                );
              },
            ),
            ListTile(
              key: const Key('btn_export_md'),
              leading: const Icon(Icons.description_outlined),
              title: const Text('全量 Markdown'),
              subtitle: const Text('全部面试的复盘文稿合并导出'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _runExport(
                  context,
                  ref.read(dataManagementServiceProvider).exportAllMarkdown,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runExport(
    BuildContext context,
    Future<ExportedFile> Function() run,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await run();
      await ref.read(markdownSharerProvider)(result.path);
      messenger.showSnackBar(
        SnackBar(content: Text('已导出 ${result.fileName}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除全部数据？'),
        content: const Text(
          '将删除所有面试记录、逐字稿、标注、问题卡片、自定义标签、'
          'AI 配置与 API Key，录音文件一并清除。删除即真删，不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('btn_delete_confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result =
          await ref.read(dataManagementServiceProvider).deleteAllData();
      messenger.showSnackBar(
        SnackBar(content: Text('已删除 ${result.deletedInterviews} 场面试记录')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                ListTile(
                  leading: const Icon(Icons.graphic_eq),
                  title: const Text('转写模型管理'),
                  subtitle: const Text('下载/删除本地 Whisper 模型，离线转写'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/models'),
                ),
                KeyedSubtree(
                  key: _darkTileKey,
                  child: SwitchListTile(
                    key: const Key('settings_dark_mode'),
                    secondary: const Icon(Icons.dark_mode),
                    title: const Text('深色模式'),
                    value: themeMode == ThemeMode.dark,
                    onChanged: _toggleTheme,
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
                  key: const Key('btn_export_data'),
                  leading: const Icon(Icons.file_download),
                  title: const Text('数据导出'),
                  subtitle: const Text('全量 JSON 备份 / 全量 Markdown 复盘'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _chooseExport(context),
                ),
                ListTile(
                  key: const Key('btn_delete_all'),
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('删除全部数据'),
                  subtitle: const Text('删除即真删，录音文件一并清除'),
                  onTap: () => _confirmDeleteAll(context),
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
