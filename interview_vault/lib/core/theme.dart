import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Material 3 主题：产品人格 =「清晨 · 阳光清新」。
/// 性格来自配色与形状（生态绿 × 晨光琥珀 × 暖米纸），不来自堆元素。
abstract final class AppTheme {
  /// 主色：清晨自然绿（生态感，饱和度收敛不刺眼）
  static const Color seedColor = Color(0xFF2E9E6B);

  /// 点睛：晨光琥珀——只用于强调（hero 渐变、亮点标签），不做大面积
  static const Color sunshine = Color(0xFFF2A93B);

  /// 阳光 CTA：清晨柠檬绿，只给全局主行动按钮
  static const Color limeCta = Color(0xFFB9DF62);
  static const Color onLimeCta = Color(0xFF243312);

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ).copyWith(
      tertiary: sunshine,
      tertiaryContainer:
          isDark ? const Color(0xFF4D3D1A) : const Color(0xFFFFE9C4),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // 阳光人格的地基：浅色是暖米纸色，深色是带绿意的暖夜色
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF101613) : const Color(0xFFF7F4EA),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF1A211C) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1A211C) : Colors.white,
      ),
    );
  }
}

/// 暗色模式优先：默认 ThemeMode.dark，切换走圆形扩散（模式①）。
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void set(ThemeMode mode) => state = mode;

  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
