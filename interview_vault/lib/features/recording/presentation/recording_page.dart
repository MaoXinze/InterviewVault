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
import '../recorder_service.dart';

/// 录音页（W2-M1）：真实录音。
/// 待开始 → 录音中（波形 + 计时 + 暂停）→ 已暂停 → 停止落库跳转面试列表。
class RecordingPage extends ConsumerWidget {
  const RecordingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(recorderServiceProvider);
    return Scaffold(
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
                  RecordingPage._format(service.elapsed),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: service.isIdle
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 3,
                      ),
                ),
                const SizedBox(height: 36),
                _Controls(service: service),
                const SizedBox(height: 24),
                _StateBadge(service: service),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _format(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.service});

  final RecorderService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (service.isIdle) {
      return _RoundButton(
        key: const Key('btn_rec_start'),
        size: 96,
        background: Theme.of(context).colorScheme.surfaceContainerLow,
        borderColor: AppTheme.gold,
        glow: true,
        onTap: () => _start(context, service),
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
          onTap: () => service.isRecording
              ? unawaited(service.pause())
              : unawaited(service.resume()),
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
          onTap: () => _stopAndSave(context, ref, service),
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
    }
  }

  Future<void> _stopAndSave(
    BuildContext context,
    WidgetRef ref,
    RecorderService service,
  ) async {
    final result = await service.stop();
    if (result == null) return;
    await ref.read(appDatabaseProvider).interviewsDao.insertOne(
          InterviewsCompanion.insert(
            id: 'iv-${DateTime.now().microsecondsSinceEpoch}',
            durationSeconds: Value(result.duration.inSeconds),
            audioFilePath: Value(result.filePath),
          ),
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存到面试列表')));
    context.go('/interviews');
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
