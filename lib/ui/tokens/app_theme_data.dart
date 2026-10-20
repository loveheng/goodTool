import 'package:flutter/material.dart';

import 'app_tokens.dart';

// token→[ThemeData] 装配层：把 [AppTokens] 的色彩 / 字号 / 几何 / 动效注入 [ThemeData]。
//
// 分工：
//   - `app_tokens.dart` = token 唯一出处 + [AppTokens]（[ThemeExtension] 本体：copyWith / lerp）；
//   - 本文件 = **只做装配**（[buildThemeData] + [_colorScheme] + [_textTheme]）；
//   - `../theme.dart` = 对外入口 `buildAppTheme`（按亮度选板 + 调本文件装配）。
//
// 装配纪律：
//   - 组件内禁散落魔法值——颜色 / 字号 / 圆角 / 边框 / 时长一律回 [AppTokens] 取；
//   - 尺度走 M3 链路（`TextTheme` + `MediaQuery` 的 textScaler），主题层不覆写任何
//     缩放参数，禁使用已弃用的旧版 textScale 参数（arch-guard R6）。

/// 按 token 装配 [ThemeData]（Material 3）。
///
/// - 色彩：`ColorScheme` 的语义色全部由 token 构造（种子色只用于补齐未映射的容器色调），
///   容器色保持中性——状态由语义色 + 图标 / 文字双通道表达（§6 双通道状态）；
/// - 字号：把**等宽遥测轨**注入 `TextTheme` 的小号槽位（bodySmall / labelSmall），
///   阅读轨留在 bodyMedium 及以上槽位（§2「阅读内容禁用等宽」）；
/// - 几何：卡片 10dp 圆角 + 1dp hairline 描边、零投影（§4.3 / §5）；
/// - 动效：禁 Spring、禁大面积渐变发光——surfaceTint 置透明。
ThemeData buildThemeData({
  required AppTokens tokens,
  required Brightness brightness,
}) {
  final AppPalette p = tokens.palette;
  final AppMetrics m = tokens.metrics;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: _colorScheme(tokens, brightness),
    scaffoldBackgroundColor: p.surface,
    canvasColor: p.surface,
    cardColor: p.surfaceRaised,
    dividerColor: p.hairline,
    textTheme: _textTheme(tokens),
    primaryTextTheme: _textTheme(tokens, color: p.onStatus),
    iconTheme: IconThemeData(color: p.onSurfaceVariant),
    dividerTheme: DividerThemeData(
      color: p.hairline,
      thickness: m.borderWidth,
      space: m.space8,
    ),
    cardTheme: CardThemeData(
      color: p.surfaceRaised,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(m.radiusMd),
        side: BorderSide(color: p.hairline, width: m.borderWidth),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      foregroundColor: p.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: tokens.typeScale.titleMedium.copyWith(color: p.onSurface),
    ),
    // 保证触控热区 ≥ 48dp（§4.4 要求 ≥ 44×44dp）。
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: <ThemeExtension<dynamic>>[tokens],
  );
}

/// 构造 [ColorScheme]：语义色由 token 注入，容器色保持中性。
ColorScheme _colorScheme(AppTokens tokens, Brightness brightness) {
  final AppPalette p = tokens.palette;
  // 种子色只用于补齐 fromSeed 的容器色调；主语义色随即被 token 覆盖，
  // 因此「高对比色彩只用于系统状态」这条纪律不会被动态取色稀释。
  final ColorScheme seeded = ColorScheme.fromSeed(
    seedColor: p.l1Info,
    brightness: brightness,
  );
  return seeded.copyWith(
    primary: p.l1Info,
    onPrimary: p.onStatus,
    primaryContainer: p.surfaceRaised,
    onPrimaryContainer: p.onSurface,
    secondary: p.l2Accent,
    onSecondary: p.onStatus,
    secondaryContainer: p.surfaceRaised,
    onSecondaryContainer: p.onSurface,
    tertiary: p.dataRef,
    onTertiary: p.onStatus,
    tertiaryContainer: p.surfaceRaised,
    onTertiaryContainer: p.onSurface,
    error: p.danger,
    onError: p.onStatus,
    errorContainer: p.surfaceRaised,
    onErrorContainer: p.onSurface,
    surface: p.surface,
    onSurface: p.onSurface,
    surfaceDim: p.surfaceSunken,
    surfaceBright: p.surfaceRaised,
    surfaceContainerLowest: p.surfaceSunken,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceRaised,
    surfaceContainerHighest: p.surfaceRaised,
    onSurfaceVariant: p.onSurfaceVariant,
    outline: p.hairline,
    outlineVariant: p.hairline,
    inverseSurface: p.onSurface,
    onInverseSurface: p.surface,
    inversePrimary: p.l1Info,
    // 禁大面积渐变发光：去掉 M3 的 surface tint 叠加。
    surfaceTint: Colors.transparent,
  );
}

/// 构造 [TextTheme]：双轨落点——小号槽位归遥测轨（等宽），其余归阅读轨。
///
/// | 槽位 | token | 轨 |
/// |---|---|---|
/// | displayLarge / displayMedium | titleLarge | 阅读 |
/// | displaySmall / headlineMedium | titleMedium | 阅读 |
/// | headlineSmall / titleSmall | titleSmall | 阅读 |
/// | titleLarge | titleLarge | 阅读 |
/// | titleMedium | titleMedium | 阅读 |
/// | bodyLarge | body | 阅读 |
/// | bodyMedium | listItem | 阅读 |
/// | bodySmall | telemetry | 遥测（等宽） |
/// | labelLarge / labelMedium | compact | 阅读 |
/// | labelSmall | micro | 遥测（等宽微标注） |
///
/// 读法：**阅读轨文本一律取 bodyMedium 及以上槽位**；bodySmall / labelSmall 带等宽
/// 字体族，是遥测轨（时间戳 / 坐标 / 计数 / JSON 预览）的落点（§2）。
TextTheme _textTheme(AppTokens tokens, {Color? color}) {
  final AppTypeScale s = tokens.typeScale;
  final Color c = color ?? tokens.palette.onSurface;

  TextStyle paint(TextStyle style) => style.copyWith(color: c);

  return TextTheme(
    displayLarge: paint(s.titleLarge),
    displayMedium: paint(s.titleLarge),
    displaySmall: paint(s.titleMedium),
    headlineLarge: paint(s.titleLarge),
    headlineMedium: paint(s.titleMedium),
    headlineSmall: paint(s.titleSmall),
    titleLarge: paint(s.titleLarge),
    titleMedium: paint(s.titleMedium),
    titleSmall: paint(s.titleSmall),
    bodyLarge: paint(s.body),
    bodyMedium: paint(s.listItem),
    bodySmall: paint(s.telemetry),
    labelLarge: paint(s.compact),
    labelMedium: paint(s.compact),
    labelSmall: paint(s.micro),
  );
}
