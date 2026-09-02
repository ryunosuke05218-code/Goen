import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// GOENのブランドカラー。ロゴ（深紅の地にアイボリーの三つ輪、明朝体のワードマーク）から採取した色を
/// 基準にしている。アプリ全体のColorSchemeやコンポーネントテーマは全て[GoenColors]を起点に組み立てる。
class GoenColors {
  const GoenColors._();

  /// ロゴ背景の深紅（#BF211F〜#C2201E付近をサンプリングし中間値を採用）。
  static const primary = Color(0xFFC0211F);
  static const primaryDark = Color(0xFF8F1917);
  static const primaryLight = Color(0xFFDE5A50);

  /// ロゴの三つ輪・ワードマークのアイボリー。
  static const ivory = Color(0xFFF1E4D2);
  static const ivoryDeep = Color(0xFFE7D5B8);

  /// 和紙のような温かみのある生成り〜墨色のニュートラルレンジ。
  static const paper = Color(0xFFFBF6EF);
  static const paperDim = Color(0xFFF3E9DA);
  static const paperDeep = Color(0xFFECDFC8);
  static const ink = Color(0xFF2A1F1A);
  static const inkSoft = Color(0xFF5C4E43);
  static const outline = Color(0xFFD8C7AE);

  /// 金・朱を思わせるアクセント（サブスク訴求やバッジなど、控えめな特別感を出す箇所に使う）。
  static const gold = Color(0xFFA9752E);
  static const goldLight = Color(0xFFD8B778);

  /// 主色の赤と混同しないよう橙寄りに振ったエラーカラー。
  static const error = Color(0xFFA6420F);
  static const success = Color(0xFF2F6F4E);

  // ダークテーマ用
  static const darkBackground = Color(0xFF1C1512);
  static const darkSurface = Color(0xFF241B17);
  static const darkSurfaceHigh = Color(0xFF2E2320);
}

/// アプリ全体のThemeDataを組み立てる。
class GoenTheme {
  const GoenTheme._();

  static ThemeData light() => _build(_lightScheme, Brightness.light);

  static ThemeData dark() => _build(_darkScheme, Brightness.dark);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: GoenColors.primary,
    onPrimary: GoenColors.ivory,
    primaryContainer: GoenColors.ivory,
    onPrimaryContainer: GoenColors.primaryDark,
    secondary: GoenColors.gold,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFF3E4C6),
    onSecondaryContainer: Color(0xFF5C4112),
    tertiary: GoenColors.inkSoft,
    onTertiary: Colors.white,
    tertiaryContainer: GoenColors.paperDeep,
    onTertiaryContainer: GoenColors.ink,
    error: GoenColors.error,
    onError: Colors.white,
    errorContainer: Color(0xFFF6DDCB),
    onErrorContainer: Color(0xFF4A2007),
    surface: GoenColors.paper,
    onSurface: GoenColors.ink,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF8F1E6),
    surfaceContainer: GoenColors.paperDim,
    surfaceContainerHigh: Color(0xFFEFE2CB),
    surfaceContainerHighest: GoenColors.paperDeep,
    onSurfaceVariant: GoenColors.inkSoft,
    outline: GoenColors.outline,
    outlineVariant: Color(0xFFE9DCC5),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: GoenColors.ink,
    onInverseSurface: GoenColors.paper,
    inversePrimary: GoenColors.primaryLight,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFE2665E),
    onPrimary: Color(0xFF3C0A08),
    primaryContainer: GoenColors.primaryDark,
    onPrimaryContainer: GoenColors.ivory,
    secondary: GoenColors.goldLight,
    onSecondary: Color(0xFF3C2A05),
    secondaryContainer: Color(0xFF5C4112),
    onSecondaryContainer: Color(0xFFF3E4C6),
    tertiary: Color(0xFFCBB9A8),
    onTertiary: GoenColors.ink,
    tertiaryContainer: Color(0xFF473A31),
    onTertiaryContainer: GoenColors.paperDim,
    error: Color(0xFFE0895A),
    onError: Color(0xFF4A2007),
    errorContainer: Color(0xFF7A3410),
    onErrorContainer: Color(0xFFF6DDCB),
    surface: GoenColors.darkSurface,
    onSurface: GoenColors.paperDim,
    surfaceContainerLowest: Color(0xFF14100D),
    surfaceContainerLow: Color(0xFF1F1815),
    surfaceContainer: GoenColors.darkSurfaceHigh,
    surfaceContainerHigh: Color(0xFF382C27),
    surfaceContainerHighest: Color(0xFF433631),
    onSurfaceVariant: Color(0xFFD3C2B2),
    outline: Color(0xFF7A6A5C),
    outlineVariant: Color(0xFF4A3D35),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: GoenColors.paperDim,
    onInverseSurface: GoenColors.ink,
    inversePrimary: GoenColors.primary,
  );

  static TextTheme _textTheme(ColorScheme scheme) {
    final serif = GoogleFonts.notoSerifJpTextTheme();
    final sans = GoogleFonts.notoSansJpTextTheme();
    // 見出し・タイトルはロゴと調和する明朝体、本文・ラベルは可読性重視のゴシック体にする。
    // AppBarのタイトルはtitleLargeを参照するため、ここを明朝体にするだけで全画面のヘッダーへ
    // ブランドの雰囲気が自動的に波及する。
    return sans.copyWith(
      displayLarge: serif.displayLarge?.copyWith(letterSpacing: 1.2),
      displayMedium: serif.displayMedium?.copyWith(letterSpacing: 1.0),
      displaySmall: serif.displaySmall?.copyWith(letterSpacing: 0.8),
      headlineLarge: serif.headlineLarge?.copyWith(letterSpacing: 0.8),
      headlineMedium: serif.headlineMedium?.copyWith(letterSpacing: 0.6),
      headlineSmall: serif.headlineSmall?.copyWith(letterSpacing: 0.4),
      titleLarge: serif.titleLarge?.copyWith(letterSpacing: 0.4, fontWeight: FontWeight.w600),
      titleMedium: serif.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final textTheme = _textTheme(scheme);
    final isDark = brightness == Brightness.dark;
    final radius = BorderRadius.circular(14);
    final fieldRadius = BorderRadius.circular(12);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        scrolledUnderElevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onPrimary),
        iconTheme: IconThemeData(color: scheme.onPrimary),
        actionsIconTheme: IconThemeData(color: scheme.onPrimary),
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.light,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        elevation: 2,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant);
        }),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: scheme.outlineVariant)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        labelStyle: textTheme.labelLarge?.copyWith(color: scheme.onSurface),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: scheme.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: scheme.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: scheme.primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide(color: scheme.error, width: 2)),
        labelStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(color: scheme.primary),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.surfaceContainerHigh,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : Colors.transparent,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : scheme.outline,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
