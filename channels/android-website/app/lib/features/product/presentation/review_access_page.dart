import '../../../core/entitlements/review_access_service.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

class ReviewAccessPage extends StatefulWidget {
  const ReviewAccessPage({required this.controller, super.key});
  final ReviewAccessController controller;
  @override
  State<ReviewAccessPage> createState() => _ReviewAccessPageState();
}

class _ReviewAccessPageState extends State<ReviewAccessPage> {
  final _input = TextEditingController();
  String? _status;
  Future<void> _activate() async {
    final result = await widget.controller.activate(_input.text);
    _input.clear();
    if (!mounted) return;
    setState(
      () => _status = switch (result) {
        ReviewAccessResult.activated => '免费审核授权已启用。',
        ReviewAccessResult.invalid => '审核凭证无效或不适用于此应用。',
        _ => '无法安全保存审核授权，请重试。',
      },
    );
  }

  Future<void> _remove() async {
    final result = await widget.controller.remove();
    if (!mounted) return;
    setState(
      () => _status = result == ReviewAccessResult.removed
          ? '审核授权已移除；已有记录和Google已购权益保留。'
          : '无法移除审核授权，请重试。',
    );
  }

  @override
  void dispose() {
    _input.clear();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('审核访问')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.controller.value ? '免费审核授权已启用。' : '审核授权未启用',
            key: const ValueKey('review-access-state'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          const Text(
            '免费审核授权仅解除数量和主题限制，使用与正常完整版相同的功能。它不是Google购买，不会解锁保险库或备份，也不改变密码。',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            key: const ValueKey('review-access-input'),
            maxLength: 256,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: context.tr('审核凭证')),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.controller.isBusy ? null : _activate,
            key: const ValueKey('review-access-activate'),
            child: const Text('启用审核访问'),
          ),
          if (widget.controller.value)
            TextButton(
              onPressed: widget.controller.isBusy ? null : _remove,
              key: const ValueKey('review-access-remove'),
              child: const Text('移除审核授权'),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _status!,
                key: const ValueKey('review-access-result'),
              ),
            ),
          const SizedBox(height: 16),
          const Text('凭证仅供免费应用审核，请使用虚构数据。Google购买和恢复购买仍可从完整版页面操作。'),
        ],
      ),
    ),
  );
}
