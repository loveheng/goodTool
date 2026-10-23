/// 设计 token 唯一出处（SSOT 落点）—— goodTools UI 视觉语言的数值化定义。
///
/// 规范正文：`docs/project/ui-design.md`
///   §1 色彩 token（功能状态驱动）· §2 排印 token（阅读轨 / 遥测轨双轨分立）
///   §4 交互质感（禁 Spring、150~200ms、Decelerate / Ease-Out）· §5 布局标尺
///   §6 无障碍红线（正文 ≥ 4.5:1、微字 ≥ 3:1、双通道状态）
///
/// 落地纪律：`.agents/skills/goodTools-ui/SKILL.md`（零魔法值 / token 唯一出处）
///
/// 三条组内铁律：
///   1. **零魔法值**：组件内禁散落裸色值 / 裸间距 / 裸时长 / 裸字号，一律回本文件取；
///   2. **深浅共用一套语义名**：深浅只差数值不差名，组件侧无需按亮度分支选色；
///   3. **阶梯封闭**：新增字号 / 尺寸 / 时长档位先扩本文件（必要时先扩 ui-design.md
///      对应节），禁组件内私自取值。
///
/// 本文件 = token 唯一出处（纯数值）+ [AppTokens]（[ThemeExtension] 本体）。
/// 装配在 `app_theme_data.dart`，对外入口在 `../theme.dart`。
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 色彩 token 组：深 / 浅两套值，**语义名完全一致**。
///
/// 深浅只差数值不差名：组件侧一律按语义名取色（如 `tokens.palette.l1Ok`），
/// 不允许在组件里判 `Brightness` 再选色。
///
/// 对比度自证（WCAG 2.x 相对亮度比；底色分别为页底 surface 与卡片底 surfaceRaised）：
///
/// | 角色 | 暗色值 | 暗/页底 | 暗/卡片 | 浅色值 | 浅/页底 | 浅/卡片 |
/// |---|---|---|---|---|---|---|
/// | onSurface | E4E4E7 | 13.96 | 11.74 | 18181B | 16.93 | 17.72 |
/// | onSurfaceVariant | A1A1AA | 6.91 | 5.81 | 52525B | 7.39 | 7.73 |
/// | textMuted | 71717A | 3.67 | 3.08 | 71717A | 4.62 | 4.83 |
/// | terminalMuted | 6B7280 | 3.66 | 3.08 | 64748B | 4.55 | 4.76 |
/// | l1Ok | 34D399 | 9.22 | 7.75 | 047857 | 5.24 | 5.48 |
/// | l1Info | 06B6D4 | 7.30 | 6.13 | 0E7490 | 5.12 | 5.36 |
/// | l2Warn | F59E0B | 8.25 | 6.94 | B45309 | 4.80 | 5.02 |
/// | l2Accent | FB923C | 7.83 | 6.58 | C2410C | 4.95 | 5.18 |
/// | danger | FB7185 | 6.58 | 5.53 | BE123C | 6.01 | 6.29 |
/// | dataRef | 818CF8 | 5.94 | 4.99 | 4F46E5 | 6.01 | 6.29 |
/// | dangerDeep | BE123C | 2.82 | 2.37 | 9F1239 | 7.66 | 8.02 |
///
/// 达标口径（对应 §6 无障碍红线）：
///   - 正文 / 次级 / 状态色（dangerDeep 除外）在页底与卡片底上均 ≥ 4.5:1，满足正文红线；
///   - textMuted / terminalMuted 只承载 10.5~11sp 微标注与状态点，≥ 3:1，满足微字线；
///   - **12sp 遥测轨（telemetry）与 10.5sp 微标注（micro）的保证**：这两档在 TextTheme
///     里默认取 onSurface（暗 13.96:1 / 浅 16.93:1），远超 3:1 底线；页面把微字降级到
///     textMuted（暗 3.67:1 / 浅 4.62:1）时仍 ≥ 3:1——两套配色都满足 §6 微字红线；
///   - dangerDeep 是**实底填充**角色（熔断条 / 中止键底），配 onDangerDeep 白字前景
///     （暗 6.29:1 / 浅 8.02:1），不作底色上的文字色，故不套正文红线；
///   - 实底状态块前景 onStatus：暗色板取近黑（对各浅色状态底 6.59~10.22:1），
///     浅色板取纯白（对各深色状态底 5.02~6.29:1），均 ≥ 4.5:1。
///
/// 与规范参考值的**有意偏差**（已按 §6 红线校准，必要时先扩 ui-design.md §1）：
///   - 暗色 danger 取 Rose 400（FB7185）而非参考的 Rose 500（F43F5E）：后者在卡片底上
///     仅 4.06:1，跌破 4.5:1 正文红线；
///   - 浅色 danger / dangerDeep 各下移一档（Rose 700 / Crimson 800），保证浅底上仍 ≥ 4.5:1。
@immutable
class AppPalette {
  const AppPalette({
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.textMuted,
    required this.onStatus,
    required this.onDangerDeep,
    required this.l1Ok,
    required this.l1Info,
    required this.l2Warn,
    required this.l2Accent,
    required this.danger,
    required this.dangerDeep,
    required this.dataRef,
    required this.terminalMuted,
    required this.hairline,
    required this.codeBg,
  });

