library;

/// 就绪态元类型（**纯 Dart，无 Flutter**）：能力就绪的状态枚举与条目模型。
/// 双通道呈现语义（色相 + 文字/图标）见 ui-design §6；组件壳在
/// `lib/ui/components/readiness_components.dart`（随组件闭包同步模板）。
enum ReadinessState {
  /// 正常可用（L1）。
  ready,

  /// 未配置 / 未接入（灰阶）。
  missing,

  /// 被拒（玫瑰）——**禁与 missing 同灰阶混淆**。
  denied,
}

/// 某项能力的就绪条目。
class ReadinessItem {
  const ReadinessItem({
    required this.label,
    required this.state,
    this.detail,
  });

  /// 能力名（定位 / 日历 / 地图 Key / 天气 Key）。
  final String label;

  final ReadinessState state;

  /// 补充说明（人话中文；禁直出内部英文相位名）。
  final String? detail;
}
