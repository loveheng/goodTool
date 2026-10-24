library;

import 'package:flutter/material.dart';

import '../action/command_gateway.dart';
import '../action/settings_commands.dart';
import '../mcp/settings_keys.dart';
import '../service/mcp_controller.dart';
import '../ui_ports/settings_port.dart';
import '../ui_ports/status_port.dart';
import 'components/app_components.dart';
import 'mcp_service_page.dart';

/// 设置页：敏感设置自决 + 「关于」长按隐藏入口（MCP 调试服务控制）。
///
/// **写路径纪律**：所有设置写经 `SettingsPort` → `CommandGateway` 的**用户侧注册表**
/// （`user_*` 命令）——与 MCP 写档同一唯一写入口，但 AI 不可触达（R1 + 信任模型）。
/// 本页**不直连** KV / store（R5），**不** `jsonDecode`（R2）。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.port,
    required this.controller,
  });

  final SettingsPort port;
  final McpController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _amapKey = TextEditingController();
  final _qweatherKey = TextEditingController();
  final _qweatherHost = TextEditingController();
  final _identity = TextEditingController();

  UserSettingsSnapshot? _snapshot;
  bool _loading = true;

  /// 正在保存的键（provider/setting key/identity）——按项隔离，保存一项
  /// 只禁用该项按钮，其余配置不陪跑禁用（否则像「卡住了」）。
  String? _savingKey;
  String? _feedback;
  bool _feedbackIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amapKey.dispose();
    _qweatherKey.dispose();
    _qweatherHost.dispose();
    _identity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final snapshot = await widget.port.read();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _identity.text = snapshot.identityPrompt ?? '';
      // 非凭证明文键：可直接回显当前值（不掩码）。
      _qweatherHost.text = snapshot.plainValues[SettingsKeys.qweatherHost] ?? '';
      _loading = false;
    });
  }

  void _report(UserCommandResult result) {
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _snapshot = result.data as UserSettingsSnapshot?;
        _feedback = '已保存';
        _feedbackIsError = false;
        // 凭证写后不回显明文——清空输入框，避免明文留在界面与输入法历史。
        _amapKey.clear();
        _qweatherKey.clear();
        // 非凭证明文键：回显最新值（写后可能已清空）。
        _qweatherHost.text =
            _snapshot?.plainValues[SettingsKeys.qweatherHost] ?? '';
      } else {
        _feedback = '${result.errorCode}：${result.message ?? ''}';
        _feedbackIsError = true;
        if (result.suggestion != null) {
          _feedback = '${_feedback!}\n${result.suggestion}';
        }
      }
    });
  }

  Future<void> _saveApiKey(String provider, String value) async {
    setState(() => _savingKey = provider);
    final result = await widget.port.setApiKey(provider: provider, key: value);
    if (!mounted) return;
    setState(() => _savingKey = null);
    _report(result);
  }

  Future<void> _savePlainSetting(String key, String value) async {
    setState(() => _savingKey = key);
    final result = await widget.port.setSetting(key: key, value: value);
    if (!mounted) return;
    setState(() => _savingKey = null);
    _report(result);
  }

  Future<void> _toggleSwitch(String key, bool enabled) async {
    final result = await widget.port.setPrivacySwitch(key: key, enabled: enabled);
    _report(result);
  }

  Future<void> _saveIdentity() async {
    setState(() => _savingKey = 'identity');
    final result = await widget.port.setIdentityProfile(_identity.text);
    if (!mounted) return;
    setState(() => _savingKey = null);
    _report(result);
  }

  /// 隐藏入口：长按「关于」进 MCP 调试服务控制页。
  void _openServicePage() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => McpServicePage(controller: widget.controller),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        if (_feedback != null) ...<Widget>[
          _FeedbackBanner(message: _feedback!, isError: _feedbackIsError),
          SizedBox(height: t.metrics.space16),
        ],
        // MCP HTTP 调试服务控制收进隐藏页（2026-10-20 产品决策：不随启动自启，
        // 仅 adb 直连）——设置页只留「关于」长按入口，控制面不暴露在日常视线里。
        _AboutCard(onOpenService: _openServicePage),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '地图厂商 API Key',
          child: _ApiKeySection(
            controller: _amapKey,
            hint: '高德 Web 服务 Key（amap_web_key）',
            configured: _snapshot?.isConfigured(SettingsKeys.amapWebKey) ??
                false,
            masked: _snapshot?.credentialMasked[SettingsKeys.amapWebKey] ?? '',
            onSave: (value) => _saveApiKey('amap', value),
            onClear: () => _saveApiKey('amap', ''),
            saving: _savingKey == 'amap',
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '天气 API Key',
          child: _ApiKeySection(
            controller: _qweatherKey,
            hint: '和风天气 API Key（qweather_key）',
            configured:
                _snapshot?.isConfigured(SettingsKeys.qweatherKey) ?? false,
            masked: _snapshot?.credentialMasked[SettingsKeys.qweatherKey] ?? '',
            onSave: (value) => _saveApiKey('qweather', value),
            onClear: () => _saveApiKey('qweather', ''),
            saving: _savingKey == 'qweather',
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '天气数据主机（2024 起必填）',
          child: _PlainKeySection(
            controller: _qweatherHost,
            hint: '账号专属 Host，如 xxxx.re.qweatherapi.com',
            configured: _snapshot?.plainValues
                    .containsKey(SettingsKeys.qweatherHost) ??
                false,
            current: _snapshot?.plainValues[SettingsKeys.qweatherHost] ?? '',
            onSave: (value) => _savePlainSetting(
              SettingsKeys.qweatherHost,
              value,
            ),
            onClear: () => _savePlainSetting(SettingsKeys.qweatherHost, ''),
            saving: _savingKey == SettingsKeys.qweatherHost,
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '隐私与脱敏',
          child: Column(
            children: <Widget>[
              _SwitchRow(
                label: '日程敏感字段过滤',
                detail: '对日程地点与描述中的电话、邮箱做掩码（默认开；标题不脱敏）',
                value: _snapshot?.isSwitchOn(SettingsKeys.privacyMaskPii) ??
                    false,
                onChanged: (v) => _toggleSwitch(SettingsKeys.privacyMaskPii, v),
              ),
              SizedBox(height: t.metrics.space8),
              _SwitchRow(
                label: '模糊定位',
                detail: '对外暴露的位置降精度（防止精确轨迹泄露）',
                value: _snapshot?.isSwitchOn(SettingsKeys.privacyBlurLocation) ??
                    false,
                onChanged: (v) =>
                    _toggleSwitch(SettingsKeys.privacyBlurLocation, v),
              ),
            ],
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '身份画像',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '供外部 Agent 在排程 / 建议时参考你的处境；仅你本人可写，Agent 无权写入。',
                style: t.typeScale.compact,
              ),
              SizedBox(height: t.metrics.space8),
              TextField(
                controller: _identity,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '身份画像（可留空）',
                ),
              ),
              SizedBox(height: t.metrics.space8),
              FilledButton(
                onPressed: _savingKey == 'identity' ? null : _saveIdentity,
                child: const Text('保存'),
              ),
            ],
          ),
        ),
        if (_loading) ...<Widget>[
          SizedBox(height: t.metrics.space16),
          Text('读取设置中…', style: t.typeScale.body),
        ],
      ],
    );
  }
}