  /// 暗色板（主口径）：Zinc 900 页底 / Zinc 800 卡片底 / Zinc 950 下沉底。
  ///
  /// hairline = 白基 12%、codeBg = 白基 8%（已按页底合成为实色，避免叠底漂移）。
  static const AppPalette dark = AppPalette(
    surface: Color(0xFF18181B),
    surfaceRaised: Color(0xFF27272A),
    surfaceSunken: Color(0xFF09090B),
    onSurface: Color(0xFFE4E4E7),
    onSurfaceVariant: Color(0xFFA1A1AA),
    textMuted: Color(0xFF71717A),
    onStatus: Color(0xFF0B0B0F),
    onDangerDeep: Color(0xFFFFFFFF),
    l1Ok: Color(0xFF34D399),
    l1Info: Color(0xFF06B6D4),
    l2Warn: Color(0xFFF59E0B),
    l2Accent: Color(0xFFFB923C),
    danger: Color(0xFFFB7185),
    dangerDeep: Color(0xFFBE123C),
    dataRef: Color(0xFF818CF8),
    terminalMuted: Color(0xFF6B7280),
    hairline: Color(0xFF343436),
    codeBg: Color(0xFF2A2A2D),
  );

  /// 浅色板：Slate 50 页底 / 白卡片底 / Slate 100 下沉底。
  ///
  /// hairline = 黑基 12%、codeBg = 黑基 8%（同样按页底合成为实色）。
  static const AppPalette light = AppPalette(
    surface: Color(0xFFF8FAFC),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF1F5F9),
    onSurface: Color(0xFF18181B),
    onSurfaceVariant: Color(0xFF52525B),
    textMuted: Color(0xFF71717A),
    onStatus: Color(0xFFFFFFFF),
    onDangerDeep: Color(0xFFFFFFFF),
    l1Ok: Color(0xFF047857),
    l1Info: Color(0xFF0E7490),
    l2Warn: Color(0xFFB45309),
    l2Accent: Color(0xFFC2410C),
    danger: Color(0xFFBE123C),
    dangerDeep: Color(0xFF9F1239),
    dataRef: Color(0xFF4F46E5),
    terminalMuted: Color(0xFF64748B),
    hairline: Color(0xFFDADCDE),
    codeBg: Color(0xFFE4E6E8),
  );

  /// 页底（页面与阅读轨底色）——§1「底色基底」。
  final Color surface;

  /// 卡片 / 容器底色（raised），用于与 [surface] 拉开层次。
  final Color surfaceRaised;

  /// 下沉底色（终端区 / 深色代码面板底）。
  final Color surfaceSunken;

  /// 正文字色（§6 要求对底色 ≥ 4.5:1）。
  final Color onSurface;

  /// 次级文字色（说明、标签）。
  final Color onSurfaceVariant;

  /// 弱化文字色（10.5~11sp 微标注 / 辅助说明；§6 要求 ≥ 3:1）。
  final Color textMuted;

  /// 实底状态块上的前景色（状态药丸 / 实底按钮上的文字与图标）。
  final Color onStatus;

  /// 深危险实底（熔断条 / 中止键）上的前景色。
  final Color onDangerDeep;

  /// L1 就绪 / 成功（服务运行、探活正常、调用成功、轻提示）。
  final Color l1Ok;

  /// L1 信息（就绪提示、信息级强调）。
  final Color l1Info;

  /// L2 写操作警示（配置变更确认、脱敏开关、模糊定位授权卡）。
  final Color l2Warn;

  /// L2 强调（次级写操作强调色）。
  final Color l2Accent;

  /// 危险 / 失败 / 准入被拒（权限缺失、调用失败）。
  final Color danger;

  /// 危险加深（熔断 / 中止实底）；只作填充底，不作底色上的文字色。
  final Color dangerDeep;

  /// 数据指针（经纬度、坐标句柄、缓存键、链接）。
  final Color dataRef;

  /// 终态 / 空闲灰（终态锁定、空闲、服务未起）。
  final Color terminalMuted;

  /// 1dp 细边框（全部分隔线）。
  final Color hairline;

  /// 代码底（行内与块级代码底：JSON 预览 / 参数）。
  final Color codeBg;
}

