import 'dart:async';

import '../../../core/platform/sensitive_clipboard.dart';
import '../../../core/security/account_password_generator.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

const generatedPasswordBackupNotice =
    '生成的密码较复杂，建议保存账号后，前往“设置 → 数据安全与备份 → 立即自动备份”进行备份，并将加密备份文件另存一份到电脑或其他存储介质，避免手机损坏或遗失导致账号密码丢失。';

const accountGeneratorNotice = 'Cardock 只能生成并记录密码，不会替你修改外部平台密码。';
const generatedPasswordSaveNotice =
    '只有你已经在对应平台完成改密，才应把此密码保存为当前密码。Cardock 不会修改平台密码。';

class PasswordGeneratorSheet extends StatefulWidget {
  const PasswordGeneratorSheet({
    this.sensitiveClipboard = const PlatformSensitiveClipboard(),
    this.revealDuration = const Duration(seconds: 30),
    super.key,
  });
  final SensitiveClipboard sensitiveClipboard;
  final Duration revealDuration;

  @override
  State<PasswordGeneratorSheet> createState() => _PasswordGeneratorSheetState();
}

class _PasswordGeneratorSheetState extends State<PasswordGeneratorSheet>
    with WidgetsBindingObserver {
  final _generator = AccountPasswordGenerator();
  AccountPasswordOptions _options = const AccountPasswordOptions();
  String _value = '';
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _value = _generator.generate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _timer?.cancel();
      setState(() {
        _visible = false;
        _value = '';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _value = '';
    super.dispose();
  }

  void _generate() {
    _timer?.cancel();
    setState(() {
      _value = _generator.generate(options: _options);
      _visible = false;
    });
  }

  void _change(AccountPasswordOptions options) {
    if (options.categoryCount == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少保留一种字符类别')));
      return;
    }
    setState(() => _options = options);
    _generate();
  }

  void _toggle() {
    _timer?.cancel();
    setState(() => _visible = !_visible);
    if (_visible) {
      _timer = Timer(widget.revealDuration, () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  Future<void> _copy() async {
    try {
      await widget.sensitiveClipboard.copySensitive(
        text: _value,
        label: context.tr('生成的密码'),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已安全复制，60 秒后自动清除。')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('复制失败，未写入剪贴板。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      key: const ValueKey('password-generator-sheet'),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('离线密码生成器', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text(generatedPasswordBackupNotice),
          const SizedBox(height: 12),
          const Text(accountGeneratorNotice),
          const SizedBox(height: 12),
          Semantics(
            label: context.tr(_visible ? '生成的密码已临时显示' : '生成的密码已隐藏'),
            child: ExcludeSemantics(
              child: Text(
                _value.isEmpty
                    ? context.tr('请重新生成密码')
                    : (_visible ? _value : '••••••••'),
                key: const ValueKey('generated-password-value'),
                translate: false,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              IconButton(
                key: const ValueKey('reveal-generated-password'),
                tooltip: context.tr(_visible ? '隐藏密码' : '显示密码30秒'),
                onPressed: _value.isEmpty ? null : _toggle,
                icon: Icon(
                  _visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              IconButton(
                key: const ValueKey('copy-generated-password'),
                tooltip: context.tr('安全复制登录密码'),
                onPressed: _value.isEmpty ? null : _copy,
                icon: const Icon(Icons.copy_outlined),
              ),
              TextButton.icon(
                key: const ValueKey('regenerate-password'),
                onPressed: _generate,
                icon: const Icon(Icons.refresh),
                label: const Text('重新生成'),
              ),
            ],
          ),
          Text(
            context.tr('长度：{count} 位', {'count': _options.length}),
            translate: false,
          ),
          Slider(
            key: const ValueKey('generated-password-length'),
            min: 8,
            max: 64,
            divisions: 56,
            value: _options.length.toDouble(),
            label: '${_options.length}',
            semanticFormatterCallback: (v) =>
                context.tr('{count} 位', {'count': v.round()}),
            onChanged: (v) => _change(_options.copyWith(length: v.round())),
          ),
          for (final option
              in <(String, bool, AccountPasswordOptions Function(bool))>[
                (
                  '大写字母',
                  _options.uppercase,
                  (v) => _options.copyWith(uppercase: v),
                ),
                (
                  '小写字母',
                  _options.lowercase,
                  (v) => _options.copyWith(lowercase: v),
                ),
                ('数字', _options.digits, (v) => _options.copyWith(digits: v)),
                (
                  '特殊字符',
                  _options.symbols,
                  (v) => _options.copyWith(symbols: v),
                ),
                (
                  '排除容易混淆字符',
                  _options.excludeAmbiguous,
                  (v) => _options.copyWith(excludeAmbiguous: v),
                ),
              ])
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(option.$1),
              value: option.$2,
              onChanged: (v) => _change(option.$3(v)),
            ),
          const Text('强度提示仅为本机建议，不代表已检测泄露或保证安全。'),
          Text(
            _options.length >= 20 && _options.categoryCount >= 3
                ? '生成强度建议：很强'
                : _options.length >= 16 && _options.categoryCount >= 2
                ? '生成强度建议：强'
                : _options.length >= 12
                ? '生成强度建议：一般'
                : '生成强度建议：偏弱',
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('use-generated-password'),
            onPressed: _value.isEmpty
                ? null
                : () => Navigator.pop(context, _value),
            child: const Text('填入当前表单'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    ),
  );
}
