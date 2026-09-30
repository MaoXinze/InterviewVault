import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/illustration.dart';
import '../../../core/widgets/motion.dart';
import '../../../data/database/app_database.dart';
import '../audio_import_service.dart';

/// 音频导入（W2-M2，PRD 2.3）：选文件 → 展示时长/大小/格式 → 确认后
/// 复制进库目录并落一条草稿面试记录。全程本地，不上传。
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  ImportedAudioInfo? _info;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 进入即唤起系统选择器；取消则留在选择态，可再次手动选择
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(audioImportServiceProvider);
      final picked = await service.pick();
      if (picked == null) return;
      final info = await service.inspect(picked);
      if (!mounted) return;
      setState(() => _info = info);
    } on Exception {
      if (mounted) _showSnack('读取文件失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmImport() async {
    final info = _info;
    if (info == null || _busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(audioImportServiceProvider);
      final storedPath = await service.importFile(info.source);
      await ref.read(appDatabaseProvider).interviewsDao.insertOne(
            InterviewsCompanion.insert(
              id: 'iv-${DateTime.now().microsecondsSinceEpoch}',
              durationSeconds: Value(info.duration?.inSeconds),
              audioFilePath: Value(storedPath),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已导入到面试列表')));
      context.go('/interviews');
    } on Exception {
      if (mounted) _showSnack('导入失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      key: const Key('page_import'),
      appBar: AppBar(title: const Text('导入音频')),
      body: Center(
        child: _busy && info == null
            ? const CircularProgressIndicator()
            : info == null
                ? _EmptyPick(onPick: _pick)
                : _ConfirmCard(
                    info: info,
                    busy: _busy,
                    onConfirm: _confirmImport,
                    onPickAgain: _pick,
                  ),
      ),
    );
  }
}

/// 尚未选择文件：入口引导
class _EmptyPick extends StatelessWidget {
  const _EmptyPick({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.surfaceContainerLow,
            border: Border.all(color: AppTheme.gold, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.gold.withValues(alpha: 0.18),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const CardIllustration.mic(size: 52),
        ),
        const SizedBox(height: 24),
        Text(
          '选择一段面试录音',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '支持 mp3 / wav / m4a / aac / ogg',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 28),
        PressableScale(
          onTap: onPick,
          child: Container(
            key: const Key('btn_import_pick'),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.gold,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '选择文件',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppTheme.onGold,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 格式确认卡（PRD 2.3：时长、大小、格式，用户确认后入库）
class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({
    required this.info,
    required this.busy,
    required this.onConfirm,
    required this.onPickAgain,
  });

  final ImportedAudioInfo info;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onPickAgain;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.audiotrack, color: AppTheme.gold, size: 48),
          const SizedBox(height: 16),
          Text(
            info.source.fileName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _metaChip(context, '格式', info.format.toUpperCase()),
              const SizedBox(width: 10),
              _metaChip(
                context,
                '大小',
                formatFileSize(info.source.sizeBytes),
              ),
              const SizedBox(width: 10),
              _metaChip(
                context,
                '时长',
                info.duration == null ? '待转写确认' : formatClock(info.duration!),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '确认后将复制到本地库，全程不上传任何服务器',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const Key('btn_import_repick'),
                onPressed: busy ? null : onPickAgain,
                child: const Text('重新选择'),
              ),
              const SizedBox(width: 12),
              PressableScale(
                onTap: busy ? null : onConfirm,
                child: Container(
                  key: const Key('btn_import_confirm'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  decoration: BoxDecoration(
                    color: busy ? colorScheme.surfaceContainerHighest : AppTheme.gold,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    busy ? '导入中…' : '确认导入',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: busy
                              ? colorScheme.onSurfaceVariant
                              : AppTheme.onGold,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaChip(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