/// 排印 token 组：阅读轨 + 遥测轨**双轨分立**（§2）。
///
/// 字号阶梯（封闭；新增档位先扩本组再使用）：
///
/// | 档位 | sp | 行高 | 字重 | 轨 | 用途 |
/// |---|---|---|---|---|---|
/// | titleLarge | 20 | 1.30 | w600 | 阅读 | 页面 / 区块主标题 |
/// | titleMedium | 17 | 1.35 | w600 | 阅读 | 次级标题 |
/// | titleSmall | 15 | 1.40 | w500 | 阅读 | 卡片标题 |
/// | body | 15 | 1.50 | w400 | 阅读 | 正文（§2 的 14~15sp 上沿） |
/// | listItem | 14 | 1.50 | w400 | 阅读 | 列表行 / 设置项标签 |
/// | compact | 14 | 1.25 | w500 | 阅读 | 紧凑控件文字（同字号更紧行高，不越 14~15sp 区间） |
/// | telemetry | 12 | 1.35 | w400 | 遥测 | 时间戳 / 坐标 / 结果（§2 的 11~12sp 上沿） |
/// | telemetryDense | 11 | 1.30 | w400 | 遥测 | 遥测密排（§2 的 11~12sp 下沿） |
/// | telemetryDisplay | 28 | 1.25 | w500 | 遥测 | 遥测主显示（计算器结果大号等宽区） |
/// | micro | 10.5 | 1.25 | w500 | 遥测 | 微标注（§2 的 10.5sp） |
/// | dayNumber | 22 | 1.25 | w600 | 阅读 | 日历日号（挂历式大日号；仅日历月格使用，不进通用排版） |
///
/// 字族：
///   - 阅读轨 Inter，缺省回落 Roboto（Android 系统字体，保证无字体资产时的可读性）；
///   - 遥测轨 JetBrains Mono，缺省回落 Roboto Mono / monospace（强制等宽）。
///
/// 本仓未打包字体资产，字族名只声明"意图"，实际落到系统字体；后续随包分发
/// Inter / JetBrains Mono 时只改本组即可，组件零改动。
@immutable
class AppTypeScale {
  const AppTypeScale({
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.body,
    required this.listItem,
    required this.compact,
    required this.telemetry,
    required this.telemetryDense,
    required this.telemetryDisplay,
    required this.micro,
    required this.dayNumber,
  });

  /// 标准档位（全仓唯一一套）。
  static const AppTypeScale standard = AppTypeScale(
    titleLarge: TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: <String>['Roboto'],
      fontSize: 20,
      height: 1.3,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: <String>['Roboto'],
      fontSize: 17,
      height: 1.35,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: <String>['Roboto'],
      fontSize: 15,
      height: 1.4,
      fontWeight: FontWeight.w500,
    ),
    body: TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: <String>['Roboto'],
      fontSize: 15,
      height: 1.5,
      fontWeight: FontWeight.w400,
    ),
    listItem: TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: <String>['Roboto'],
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w400,
    ),
    compact: TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: <String>['Roboto'],
      fontSize: 14,
      height: 1.25,
      fontWeight: FontWeight.w500,
    ),
    telemetry: TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: <String>['Roboto Mono', 'monospace'],
      fontSize: 12,
      height: 1.35,
      fontWeight: FontWeight.w400,
    ),
    telemetryDense: TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: <String>['Roboto Mono', 'monospace'],
      fontSize: 11,
      height: 1.3,
      fontWeight: FontWeight.w400,
    ),
    telemetryDisplay: TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: <String>['Roboto Mono', 'monospace'],
      fontSize: 28,
      height: 1.25,
      fontWeight: FontWeight.w500,
    ),
    micro: TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: <String>['Roboto Mono', 'monospace'],
      fontSize: 10.5,
      height: 1.25,
      fontWeight: FontWeight.w500,
    ),
    dayNumber: TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: <String>['Roboto'],
      fontSize: 22,
      height: 1.25,
      fontWeight: FontWeight.w600,
    ),
  );

  /// 标题一级（阅读轨）。
  final TextStyle titleLarge;

  /// 标题二级（阅读轨）。
  final TextStyle titleMedium;

  /// 标题三级（阅读轨）。
  final TextStyle titleSmall;

  /// 正文（阅读轨）。
  final TextStyle body;

  /// 列表行（阅读轨）。
  final TextStyle listItem;

  /// 紧凑控件文字（阅读轨）。
  final TextStyle compact;

  /// 遥测正文（遥测轨，等宽）。
  final TextStyle telemetry;

  /// 遥测密排（遥测轨，等宽）。
  final TextStyle telemetryDense;

  /// 遥测主显示（遥测轨，等宽大号——计算器结果区）。
  final TextStyle telemetryDisplay;

  /// 微标注（遥测轨，等宽）。
  final TextStyle micro;

  /// 日历日号（阅读轨，挂历式大日号；仅日历月格使用）。
  final TextStyle dayNumber;
}

