import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Material 3 主题：产品人格 =「墨绿 × 鎏金 · 知识金库」。
/// InterviewVault 的"金库"隐喻：深墨绿是库，鎏金是把面试炼成的资产。
/// 分工铁律：金 = 价值与行动（CTA/hero 数字/⏺/选中态），绿 = 功能（链接/图标）。
abstract final class AppTheme {
  /// 功能绿：链接、图标、常规强调（静谧墨绿系）
  static const Color seedColor = Color(0xFF2F7D5F);

  /// 品牌金：签名色，克制使用才值钱
  static const Color gold = Color(0xFFE3B341);

  /// 亮色模式下的金（白底上保证对比度）
  static const Color goldDeep = Color(0xFF9C711E);

  /// 金底上的墨字
  static const Color onGold = Color(0xFF241B05);

  /// 硬边按钮的"厚度"（Duolingo 式压边）
  static const Color goldEdge = Color(0xFFB98A20);

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // 墨绿暖夜 × 纸白：对比度优先，拒绝发灰发虚
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0E1411) : const Color(0xFFFAFAF6),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF161D18) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF121814) : Colors.white,
      ),
    );
  }
}

/// 默认亮色（2026-10 用户决策）；暗色仍是设计原点，金/绿的分工不变。
/// 切换走圆形扩散（模式①）。
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  void set(ThemeMode mode) => state = mode;

  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
