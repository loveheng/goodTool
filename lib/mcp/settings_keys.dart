library;

/// app_settings 内部键的**单一真相源**。
///
/// 此前键名字面量散落三处（装配件 `kAmapWebKey`、service `kQweatherKey`、
/// 总控 `_keyIdentityPrompt`）。用户设置页要**枚举并回显**这些键，键名一旦漂移
/// 就会出现「界面说已配置、实际未生效」或反之——故收口到本表，各处原常量改为
/// 引用本表（保留原名，不改调用面）。
///
/// 住**内核 mcp 层**：本表被 `repository`（读聚合）与 `service`（Actor 写）共同
/// 依赖，放内核可避免 repository↔service 的域级环。
class SettingsKeys {
  const SettingsKeys._();

  /// 高德 Web 服务 Key（`geo_*` 联网动作 + 静态图）。
  static const String amapWebKey = 'amap_web_key';

  /// 高德静态图数字签名密钥（可选，防 `INVALID_USER_SCODE`）。
  static const String amapSecret = 'amap_secret';

  /// 和风天气 API Key。
  static const String qweatherKey = 'qweather_key';

  /// 和风天气数据主机（免费版 `devapi` 与商业版 `api` 不同）。
  static const String qweatherHost = 'qweather_host';

  /// 用户身份画像（拼进 MCP 系统提示词）。
  static const String identityPrompt = 'identity_prompt';

  /// 用户预设城市（天气用；用户自设，Agent 无权写入）。
  static const String weatherLocation = 'weather_location';

  /// 日程敏感字段过滤开关（`'1'` 开 / `'0'` 关）。
  static const String privacyMaskPii = 'privacy_mask_pii';

  /// 模糊定位开关（`'1'` 开 / `'0'` 关）。
  static const String privacyBlurLocation = 'privacy_blur_location';

  /// 全部**用户可在设置页改写**的键。
  static const List<String> userWritable = <String>[
    amapWebKey,
    amapSecret,
    qweatherKey,
    qweatherHost,
    identityPrompt,
    weatherLocation,
    privacyMaskPii,
    privacyBlurLocation,
  ];

  /// 凭证类键（写入后只回显「已配置 + 掩码尾号」，禁回显明文）。
  static const List<String> credentialKeys = <String>[
    amapWebKey,
    amapSecret,
    qweatherKey,
  ];

  /// 脱敏开关类键（值域 `'1'` / `'0'`）。
  static const List<String> privacySwitchKeys = <String>[
    privacyMaskPii,
    privacyBlurLocation,
  ];

  /// 非凭证类**可明文回显**的键（如天气数据主机）。
  static const List<String> plainReadableKeys = <String>[
    qweatherHost,
    weatherLocation,
  ];
}
