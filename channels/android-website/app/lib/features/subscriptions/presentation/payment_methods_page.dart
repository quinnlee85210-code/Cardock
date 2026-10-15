import '../../../app/app_state.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../domain/subscription_record.dart';

const paymentMethodPresets = [
  '微信支付',
  '支付宝',
  '银行卡',
  'App Store',
  'Google Play',
  'PayPal',
  '其他',
];

class PaymentMethodsPage extends StatelessWidget {
  const PaymentMethodsPage({required this.state, super.key});
  final AppState state;
  Future<void> _edit(BuildContext context, [PaymentMethodRecord? method]) =>
      showDialog<void>(
        context: context,
        builder: (context) =>
            _PaymentMethodEditor(state: state, method: method),
      );
  Future<void> _merge(BuildContext context, PaymentMethodRecord method) async {
    final id = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('合并到支付方式'),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('将重新关联订阅、回收站与费用记录；保留历史付款名称快照。'),
          ),
          for (final p in state.paymentMethods.where(
            (p) => p.id != method.id && !p.archived,
          ))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p.id),
              child: Text(p.name, translate: false),
            ),
        ],
      ),
    );
    if (id != null) await state.mergePaymentMethods(method.id, id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('支付方式管理')),
    floatingActionButton: state.hasSubscriptionOnlyAccess
        ? null
        : FloatingActionButton(
            tooltip: context.tr('新增支付方式'),
            onPressed: () => _edit(context),
            child: const Icon(Icons.add),
          ),
    body: ListenableBuilder(
      listenable: state,
      builder: (context, child) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('仅记录名称与简标。不要填写完整卡号、安全码、支付密码或验证码。归档后仍保留历史记录。'),
          if (state.paymentMethods.isEmpty)
            const ListTile(title: Text('暂无支付方式')),
          for (final p in state.paymentMethods)
            Card(
              child: ListTile(
                title: Text(p.name, translate: false),
                subtitle: Text(
                  context.tr(
                    '{count} 条订阅 · {trash} 条回收站 · {expenses} 笔费用 · {status}',
                    {
                      'trash': state.trashSubscriptions
                          .where(
                            (t) => t.record.management?.paymentMethodId == p.id,
                          )
                          .length,
                      'expenses': state.subscriptionExpenses
                          .where((e) => e.paymentMethodId == p.id)
                          .length,
                      'count': state.subscriptions
                          .where((s) => s.management?.paymentMethodId == p.id)
                          .length,
                      'status': context.tr(p.archived ? '已归档' : '可使用'),
                    },
                  ),
                  translate: false,
                ),
                onTap: state.hasSubscriptionOnlyAccess
                    ? null
                    : () => _edit(context, p),
                trailing: state.hasSubscriptionOnlyAccess
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: context.tr('支付方式操作'),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'archive',
                            child: Text(p.archived ? '恢复支付方式' : '归档支付方式'),
                          ),
                          const PopupMenuItem(
                            value: 'merge',
                            child: Text('合并支付方式'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除未使用的方式'),
                          ),
                        ],
                        onSelected: (action) async {
                          if (action == 'archive') {
                            await state.savePaymentMethod(
                              p.copyWith(archived: !p.archived),
                            );
                          }
                          if (action == 'merge' && context.mounted) {
                            await _merge(context, p);
                          }
                          if (action == 'delete' && context.mounted) {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('删除未使用的方式'),
                                content: const Text('已被订阅、回收站或费用引用的方式不能删除。'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('确认删除'),
                                  ),
                                ],
                              ),
                            );
                            if (yes == true) {
                              final saved = await state.deletePaymentMethod(
                                p.id,
                              );
                              if (!saved && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('使用中的支付方式只能归档')),
                                );
                              }
                            }
                          }
                        },
                      ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _PaymentMethodEditor extends StatefulWidget {
  const _PaymentMethodEditor({required this.state, this.method});
  final AppState state;
  final PaymentMethodRecord? method;
  @override
  State<_PaymentMethodEditor> createState() => _PaymentMethodEditorState();
}

class _PaymentMethodEditorState extends State<_PaymentMethodEditor> {
  late final _name = TextEditingController(text: widget.method?.name ?? '');
  late final _label = TextEditingController(
    text: widget.method?.shortLabel ?? '',
  );
  late final _note = TextEditingController(text: widget.method?.note ?? '');
  late PaymentMethodType _type = widget.method?.type ?? PaymentMethodType.other;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final method = PaymentMethodRecord(
        id:
            widget.method?.id ??
            'payment-${DateTime.now().toUtc().microsecondsSinceEpoch}',
        name: _name.text,
        type: _type,
        shortLabel: _label.text,
        note: _note.text,
        archived: widget.method?.archived ?? false,
      );
      final saved = await widget.state.savePaymentMethod(method);
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
      } else {
        setState(() => _error = '名称重复或保存失败，请检查后重试。');
      }
    } on Object {
      setState(() => _error = '请填写有效的支付方式名称和简标。');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.method == null ? '新增支付方式' : '编辑支付方式'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<PaymentMethodType>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '支付方式类型'),
            items: [
              for (var i = 0; i < PaymentMethodType.values.length; i++)
                DropdownMenuItem(
                  value: PaymentMethodType.values[i],
                  child: Text(paymentMethodPresets[i]),
                ),
            ],
            onChanged: (v) => setState(() {
              _type = v ?? PaymentMethodType.other;
              if (_name.text.isEmpty) {
                _name.text = context.tr(paymentMethodPresets[_type.index]);
              }
            }),
          ),
          TextFormField(
            controller: _name,
            maxLength: 100,
            decoration: const InputDecoration(labelText: '支付方式名称'),
          ),
          TextFormField(
            controller: _label,
            maxLength: 20,
            decoration: const InputDecoration(labelText: '简标或尾号（可选）'),
          ),
          TextFormField(
            controller: _note,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '备注'),
          ),
          const Text('不要填写完整卡号、安全码、支付密码或验证码。'),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
