import 'dart:async';

import '../../../core/platform/safe_url_launcher.dart';
import '../../../core/platform/sensitive_clipboard.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../domain/account_custom_field.dart';
import 'account_custom_fields_editor.dart';

class AccountCustomFieldsCard extends StatefulWidget {
  const AccountCustomFieldsCard({
    required this.fields,
    this.sensitiveClipboard = const PlatformSensitiveClipboard(),
    this.urlLauncher = const SafeUrlLauncher(),
    this.revealDuration = const Duration(seconds: 30),
    super.key,
  });
  final List<AccountCustomField> fields;
  final SensitiveClipboard sensitiveClipboard;
  final ExternalUrlLauncher urlLauncher;
  final Duration revealDuration;
  @override
  State<AccountCustomFieldsCard> createState() =>
      _AccountCustomFieldsCardState();
}

class _AccountCustomFieldsCardState extends State<AccountCustomFieldsCard>
    with WidgetsBindingObserver {
  final Set<String> _visible = {};
  final Map<String, Timer> _timers = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant AccountCustomFieldsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fields != widget.fields) _hideAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _hideAll();
  }

  void _hideAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (mounted) setState(_visible.clear);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _visible.clear();
    super.dispose();
  }

  void _toggle(String id) {
    _timers.remove(id)?.cancel();
    setState(() {
      if (!_visible.add(id)) _visible.remove(id);
    });
    if (_visible.contains(id)) {
      _timers[id] = Timer(widget.revealDuration, () {
        if (mounted) setState(() => _visible.remove(id));
      });
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _copy(AccountCustomField field) async {
    try {
      await widget.sensitiveClipboard.copySensitive(
        text: field.value,
        label: context.tr('自定义字段'),
      );
      _message('已安全复制，60 秒后自动清除。');
    } on Object {
      _message('复制失败，未写入剪贴板。');
    }
  }

  Future<void> _open(AccountCustomField field) async {
    try {
      if (!await widget.urlLauncher.open(field.value)) {
        _message('系统没有可打开该网址的应用。');
      }
    } on FormatException {
      _message('网址格式无效，仅支持安全的 http/https 地址。');
    } on Object {
      _message('打开网址失败。');
    }
  }

  @override
  Widget build(BuildContext context) => CardockSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('自定义字段', style: Theme.of(context).textTheme.titleMedium),
        for (final field in [
          ...widget.fields,
        ]..sort((a, b) => a.order.compareTo(b.order))) ...[
          const Divider(height: 24),
          Text(
            field.name,
            translate: false,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            customFieldTypeLabel(field.type),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          if (field.isSensitive && field.value.isNotEmpty)
            Semantics(
              label: context.tr(
                _visible.contains(field.id) ? '敏感值已临时显示' : '敏感值已隐藏',
              ),
              child: ExcludeSemantics(
                child: Text(
                  _visible.contains(field.id) ? field.value : '••••••••',
                  key: ValueKey('custom-field-detail-value-${field.id}'),
                  translate: false,
                ),
              ),
            )
          else
            Text(
              field.value.isEmpty ? context.tr('未填写') : field.value,
              key: ValueKey('custom-field-detail-value-${field.id}'),
              translate: false,
            ),
          if (field.value.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (field.isSensitive)
                  IconButton(
                    key: ValueKey('reveal-custom-field-detail-${field.id}'),
                    tooltip: context.tr(
                      _visible.contains(field.id) ? '隐藏敏感值' : '临时显示敏感值30秒',
                    ),
                    onPressed: () => _toggle(field.id),
                    icon: Icon(
                      _visible.contains(field.id)
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                if (field.type == AccountCustomFieldType.url)
                  IconButton(
                    key: ValueKey('open-custom-field-url-${field.id}'),
                    tooltip: context.tr('使用系统浏览器打开'),
                    onPressed: () => _open(field),
                    icon: const Icon(Icons.open_in_new),
                  ),
                IconButton(
                  key: ValueKey('copy-custom-field-${field.id}'),
                  tooltip: context.tr('安全复制字段值'),
                  onPressed: () => _copy(field),
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
        ],
      ],
    ),
  );
}
