library;

import 'package:flutter/material.dart';

import '../action/command_gateway.dart';
import '../action/settings_commands.dart';
import '../mcp/settings_keys.dart';
import '../service/mcp_controller.dart';
import '../ui_ports/settings_port.dart';
import '../ui_ports/status_port.dart';
import 'components/app_components.dart';

/// 设置页：MCP 服务控制 + 敏感设置自决。
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
  final _identity = TextEditingController();

  UserSettingsSnapshot? _snapshot;
  bool _loading = true;
  bool _saving = false;
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
    _identity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final snapshot = await widget.port.read();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _identity.text = snapshot.identityPrompt ?? '';
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
    setState(() => _saving = true);
    final result = await widget.port.setApiKey(provider: provider, key: value);
    if (!mounted) return;
    setState(() => _saving = false);
    _report(result);
  }

  Future<void> _toggleSwitch(String key, bool enabled) async {
    final result = await widget.port.setPrivacySwitch(key: key, enabled: enabled);
    _report(result);
  }

  Future<void> _saveIdentity() async {
    setState(() => _saving = true);
    final result = await widget.port.setIdentityProfile(_identity.text);
    if (!mounted) return;
    setState(() => _saving = false);
    _report(result);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final service = widget.controller;
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        if (_feedback != null) ...<Widget>[
          _FeedbackBanner(message: _feedback!, isError: _feedbackIsError),
          SizedBox(height: t.metrics.space16),
        ],
        SectionCard(
          title: 'MCP 服务',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: t.metrics.space8,
                runSpacing: t.metrics.space8,
                children: <Widget>[
                  TelemetryText(service.running ? '运行中' : '已停止',
                      color: service.running
                          ? t.palette.l1Ok
                          : t.palette.terminalMuted),
                  TelemetryText('端口 ${service.port}'),
                  TelemetryText(service.endpoint),
                ],
              ),
              SizedBox(height: t.metrics.space8),
              Wrap(
                spacing: t.metrics.space8,
                children: <Widget>[
                  FilledButton(
                    onPressed: () async {
                      await service.enable();
                      if (mounted) setState(() {});
                    },
                    child: const Text('启动'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      await service.disable();
                      if (mounted) setState(() {});
                    },
                    child: const Text('停止'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      await service.regenerateToken();
                      if (mounted) setState(() {});
                    },
                    child: const Text('重生成令牌'),
                  ),
                ],
              ),
              if (service.lastError != null) ...<Widget>[
                SizedBox(height: t.metrics.space8),
                Text(
                  '上次错误：${service.lastError}',
                  style: t.typeScale.compact.copyWith(color: t.palette.danger),
                ),
              ],
            ],
          ),
        ),
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
            saving: _saving,
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
            saving: _saving,
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
                onPressed: _saving ? null : _saveIdentity,
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
