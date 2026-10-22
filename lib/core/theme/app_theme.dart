import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';

enum AppTheme {
  ocean('🌊 海洋', FlexScheme.blue),
  forest('🌲 森林', FlexScheme.green),
  sunset('🌅 日落', FlexScheme.amber),
  night('🌙 暗夜', FlexScheme.indigo),
  minimal('🏔️ 极简', FlexScheme.material);

  final String label;
  final FlexScheme scheme;
  const AppTheme(this.label, this.scheme);
}

/// 统一的柔和阴影，供卡片等组件复用（轻微浮起）。
List<BoxShadow> softShadow(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return [
    BoxShadow(
      color: Colors.black.withAlpha(dark ? 60 : 18),
      blurRadius: 18,
      offset: const Offset(0, 6),
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Colors.black.withAlpha(dark ? 40 : 10),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];
}

const double _radius = 18.0;

ThemeData buildLightTheme(AppTheme theme) {
  final base = FlexThemeData.light(
    scheme: theme.scheme,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 15,
    appBarStyle: FlexAppBarStyle.background,
    appBarOpacity: 0.92,
    bottomAppBarElevation: 0,
    subThemesData: const FlexSubThemesData(
      inputDecoratorRadius: 14.0,
      chipRadius: 20.0,
      popupMenuRadius: 14.0,
      alignedDropdown: true,
      fabRadius: 18.0,
      navigationBarSelectedLabelSize: 12.0,
      navigationBarUnselectedLabelSize: 12.0,
      bottomSheetRadius: 24.0,
      defaultRadius: 18.0,
    ),
    visualDensity: FlexColorScheme.comfortablePlatformDensity,
    useMaterial3: true,
    swapLegacyOnMaterial3: true,
  );
  return _refine(base, Brightness.light);
}

ThemeData buildDarkTheme(AppTheme theme) {
  final base = FlexThemeData.dark(
    scheme: theme.scheme,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 15,
    appBarStyle: FlexAppBarStyle.background,
    appBarOpacity: 0.92,
    bottomAppBarElevation: 0,
    subThemesData: const FlexSubThemesData(
      inputDecoratorRadius: 14.0,
      chipRadius: 20.0,
      popupMenuRadius: 14.0,
      alignedDropdown: true,
      fabRadius: 18.0,
      navigationBarSelectedLabelSize: 12.0,
      navigationBarUnselectedLabelSize: 12.0,
      bottomSheetRadius: 24.0,
      defaultRadius: 18.0,
    ),
    visualDensity: FlexColorScheme.comfortablePlatformDensity,
    useMaterial3: true,
    swapLegacyOnMaterial3: true,
  );
  return _refine(base, Brightness.dark);
}

/// 在 flex 基础上叠加更精致的卡片/按钮/AppBar 细节。
ThemeData _refine(ThemeData base, Brightness brightness) {
  return base.copyWith(
    // 透明：实际底色由 AppBackground 的氛围渐变层提供
    // （见 core/theme/app_background.dart）。关掉氛围背景时 AppBackground 会退回纯色。
    scaffoldBackgroundColor: Colors.transparent,
    cardTheme: CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      color: base.colorScheme.surface,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      centerTitle: false,
      scrolledUnderElevation: 0.5,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: base.colorScheme.outlineVariant.withAlpha(120)),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      height: 66,
      elevation: 0,
      backgroundColor: base.colorScheme.surface,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