/// 布局标尺 token 组（§5）：基线网格、间距阶梯、圆角分级、边框、限宽、触控热区。
///
/// - 基线网格 4dp；间距阶梯封闭为 4 / 6 / 8 / 10 / 12 / 14 / 16（dp），按值直名。
///   其中 6 / 10 / 14 属"落在网格系内的紧凑微调"，16 为阶梯上限；更大留白靠多级
///   嵌套留白组合达成，禁私自新增间距档位。
/// - 圆角分级：4（Badge / 标签）· 8（小容器）· 10（卡片 cardRadius）· 12（按钮）
///   · 24（底部输入条胶囊，**全局唯一 > 16dp 例外**；本次未实现输入条故暂不启用）。
///   其余全局禁 > 16dp；圆形控件走 CircleBorder，不需要圆角档位。
/// - 边框 1dp hairline（另备 0.5dp 次级细线）；限宽：主内容 720dp、空态 560dp。
/// - 触控热区 ≥ 44×44dp（视觉元素可小：状态点 7dp、微标注 11sp）。
@immutable
class AppMetrics {
  const AppMetrics({
    required this.grid,
    required this.space4,
    required this.space6,
    required this.space8,
    required this.space10,
    required this.space12,
    required this.space14,
    required this.space16,
    required this.radiusBadge,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusPill,
    required this.borderWidth,
    required this.borderWidthThin,
    required this.contentMaxWidth,
    required this.emptyStateMaxWidth,
    required this.minTouchTarget,
    required this.statusDotSize,
    required this.inkPadHeight,
    required this.inkStrokeWidth,
  });

  /// 标准标尺。
  static const AppMetrics standard = AppMetrics(
    grid: 4,
    space4: 4,
    space6: 6,
    space8: 8,
    space10: 10,
    space12: 12,
    space14: 14,
    space16: 16,
    radiusBadge: 4,
    radiusSm: 8,
    radiusMd: 10,
    radiusLg: 12,
    radiusPill: 24,
    borderWidth: 1,
    borderWidthThin: 0.5,
    contentMaxWidth: 720,
    emptyStateMaxWidth: 560,
    minTouchTarget: 44,
    statusDotSize: 7,
    inkPadHeight: 120,
    inkStrokeWidth: 2.5,
  );

  /// 基线网格（4dp）。
  final double grid;

  /// 间距 4dp。
  final double space4;

  /// 间距 6dp（网格系内紧凑微调）。
  final double space6;

  /// 间距 8dp。
  final double space8;

  /// 间距 10dp（网格系内紧凑微调）。
  final double space10;

  /// 间距 12dp。
  final double space12;

  /// 间距 14dp（网格系内紧凑微调）。
  final double space14;

  /// 间距 16dp（阶梯上限）。
  final double space16;

  /// 圆角 4dp（Badge / 标签）。
  final double radiusBadge;

  /// 圆角 8dp（小容器）。
  final double radiusSm;

  /// 圆角 10dp（卡片 cardRadius）。
  final double radiusMd;

  /// 圆角 12dp（按钮）。
  final double radiusLg;

  /// 圆角 24dp（底部输入条胶囊；全局唯一 > 16dp 例外）。
  final double radiusPill;

