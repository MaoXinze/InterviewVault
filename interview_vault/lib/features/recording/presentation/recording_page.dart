import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 录音页：W2 实装真实录音（波形 / 暂停继续 / 锁屏后台）。
/// 当前为 dormant 录音机骨架——版式即未来形态，功能按 W2 路线激活。
class RecordingPage extends StatelessWidget {
  const RecordingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('page_record'),
      appBar: AppBar(title: const Text('新录音')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _WaveformPlaceholder(),
            const SizedBox(height: 20),
            // 计时器占位：等宽字距，未来实时走秒
            Text(
              '00:00',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                  ),
            ),
            const SizedBox(height: 36),
            // 麦克风：金环 + 辉光（点击给出阶段提示，W2 起真正录音）
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('录音整备中，W2 激活')),
              ),
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceContainerLow,
                  border: Border.all(color: AppTheme.gold, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.gold.withValues(alpha: 0.25),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic_none,
                  color: AppTheme.gold,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Text(
                '录音整备中 · W2 激活',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.gold,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '锁屏后台录音 · 暂停/继续 · 实时波形',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 静止波形占位：中段几根泛金，预示未来实时波形的形态。
class _WaveformPlaceholder extends StatelessWidget {
  const _WaveformPlaceholder();

  static const List<int> _heights = [
    10, 18, 26, 34, 22, 14, 8, 16, 28, 40, 30, 18, //
    10, 14, 24, 36, 28, 16, 10, 18, 30, 22, 12, 8,
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final entry in _heights.indexed)
          Container(
            width: 4,
            height: entry.$2.toDouble(),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            decoration: BoxDecoration(
              color: (entry.$1 >= 9 && entry.$1 <= 14
                      ? AppTheme.gold
                      : colorScheme.onSurfaceVariant)
                  .withValues(alpha: entry.$1 >= 9 && entry.$1 <= 14
                      ? 0.55
                      : 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