/// 「关于」卡：版本信息 + **长按**进 MCP 调试服务控制页（隐藏入口，普通点按无反应）。
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.onOpenService});

  final VoidCallback onOpenService;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return SectionCard(
      title: '关于',
      child: GestureDetector(
        onLongPress: onOpenService,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('goodTools', style: t.typeScale.listItem),
            SizedBox(height: t.metrics.space4),
            Text(
              '长按本卡片进入 MCP 调试服务控制（仅调试用，adb 直连）',
              style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// 反馈条：成功 / 失败可读提示（不崩溃、不吞错）。
class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.metrics.space12),
      decoration: BoxDecoration(
        color: isError
            ? t.palette.danger.withValues(alpha: 0.12)
            : t.palette.l1Ok.withValues(alpha: 0.12),
        border: Border.all(
          color: isError ? t.palette.danger : t.palette.l1Ok,
          width: t.metrics.borderWidth,
        ),
        borderRadius: BorderRadius.circular(t.metrics.radiusMd),
      ),
      child: Text(
        message,
        style: t.typeScale.compact.copyWith(
          color: isError ? t.palette.danger : t.palette.l1Ok,
        ),
      ),
    );
  }
}

/// API Key 输入段：**凭证不回显明文**（standards §6.1）——只显示「已配置 + 掩码尾号」。
class _ApiKeySection extends StatelessWidget {
  const _ApiKeySection({
    required this.controller,
    required this.hint,
    required this.configured,
    required this.masked,
    required this.onSave,
    required this.onClear,
    required this.saving,
  });