  /// 边框 1dp（hairline）。
  final double borderWidth;

  /// 边框 0.5dp（次级细线）。
  final double borderWidthThin;

  /// 宽屏主内容限宽 720dp。
  final double contentMaxWidth;

  /// 空态提示限宽 560dp。
  final double emptyStateMaxWidth;

  /// 最小触控热区 44×44dp。
  final double minTouchTarget;

  /// 状态点视觉直径 7dp（热区靠透明 padding 补足）。
  final double statusDotSize;

  /// 手写书写带高度（dp）。
  final double inkPadHeight;

  /// 手写墨迹笔画宽度（dp）。
  final double inkStrokeWidth;
}

/// 动效 token 组（§4.2）：禁 Spring；只用 Decelerate / Ease-Out 紧凑减速曲线；
/// 转场时长封闭在 150~200ms。
///
/// | 档位 | 时长 | 用途 |
/// |---|---|---|
/// | durationFast | 150ms | 状态点相位过渡 / 微反馈（禁缩放与弹跳） |
/// | durationStandard | 180ms | 常规转场（卡片展开、页内切换） |
/// | durationSlow | 200ms | 页面级转场 |
@immutable
class AppMotion {
  const AppMotion({
    required this.durationFast,
    required this.durationStandard,
    required this.durationSlow,
    required this.curveDecelerate,
    required this.curveEaseOut,
    required this.curveStandard,
  });

  /// 标准动效档位。
  static const AppMotion standard = AppMotion(
    durationFast: Duration(milliseconds: 150),
    durationStandard: Duration(milliseconds: 180),
    durationSlow: Duration(milliseconds: 200),
    curveDecelerate: Curves.decelerate,
    curveEaseOut: Curves.easeOut,
    curveStandard: Curves.easeOut,
  );

  /// 快速档 150ms（状态点相位过渡 / 微反馈）。
  final Duration durationFast;

  /// 常规档 180ms。
  final Duration durationStandard;

  /// 慢速档 200ms（页面级转场）。
  final Duration durationSlow;

  /// 减速曲线（入场 / 状态收敛）。
  final Curve curveDecelerate;

  /// 缓出曲线（退场 / 位移收敛）。
  final Curve curveEaseOut;

  /// 默认转场曲线（= Ease-Out）。
  final Curve curveStandard;
}

/// UI 层 design token 的运行时装载体：[ThemeExtension] 本体。
///
/// 组件侧经 `Theme.of(context).extension<AppTokens>()!` 取用；四个对外出口：
///   - [AppTokens.dark]（静态 const 值）、[AppTokens.light]（静态 const 值）；
///   - [AppTokens.of]（按亮度取板的方法，主题入口唯一用）；
///   - 装配函数 `buildThemeData`（在 `app_theme_data.dart`），对外入口
///     `buildAppTheme`（在 `../theme.dart`）。
///
/// 注意：[AppTokens.dark] / [AppTokens.light] 是**静态 const 字段**（值语义，直接取用），
/// 不是工厂方法——按 `AppTokens.of(brightness)` 取板即可覆盖全部场景。
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.palette,
    required this.typeScale,
    required this.metrics,
    required this.motion,
  });

  /// 暗色 token 组（主口径：暗色优先）。
  static const AppTokens dark = AppTokens(
    palette: AppPalette.dark,
    typeScale: AppTypeScale.standard,
    metrics: AppMetrics.standard,
    motion: AppMotion.standard,
  );

  /// 浅色 token 组。
  static const AppTokens light = AppTokens(
    palette: AppPalette.light,
    typeScale: AppTypeScale.standard,
    metrics: AppMetrics.standard,
    motion: AppMotion.standard,
  );

  /// 按亮度取 token 组（唯一允许的亮度分支点：主题入口，不进组件）。
  static AppTokens of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 色彩 token（深浅共用一套语义名）。
  final AppPalette palette;

  /// 排印 token（阅读轨 / 遥测轨双轨）。
  final AppTypeScale typeScale;

  /// 布局标尺 token（间距 / 圆角 / 边框 / 限宽 / 触控热区）。
  final AppMetrics metrics;

  /// 动效 token（时长 / 缓动曲线）。
  final AppMotion motion;

  @override
  AppTokens copyWith({
    AppPalette? palette,
    AppTypeScale? typeScale,
    AppMetrics? metrics,
    AppMotion? motion,
  }) {
    return AppTokens(
      palette: palette ?? this.palette,
      typeScale: typeScale ?? this.typeScale,
      metrics: metrics ?? this.metrics,
      motion: motion ?? this.motion,
    );
  }

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) {
      return this;
    }
    return AppTokens(
      palette: _lerpPalette(palette, other.palette, t),
      typeScale: _lerpTypeScale(typeScale, other.typeScale, t),
      metrics: _lerpMetrics(metrics, other.metrics, t),
      // 缓动曲线是离散枚举，不做数值插值：过半即切到目标曲线。
      motion: t < 0.5 ? motion : other.motion,
    );
  }
}

