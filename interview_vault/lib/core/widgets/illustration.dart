import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// 鎏金单色线稿插画（assets/illustrations/，本地资产离线可用）。
///
/// 全部线稿单色绘制，经 [BlendMode.srcIn] 整体着色：
/// 暗色用品牌金、亮色用 goldDeep（白底对比），与「墨绿 × 鎏金」人格一致。
class CardIllustration extends StatelessWidget {
  const CardIllustration.question({super.key, this.size = 88, this.opacity})
      : _asset = 'assets/illustrations/flip_question.svg';

  const CardIllustration.answer({super.key, this.size = 88, this.opacity})
      : _asset = 'assets/illustrations/flip_answer.svg';

  const CardIllustration.done({super.key, this.size = 88, this.opacity})
      : _asset = 'assets/illustrations/review_done.svg';

  final String _asset;

  /// 边长（正方形 viewBox 120）
  final double size;

  /// 不透明度（水印用法给 0.1-0.2；1 = 实色）
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppTheme.gold : AppTheme.goldDeep;
    final color = base.withValues(alpha: opacity ?? 1.0);
    return SvgPicture.asset(
      _asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
