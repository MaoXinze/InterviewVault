import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io' show Platform;

import 'package:just_audio/just_audio.dart';

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
import '../device_audio_service.dart';

/// 音频导入（W2-M2，PRD 2.3）：本机音频列表（MediaStore）点选 → 展示
/// 时长/大小/格式 → 确认后复制进库目录并落一条草稿面试记录。
/// 系统文件选择器保留为兜底入口。全程本地，不上传。
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  /// null = 加载中；denied = 权限被拒（引导态）
  DeviceAudioPermission? _permission;
  List<DeviceAudio>? _audios;
  String _query = '';
  ImportedAudioInfo? _info;
  bool _busy = false;

  /// 试听：同一时刻最多播放一个文件，点播放键切换
  AudioPlayer? _previewPlayer;
  StreamSubscription<dynamic>? _previewSub;
  String? _previewPath;

  @override
  void initState() {
    super.initState();
    _loadAudios();
  }

  Future<void> _loadAudios() async {
    setState(() => _permission = null);
    final service = ref.read(deviceAudioServiceProvider);
    final permission = await service.ensurePermission();
    List<DeviceAudio>? audios;
    if (permission == DeviceAudioPermission.granted) {
      audios = await service.listAudios();
    }
    if (!mounted) return;
    setState(() {
      _permission = permission;
      _audios = audios;
    });
  }

  @override
  void dispose() {
    _previewSub?.cancel();
    _previewPlayer?.dispose();
    super.dispose();
  }

  /// 试听开关：同一文件再点一次即停止；换文件则替换播放器
  Future<void> _togglePreview(DeviceAudio audio) async {
    if (_previewPath == audio.path) {
      await _stopPreview();
      if (mounted) setState(() {});
      return;
    }
    try {
      await _stopPreview();
      final player = AudioPlayer();
      _previewPlayer = player;
      _previewPath = audio.path;
      if (mounted) setState(() {});
      _previewSub = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          _stopPreview();
          setState(() {});
        }
      });
      await player.setFilePath(audio.path);
      unawaited(player.play());
    } on Exception {
      await _stopPreview();
      if (mounted) _showSnack('无法预览该音频（可能格式不支持）');
    }
  }

  Future<void> _stopPreview() async {
    _previewPath = null;
    _previewSub?.cancel();
    _previewSub = null;
    final player = _previewPlayer;
    _previewPlayer = null;
    try {
      await player?.stop();
      await player?.dispose();
    } on Exception {
      // 释放失败不阻塞导入流程
    }
  }

  /// 从本机列表点选 → 直接探测格式信息（无需经系统选择器）
  Future<void> _pickFromDevice(DeviceAudio audio) async {
    if (_busy) return;
    await _stopPreview();
    if (mounted) setState(() => _busy = true);
    try {
      final service = ref.read(audioImportServiceProvider);
      // 双分隔符兜底：Android 路径为 /，Windows 测试宿主为 \
      final fileName =
          audio.path.split('/').last.split(Platform.pathSeparator).last;
      final info = await service.inspect(
        PickedAudio(
          path: audio.path,
          fileName: fileName,
          sizeBytes: audio.sizeBytes,
        ),
      );
      if (!mounted) return;
      setState(() {
        _info = info;
        _busy = false;
      });
    } on Exception {
      if (mounted) {
        setState(() => _busy = false);
        _showSnack('读取文件失败，请重试');
      }
    }
  }

  /// 系统文件选择器兜底（SAF，覆盖媒体库之外的目录）
  Future<void> _pickViaSystem() async {
    if (_busy) return;
    await _stopPreview();
    if (mounted) setState(() => _busy = true);
    try {
      final service = ref.read(audioImportServiceProvider);
      final picked = await service.pick();
      if (picked == null) return;
      final info = await service.inspect(picked);
      if (!mounted) return;
      setState(() {
        _info = info;
        _busy = false;
      });
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
      body: info != null
          ? _ConfirmCard(
              info: info,
              busy: _busy,
              onConfirm: _confirmImport,
              onPickAgain: _pickViaSystem,
            )
          : _buildBrowser(context),
    );
  }

  Widget _buildBrowser(BuildContext context) {
    final permission = _permission;
    if (permission == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (permission == DeviceAudioPermission.denied) {
      return _PermissionGuide(onRequest: _loadAudios);
    }
    final audios = _audios ?? const <DeviceAudio>[];
    final filtered = _query.isEmpty
        ? audios
        : audios
            .where((a) => a.title.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('field_import_search'),
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索本机音频文件名',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('btn_import_pick'),
                onPressed: _busy ? null : _pickViaSystem,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('文件管理器'),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: audios.isEmpty
              ? _EmptyBrowser(onSystemPick: _pickViaSystem)
              : filtered.isEmpty
                  ? Center(
                      child: Text('没有匹配"$_query"的音频'),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final audio = filtered[index];
                        final subtitle = [
                          if (audio.album != null && audio.album!.isNotEmpty)
                            audio.album!,
                          if (audio.durationMs != null)
                            formatClock(
                              Duration(milliseconds: audio.durationMs!),
                            ),
                          formatFileSize(audio.sizeBytes),
                        ].join(' · ');
                        final previewing = _previewPath == audio.path;
                        return ListTile(
                          key: Key('device_audio_$index'),
                          leading: IconButton(
                            key: Key('btn_preview_$index'),
                            onPressed: () => _togglePreview(audio),
                            icon: Icon(
                              previewing
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_outline,
                              size: 30,
                              color: previewing
                                  ? AppTheme.gold
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            audio.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: previewing
                                ? Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: AppTheme.gold,
                                      fontWeight: FontWeight.w700,
                                    )
                                : null,
                          ),
                          subtitle: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _pickFromDevice(audio),
                        );
                      },
                    ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              '列表来自本机媒体库，仅用于选择导入，全程不上传',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

/// 媒体权限被拒：说明 + 去授权（重新触发系统弹窗）
class _PermissionGuide extends StatelessWidget {
  const _PermissionGuide({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_off_outlined,
              size: 52,
              color: AppTheme.gold,
            ),
            const SizedBox(height: 20),
            Text(
              '需要"音频媒体"权限',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '用于列出本机音频供你直接点选导入，'
              '免去在文件管理器里翻目录。列表只在 App 内使用，全程不上传。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('btn_import_permission'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: AppTheme.onGold,
              ),
              onPressed: onRequest,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('去授权'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本机没找到音频：空态引导（仍可走系统选择器）
class _EmptyBrowser extends StatelessWidget {
  const _EmptyBrowser({required this.onSystemPick});

  final VoidCallback onSystemPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CardIllustration.mic(size: 64, opacity: 0.8),
          const SizedBox(height: 16),
          Text(
            '本机没找到音频文件',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '新录的音频会在导入后出现在这里',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onSystemPick,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('从文件管理器选择'),
          ),
        ],
      ),
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
                    color: busy
                        ? colorScheme.surfaceContainerHighest
                        : AppTheme.gold,
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
