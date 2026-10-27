import 'package:flutter/material.dart';

/// 全局配色与排版常量。
/// 所有色值严格取自 SPEC 第 5 节，禁止在页面里硬编码颜色。
class AppColors {
  AppColors._();

  // ---------- 浅色模式 ----------
  /// 主墨色：标题、主按钮
  static const Color ink = Color(0xFF1B2A41);
  /// 金棕色：强调、进度环
  static const Color gold = Color(0xFFA67C3D);
  /// 金棕色（文字级）：仅用于小号正文/按钮文字，对 #FFFFFF 与 #F7F5F0 均 >=4.5:1（WCAG AA）
  static const Color goldText = Color(0xFF8F6329);
  /// 纸色：页面背景
  static const Color paper = Color(0xFFF7F5F0);
  /// 卡片白
  static const Color card = Color(0xFFFFFFFF);
  /// 正文
  static const Color text = Color(0xFF2E3440);
  /// 次要文字
  static const Color textMinor = Color(0xFF5B6472);
  /// 分隔线
  static const Color divider = Color(0xFFE3DED4);
  /// 成功
  static const Color success = Color(0xFF3E6B57);
  /// 警示
  static const Color warning = Color(0xFFB03A2E);

  // ---------- 深色模式 ----------
  static const Color darkBg = Color(0xFF12161C);
  static const Color darkCard = Color(0xFF1A2028);
  static const Color darkText = Color(0xFFE6E3DC);
  static const Color darkPrimary = Color(0xFFD9C7A7);
}

/// 字号与间距常量。
class AppSizes {
  AppSizes._();

  static const double h1 = 28.0;
  static const double h2 = 20.0;
  static const double h3 = 16.0;
  static const double body = 14.0;
  static const double caption = 12.0;
  /// 数字展示专用大字号（Inter）
  static const double numberLarge = 48.0;
  static const double numberMid = 32.0;

  /// 间距一律 8 的倍数
  static const double gap = 8.0;
  static const double gap2 = 16.0;
  static const double gap3 = 24.0;

  /// 卡片圆角 20，按钮圆角 14
  static const double cardRadius = 20.0;
  static const double buttonRadius = 14.0;
}

/// 唯一允许使用的阴影。
const List<BoxShadow> kCardShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x0F1B2A41), // rgba(27,42,65,0.06)
    offset: Offset(0, 2),
    blurRadius: 8,
  ),
];

/// 动效时长 200~280ms，统一走这个常量。
const Duration kAnimFast = Duration(milliseconds: 200);
const Duration kAnimNormal = Duration(milliseconds: 280);

/// 构建浅色主题。
ThemeData buildLightTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.ink,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.ink,
    secondary: AppColors.gold,
    surface: AppColors.card,
    error: AppColors.warning,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    dividerColor: AppColors.divider,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paper,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: AppSizes.h2,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: AppSizes.h1, fontWeight: FontWeight.w600, color: AppColors.ink),
      titleLarge: TextStyle(fontSize: AppSizes.h2, fontWeight: FontWeight.w600, color: AppColors.ink),
      titleMedium: TextStyle(fontSize: AppSizes.h3, fontWeight: FontWeight.w600, color: AppColors.text),
      bodyMedium: TextStyle(fontSize: AppSizes.body, color: AppColors.text, height: 1.6),
      bodySmall: TextStyle(fontSize: AppSizes.caption, color: AppColors.textMinor),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        ),
        textStyle: const TextStyle(fontSize: AppSizes.body, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.gold.withValues(alpha: 0.16),
      height: 68,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: AppSizes.caption, fontWeight: FontWeight.w500),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.gold,
      linearTrackColor: AppColors.divider,
    ),
  );
}

/// 构建深色主题。
ThemeData buildDarkTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.darkPrimary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.darkPrimary,
    secondary: AppColors.gold,
    surface: AppColors.darkCard,
    error: AppColors.warning,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.darkBg,
    dividerColor: const Color(0xFF2A313B),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBg,
      foregroundColor: AppColors.darkText,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: AppSizes.h2,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: AppSizes.h1, fontWeight: FontWeight.w600, color: AppColors.darkText),
      titleLarge: TextStyle(fontSize: AppSizes.h2, fontWeight: FontWeight.w600, color: AppColors.darkText),
      titleMedium: TextStyle(fontSize: AppSizes.h3, fontWeight: FontWeight.w600, color: AppColors.darkText),
      bodyMedium: TextStyle(fontSize: AppSizes.body, color: AppColors.darkText, height: 1.6),
      bodySmall: TextStyle(fontSize: AppSizes.caption, color: Color(0xFF9AA3B0)),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkCard,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.darkPrimary,
        foregroundColor: AppColors.darkBg,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        ),
        textStyle: const TextStyle(fontSize: AppSizes.body, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.darkCard,
      indicatorColor: AppColors.darkPrimary.withValues(alpha: 0.18),
      height: 68,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: AppSizes.caption, fontWeight: FontWeight.w500),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.darkPrimary,
      linearTrackColor: Color(0xFF2A313B),
    ),
  );
}
