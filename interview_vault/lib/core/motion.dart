import 'package:flutter/material.dart';

/// 全局动效 token（参考视频"Advanced Interaction Design"的铁律）：
/// 一次只动一层、单段 ≤400ms、全部经系统"减弱动态效果"门控。
abstract final class Motion {
  /// 微交互：按压下沉、图标弹性
  static const Duration fast = Duration(milliseconds: 150);

  /// 内容过渡：展开、浮现、错落间隔
  static const Duration medium = Duration(milliseconds: 250);

  /// 大面积变化：主题圆形扩散、卡片飞出
  static const Duration slow = Duration(milliseconds: 400);

  /// 主曲线：先快后缓
  static const Curve emphasized = Curves.easeOutCubic;

  /// 弹性曲线：选中舒张、图标弹跳（有限时长，pumpAndSettle 可收敛）
  static const Curve spring = Curves.easeOutBack;

  /// 列表错落间隔
  static const Duration stagger = Duration(milliseconds: 50);

  /// 第 index 项的错落延迟（封顶 8 档，长列表不无限等待）
  static Duration staggerDelay(int index) => stagger * (index > 7 ? 7 : index);
}

/// 系统"减弱动态效果"是否开启（Android 无障碍 / 演示模式）。
/// 开启时所有装饰性动画直接呈现终态，只保留必要的状态变化。
bool prefersReducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
