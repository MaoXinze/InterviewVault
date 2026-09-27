import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/motion.dart';
import '../../transcription/whisper_model_manager.dart';

/// 转写模型管理（我的 → 转写模型管理）：base/small 按需下载、删除。
/// 下载在后台持续，离开页面不中断（事件流由 manager 广播）。
class ModelManagePage extends ConsumerStatefulWidget {
  const ModelManagePage({super.key});

  @override
  ConsumerState<ModelManagePage> createState() => _ModelManagePageState();
}

class _ModelManagePageState extends ConsumerState<ModelManagePage> {
  final _downloaded = <TranscribeModel, bool>{};

  @override
  void initState() {
    super.initState();
    _refresh();
    // 下载事件驱动刷新（进度/完成/失败）——UI 不持有下载状态
    ref.read(whisperModelEventsProvider);
    ref.read(whisperModelGatewayProvider).events.listen((_) => _refresh());
  }

  Future<void> _refresh() async {
    final models = ref.read(whisperModelGatewayProvider);
    for (final m in TranscribeModel.values) {
      _downloaded[m] = await models.isDownloaded(m);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 订阅事件流：进度变化触发本页重建（initState 的 listen 只负责刷新缓存）
    ref.watch(whisperModelEventsProvider);

    return Scaffold(
      key: const Key('page_models'),
      appBar: AppBar(title: const Text('转写模型')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '本地 Whisper 模型（whisper.cpp）· 下载后即可离线转写，录音不出设备',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          for (final model in TranscribeModel.values)
            _ModelCard(
              model: model,
              downloaded: _downloaded[model] ?? false,
              onDownload: () => _download(model),
              onDelete: () => _delete(model),
            ),
        ],
      ),
    );
  }

  Future<void> _download(TranscribeModel model) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(whisperModelGatewayProvider).download(model);
      await _refresh();
      messenger.showSnackBar(
          SnackBar(content: Text('${model.modelName} 模型下载完成')));
    } on WhisperDownloadException {
      messenger.showSnackBar(const SnackBar(
        content: Text('模型下载失败：主源与镜像均不可达，请检查网络后重试'),
      ));
    }
  }

  Future<void> _delete(TranscribeModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定删除 ${model.modelName} 模型吗？删除后需重新下载才能转写。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('btn_confirm_delete_model'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(whisperModelGatewayProvider).delete(model);
      await _refresh();
      messenger.showSnackBar(
          SnackBar(content: Text('${model.modelName} 模型已删除')));
    } on StateError {
      messenger.showSnackBar(
          const SnackBar(content: Text('模型正在下载中，无法删除')));
    }
  }
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard({
    required this.model,
    required this.downloaded,
    required this.onDownload,
    required this.onDelete,
  });

  final TranscribeModel model;
  final bool downloaded;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 事件流变化时重建本卡片（下载进度）
    final event = ref.watch(whisperModelEventsProvider).value;
    final models = ref.watch(whisperModelGatewayProvider);
    final downloading = models.isDownloading(model);
    final pct = models.percentOf(model) ?? event?.percent ?? 0;

    return Card(
      key: Key('model_card_${model.modelName}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.description,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (downloaded)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '已下载',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.goldDeep,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'ggml-${model.modelName}.bin · ${model.sizeHint}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            if (downloading) ...[
              LinearProgressIndicator(
                key: Key('model_progress_${model.modelName}'),
                value: pct / 100,
              ),
              const SizedBox(height: 8),
              Text('下载中 $pct%', style: Theme.of(context).textTheme.bodySmall),
            ] else
              Row(
                children: [
                  if (!downloaded)
                    PressableScale(
                      child: FilledButton.icon(
                        key: Key('btn_download_${model.modelName}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.gold,
                          foregroundColor: AppTheme.onGold,
                        ),
                        onPressed: onDownload,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('下载'),
                      ),
                    )
                  else ...[
                    const Spacer(),
                    TextButton.icon(
                      key: Key('btn_delete_${model.modelName}'),
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('删除'),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