AppPalette _lerpPalette(AppPalette a, AppPalette b, double t) {
  Color c(Color x, Color y) => Color.lerp(x, y, t)!;
  return AppPalette(
    surface: c(a.surface, b.surface),
    surfaceRaised: c(a.surfaceRaised, b.surfaceRaised),
    surfaceSunken: c(a.surfaceSunken, b.surfaceSunken),
    onSurface: c(a.onSurface, b.onSurface),
    onSurfaceVariant: c(a.onSurfaceVariant, b.onSurfaceVariant),
    textMuted: c(a.textMuted, b.textMuted),
    onStatus: c(a.onStatus, b.onStatus),
    onDangerDeep: c(a.onDangerDeep, b.onDangerDeep),
    l1Ok: c(a.l1Ok, b.l1Ok),
    l1Info: c(a.l1Info, b.l1Info),
    l2Warn: c(a.l2Warn, b.l2Warn),
    l2Accent: c(a.l2Accent, b.l2Accent),
    danger: c(a.danger, b.danger),
    dangerDeep: c(a.dangerDeep, b.dangerDeep),
    dataRef: c(a.dataRef, b.dataRef),
    terminalMuted: c(a.terminalMuted, b.terminalMuted),
    hairline: c(a.hairline, b.hairline),
    codeBg: c(a.codeBg, b.codeBg),
  );
}

AppTypeScale _lerpTypeScale(AppTypeScale a, AppTypeScale b, double t) {
  TextStyle s(TextStyle x, TextStyle y) => TextStyle.lerp(x, y, t)!;
  return AppTypeScale(
    titleLarge: s(a.titleLarge, b.titleLarge),
    titleMedium: s(a.titleMedium, b.titleMedium),
    titleSmall: s(a.titleSmall, b.titleSmall),
    body: s(a.body, b.body),
    listItem: s(a.listItem, b.listItem),
    compact: s(a.compact, b.compact),
    telemetry: s(a.telemetry, b.telemetry),
    telemetryDense: s(a.telemetryDense, b.telemetryDense),
    telemetryDisplay: s(a.telemetryDisplay, b.telemetryDisplay),
    micro: s(a.micro, b.micro),
    dayNumber: s(a.dayNumber, b.dayNumber),
  );
}

AppMetrics _lerpMetrics(AppMetrics a, AppMetrics b, double t) {
  double m(double x, double y) => lerpDouble(x, y, t)!;
  return AppMetrics(
    grid: m(a.grid, b.grid),
    space4: m(a.space4, b.space4),
    space6: m(a.space6, b.space6),
    space8: m(a.space8, b.space8),
    space10: m(a.space10, b.space10),
    space12: m(a.space12, b.space12),
    space14: m(a.space14, b.space14),
    space16: m(a.space16, b.space16),
    radiusBadge: m(a.radiusBadge, b.radiusBadge),
    radiusSm: m(a.radiusSm, b.radiusSm),
    radiusMd: m(a.radiusMd, b.radiusMd),
    radiusLg: m(a.radiusLg, b.radiusLg),
    radiusPill: m(a.radiusPill, b.radiusPill),
    borderWidth: m(a.borderWidth, b.borderWidth),
    borderWidthThin: m(a.borderWidthThin, b.borderWidthThin),
    contentMaxWidth: m(a.contentMaxWidth, b.contentMaxWidth),
    emptyStateMaxWidth: m(a.emptyStateMaxWidth, b.emptyStateMaxWidth),
    minTouchTarget: m(a.minTouchTarget, b.minTouchTarget),
    statusDotSize: m(a.statusDotSize, b.statusDotSize),
    inkPadHeight: m(a.inkPadHeight, b.inkPadHeight),
    inkStrokeWidth: m(a.inkStrokeWidth, b.inkStrokeWidth),
  );
}