  final TextEditingController controller;
  final String hint;
  final bool configured;
  final String masked;
  final ValueChanged<String> onSave;
  final VoidCallback onClear;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            StatusDot(
              state: configured
                  ? ReadinessState.ready
                  : ReadinessState.missing,
            ),
            SizedBox(width: t.metrics.space4),
            Text(
              configured ? '已配置 $masked' : '未配置',
              style: t.typeScale.compact.copyWith(
                color: configured ? t.palette.l1Ok : t.palette.terminalMuted,
              ),
            ),
          ],
        ),
        SizedBox(height: t.metrics.space8),
        TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(labelText: hint),
        ),
        SizedBox(height: t.metrics.space8),
        Wrap(
          spacing: t.metrics.space8,
          children: <Widget>[
            FilledButton(
              onPressed: saving ? null : () => onSave(controller.text),
              child: const Text('保存'),
            ),
            if (configured)
              OutlinedButton(
                onPressed: saving ? null : onClear,
                child: const Text('清除'),
              ),
          ],
        ),
      ],
    );
  }
}

/// 非凭证明文键输入段（如天气数据主机）：可回显当前值，不掩码、不明文隐藏。
class _PlainKeySection extends StatelessWidget {
  const _PlainKeySection({
    required this.controller,
    required this.hint,
    required this.configured,
    required this.current,
    required this.onSave,
    required this.onClear,
    required this.saving,
  });

  final TextEditingController controller;
  final String hint;
  final bool configured;
  final String current;
  final ValueChanged<String> onSave;
  final VoidCallback onClear;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            StatusDot(
              state: configured
                  ? ReadinessState.ready
                  : ReadinessState.missing,
            ),
            SizedBox(width: t.metrics.space4),
            Expanded(
              child: Text(
                configured ? '已配置：$current' : '未配置',
                style: t.typeScale.compact.copyWith(
                  color: configured ? t.palette.l1Ok : t.palette.terminalMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: t.metrics.space4),
        Text(
          '和风公共域名（devapi / api / geoapi）自 2024 年起已全线停用'
          '（403 Invalid Host / 404 空体），须填账号专属 Host（控制台「项目管理」'
          '复制，形如 xxxx.re.qweatherapi.com），它同时服务天气与 GeoAPI 城市解析。'
          '粘贴带 https:// 或尾部斜杠会被自动归一为纯主机名。',
          style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
        ),
        SizedBox(height: t.metrics.space8),
        TextField(
          controller: controller,
          decoration: InputDecoration(labelText: hint),
        ),
        SizedBox(height: t.metrics.space8),
        Wrap(
          spacing: t.metrics.space8,
          children: <Widget>[
            FilledButton(
              onPressed: saving ? null : () => onSave(controller.text),
              child: const Text('保存'),
            ),
            if (configured)
              OutlinedButton(
                onPressed: saving ? null : onClear,
                child: const Text('清除'),
              ),
          ],
        ),
      ],
    );
  }
}

/// 脱敏开关行（状态 + 说明 + 开关）。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: t.typeScale.listItem),
              SizedBox(height: t.metrics.space4),
              Text(
                detail,
                style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
