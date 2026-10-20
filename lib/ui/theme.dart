import 'package:flutter/material.dart';

import 'tokens/app_theme_data.dart';
import 'tokens/app_tokens.dart';

/// 构建应用 [ThemeData]：Material 3，**暗色优先**（暗色为主口径，浅色为对照分支）。
///
/// 用法：宿主按系统设置择一——
/// `MaterialApp(darkTheme: buildAppTheme(brightness: Brightness.dark),
/// theme: buildAppTheme(brightness: Brightness.light), ...)`。
///
/// 纪律：
///   - 色彩 / 字号 / 几何 / 动效一律来自 token（`tokens/app_tokens.dart` 是唯一出处），
///     本文件只做「亮度 → token 组 → ThemeData」的转接，不引入任何数值；
///   - 字号由 `TextTheme` 提供，用户缩放走 M3 链路（`MediaQuery` 的 textScaler 施加），
///     主题层不覆写缩放参数（arch-guard R6）；
///   - 等宽遥测轨字号已落在 `TextTheme` 的小号槽位（bodySmall / labelSmall），
///     组件侧按语义取用，禁在组件内硬编码字号。
ThemeData buildAppTheme({required Brightness brightness}) {
  return buildThemeData(
    tokens: AppTokens.of(brightness),
    brightness: brightness,
  );
}
