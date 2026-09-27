import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../audio_playback.dart';

/// 迷你播放条（PRD 2.5"标注跳转"的落点）：详情页头部卡下方，
/// 播放/暂停 + 进度 + 时间；未加载时进度条为不确定态。
/// 打开/播放失败的错误提示由调用方处理。
class MiniAudioPlayer extends ConsumerWidget {
  const MiniAudioPlayer({super.key, required this.audioPath});

  final String audioPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot =
        ref.watch(audioPlaybackStatesProvider).value ?? AudioPlaybackSnapshot.idle;
    final player = ref.read(audioPlaybackProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final duration = snapshot.duration;
    // duration 未知时显示 0 进度而非不确定态：不确定态是持续动画，
    // 会让 pumpAndSettle 永不收敛（测试挂起 + 无谓耗电）
    final progress = duration == null || duration == Duration.zero
        ? 0.0
        : (snapshot.position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0);

    return Card(
      key: const Key('mini_player'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              key: const Key('btn_play_pause'),
              icon: Icon(
                snapshot.playing ? Icons.pause_circle : Icons.play_circle,
                color: AppTheme.gold,
                size: 32,
              ),
              onPressed: () => _toggle(context, player),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    key: const Key('player_progress'),
                    value: progress,
                    minHeight: 4,
                    color: AppTheme.gold,
                    backgroundColor:
                        colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    duration == null
                        ? '点击播放录音'
                        : '${formatClock(snapshot.position)} / ${formatClock(duration)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, AudioPlayback player) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await player.open(audioPath);
      await player.toggle();
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(content: Text('音频无法播放：录音文件可能已被移动或删除')),
      );
    }
  }
}
