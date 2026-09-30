import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 品牌线稿图标（assets/icons/，单色绘制，随主题着色）。
///
/// 与 Material 图标相比线条更圆润统一，是底栏与首页快捷入口的签名视觉。
/// 资产以 #000 描边绘制，经 [BlendMode.srcIn] 整体着色为传入色。
class BrandIcon extends StatelessWidget {
  const BrandIcon(this.name, {super.key, this.size = 24, this.color});

  /// 资产名（不含 assets/icons/ 前缀与 .svg 后缀），如 'nav_home'
  final String name;

  final double size;

  /// 着色；null 时按资产原色渲染
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final filter = color == null
        ? null
        : ColorFilter.mode(color!, BlendMode.srcIn);
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: filter,
    );
  }
}
