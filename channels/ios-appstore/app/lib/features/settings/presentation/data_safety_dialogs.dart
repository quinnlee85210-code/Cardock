import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

Future<bool> safetyConfirm(
  BuildContext context,
  String title,
  String message, {
  String action = '继续',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> safetyInput(
  BuildContext context,
  String label, {
  bool secret = true,
  bool allowVisibilityToggle = false,
  String? message,
  String? Function(String)? validator,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SafetyInputDialog(
    label: label,
    secret: secret,
    allowVisibilityToggle: allowVisibilityToggle,
    message: message,
    validator: validator,
  ),
);

class _SafetyInputDialog extends StatefulWidget {
  const _SafetyInputDialog({
    required this.label,
    required this.secret,
    required this.allowVisibilityToggle,
    this.message,
    this.validator,
  });
  final String label;
  final bool secret;
  final bool allowVisibilityToggle;
  final String? message;
  final String? Function(String)? validator;
  @override
  State<_SafetyInputDialog> createState() => _SafetyInputDialogState();
}

class _SafetyInputDialogState extends State<_SafetyInputDialog>
    with WidgetsBindingObserver {
  final controller = TextEditingController();
  bool _passwordVisible = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _passwordVisible) {
      setState(() => _passwordVisible = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  void finish(bool accepted) {
    if (accepted) {
      final error = widget.validator?.call(controller.text);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    }
    final value = accepted ? controller.text : null;
    controller.clear();
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.label),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.message != null) Text(widget.message!),
          TextField(
            controller: controller,
            obscureText: widget.secret && !_passwordVisible,
            enableIMEPersonalizedLearning: !widget.secret,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: widget.secret ? 4096 : 100,
            decoration: InputDecoration(
              labelText: context.tr(widget.label),
              errorText: _error == null ? null : context.tr(_error!),
              errorMaxLines: 4,
              suffixIcon: widget.secret && widget.allowVisibilityToggle
                  ? IconButton(
                      tooltip: context.tr(_passwordVisible ? '隐藏密码' : '显示密码'),
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => finish(false), child: const Text('取消')),
      FilledButton(onPressed: () => finish(true), child: const Text('确认')),
    ],
  );
}
