import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart' show RecordState;

import '../../../core/motion.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/motion.dart';
import '../../../data/database/app_database.dart';
import '../../../data/local/audio_files.dart';
import '../recorder_service.dart';

/// 录音页（W2-M1）：真实录音。
/// 待开始 → 录音中（波形 + 计时 + 暂停）→ 已暂停 → 停止落库跳转面试列表。
/// 录音/暂停态下返回需先选择：继续、停止并保存、丢弃。
class RecordingPage extends ConsumerStatefulWidget {
  const RecordingPage({super.key});

  @override
  ConsumerState<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends ConsumerState<RecordingPage> {
  RecorderService? _service;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    final service = ref.read(recorderServiceProvider);
    _service = service;
    // record 插件 start 后的原生线程失败经状态流异步透传，这里接住弹提示
    service.onPlatformError = _onPlatformError;
  }

  @override
  void dispose() {
    if (identical(_service?.onPlatformError, _onPlatformError)) {
      _service?.onPlatformError = null;
    }
    super.dispose();
  }

  void _onPlatformError(Object error) {
    if (!mounted) return;
    _showSnack('录音出现错误已中止，请重试');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(recorderServiceProvider);
    return PopScope(
      canPop: _leaving || service.isIdle,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmLeave(service);
      },
      child: Scaffold(
        key: const Key('page_record'),
        appBar: AppBar(title: const Text('新录音')),
        body: AnimatedBuilder(
          animation: service,
          builder: (context, _) {
            final colorScheme = Theme.of(context).colorScheme;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Waveform(service: service),
                  const SizedBox(height: 20),
                  Text(
                    _format(service.elapsed),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: service.isIdle
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                        ),
                  ),
                  const SizedBox(height: 36),
                  _Controls(
                    service: service,
                    onStop: () => _stopAndSave(context, ref, service),
                  ),
                  const SizedBox(height: 24),
                  _StateBadge(service: service),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmLeave(RecorderService service) async {
    final action = await showDialog<_LeaveAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('正在录音'),
        content: const Text('离开前要先处理这段录音吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _LeaveAction.stay),
            child: const Text('继续录音'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _LeaveAction.discard),
            child: const Text('丢弃录音'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, _LeaveAction.save),
            child: const Text('停止并保存'),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == _LeaveAction.stay) return;
    if (action == _LeaveAction.discard) {
      final result = await service.stop().catchError((Object _) {
        return null;
      });
      await deleteAudioFile(result?.filePath);
      if (!mounted) return;
      setState(() => _leaving = true);
      context.pop();
      return;
    }
    await _stopAndSave(context, ref, service);
  }

  Future<void> _stopAndSave(
    BuildContext context,
    WidgetRef ref,
    RecorderService service,
  ) async {
    RecordingResult? result;
    try {
      result = await service.stop();
    } on Exception {
      if (context.mounted) _showSnack('停止录音失败，请重试');
      return;
    }
    if (result == null) return;
    try {
      await ref.read(appDatabaseProvider).interviewsDao.insertOne(
            InterviewsCompanion.insert(
              id: 'iv-${DateTime.now().microsecondsSinceEpoch}',
              durationSeconds: Value(result.duration.inSeconds),
              audioFilePath: Value(result.filePath),
            ),
          );
    } on Exception {
      // 音频文件已在磁盘，DB 未落：提示后留在本页，可重试或稍后在列表重建
      if (context.mounted) _showSnack('保存失败，录音文件已保留，请重试');
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存到面试列表')));
    context.go('/interviews');
  }
}

enum _LeaveAction { stay, discard, save }

/// 时长格式：超 1 小时显示 h:mm:ss，否则 mm:ss。
String _format(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

class _Controls extends ConsumerStatefulWidget {
  const _Controls({required this.service, required this.onStop});

  final RecorderService service;
  final Future<void> Function() onStop;

  @override
  ConsumerState<_Controls> createState() => _ControlsState();
}

class _ControlsState extends ConsumerState<_Controls> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    if (service.isIdle) {
      return _RoundButton(
        key: const Key('btn_rec_start'),
        size: 96,
        background: Theme.of(context).colorScheme.surfaceContainerLow,
        borderColor: AppTheme.gold,
        glow: true,
        onTap: _saving ? null : () => _start(context, service),
        child: const Icon(Icons.mic_none, color: AppTheme.gold, size: 44),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 主控：录音中=暂停，已暂停=继续
        _RoundButton(
          key: service.isRecording
              ? const Key('btn_rec_pause')
              : const Key('btn_rec_resume'),
          size: 84,
          background: AppTheme.gold,
          onTap: _saving
              ? null
              : () => _togglePause(context, service),
          child: Icon(
            service.isRecording ? Icons.pause : Icons.play_arrow,
            color: AppTheme.onGold,
            size: 40,
          ),
        ),
        const SizedBox(width: 28),
        // 停止并落库
        _RoundButton(
          key: const Key('btn_rec_stop'),
          size: 64,
          background: Theme.of(context).colorScheme.onSurfaceVariant,
          onTap: _saving ? null : () => _runStop(),
          child: const Icon(Icons.stop, color: Colors.white, size: 32),
        ),
      ],
    );
  }

  Future<void> _start(BuildContext context, RecorderService service) async {
    try {
      await service.start();
    } on RecorderPermissionException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录音')),
        );
      }
    } on Exception {
      // 启动失败（编码器不支持等）：无提示会让按钮像"坏了"
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('录音启动失败，请重试')),
        );
      }
    }
  }

  Future<void> _togglePause(
    BuildContext context,
    RecorderService service,
  ) async {
    try {
      service.isRecording
          ? await service.pause()
          : await service.resume();
    } on Exception {
      // 状态机与真实录音器可能脱钩，交给用户重试而不是静默错位
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
        );
      }
    }
  }

  /// _stopAndSave 期间禁用全部按钮：防双击重复入库，也防落库中再次开始
  Future<void> _runStop() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onStop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.service});

  final RecorderService service;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, dotColor) = switch (service.state) {
      RecordState.record => ('录音中', AppTheme.gold),
      RecordState.pause => ('已暂停', colorScheme.onSurfaceVariant),
      _ => ('待开始 · 点击麦克风', colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// 电平波形：28 根，随 service.history 实时生长（鎏金）。
class _Waveform extends StatelessWidget {
  const _Waveform({required this.service});

  final RecorderService service;

  @override
  Widget build(BuildContext context) {
    final bars = service.history;
    return SizedBox(
      height: 56,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < 28; i++)
            AnimatedContainer(
              duration: Motion.fast,
              width: 4,
              height: 6 + (i < bars.length ? bars[i] : 0) * 44,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                color: i < bars.length && bars[i] > 0.02
                    ? AppTheme.gold.withValues(alpha: 0.3 + bars[i] * 0.5)
                    : Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.size,
    required this.background,
    required this.child,
    this.onTap,
    this.borderColor,
    this.glow = false,
  });

  final double size;
  final Color background;
  final Widget child;
  final VoidCallback? onTap;
  final Color? borderColor;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background,
          border: borderColor == null
              ? null
              : Border.all(color: borderColor!, width: 2),
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: AppTheme.gold.withValues(alpha: 0.25),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: child,
      ),
    );
  }
}
