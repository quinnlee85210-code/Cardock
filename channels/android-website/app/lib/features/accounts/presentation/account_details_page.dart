import 'dart:async';

import '../../../l10n/localized_material.dart';

import '../../../core/platform/safe_url_launcher.dart';
import '../../../core/platform/sensitive_clipboard.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/translations_records.dart';
import '../../../shared/widgets/cardock_platform_icon.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../../subscriptions/domain/subscription_record.dart';
import '../domain/account_record.dart';
import 'password_review_center_page.dart';
import 'account_custom_fields_card.dart';

typedef AccountEditAction =
    Future<AccountRecord?> Function(AccountRecord account);
typedef AccountDeleteAction = Future<bool> Function(AccountRecord account);
typedef AccountSubscriptionAction =
    Future<void> Function(AccountRecord account);
typedef AccountSubscriptionsProvider =
    List<SubscriptionRecord> Function(AccountRecord account);
typedef AccountRecordProvider = AccountRecord? Function(String accountId);
typedef AccountPasswordReviewAction = Future<bool> Function(String accountId);
typedef AccountPasswordReviewIntervalAction =
    Future<bool> Function(String accountId, int? intervalDays);
typedef AccountPasswordReviewSnoozeAction =
    Future<bool> Function(String accountId, int days);

class AccountDetailsPage extends StatefulWidget {
  const AccountDetailsPage({
    required this.account,
    required this.subscriptions,
    this.subscriptionsProvider,
    this.onEdit,
    this.onDelete,
    this.onAddSubscription,
    this.accountProvider,
    this.onConfirmPasswordCurrent,
    this.onMarkPlatformPasswordChanged,
    this.onMarkPasswordNeedsReview,
    this.onSetPasswordReviewInterval,
    this.onSnoozePasswordReview,
    this.sensitiveClipboard = const PlatformSensitiveClipboard(),
    this.urlLauncher = const SafeUrlLauncher(),
    this.passwordRevealDuration = const Duration(seconds: 30),
    super.key,
  });

  final AccountRecord account;
  final List<SubscriptionRecord> subscriptions;
  final AccountSubscriptionsProvider? subscriptionsProvider;
  final AccountEditAction? onEdit;
  final AccountDeleteAction? onDelete;
  final AccountSubscriptionAction? onAddSubscription;
  final AccountRecordProvider? accountProvider;
  final AccountPasswordReviewAction? onConfirmPasswordCurrent;
  final AccountPasswordReviewAction? onMarkPlatformPasswordChanged;
  final AccountPasswordReviewAction? onMarkPasswordNeedsReview;
  final AccountPasswordReviewIntervalAction? onSetPasswordReviewInterval;
  final AccountPasswordReviewSnoozeAction? onSnoozePasswordReview;
  final SensitiveClipboard sensitiveClipboard;
  final ExternalUrlLauncher urlLauncher;
  final Duration passwordRevealDuration;

  @override
  State<AccountDetailsPage> createState() => _AccountDetailsPageState();
}

class _AccountDetailsPageState extends State<AccountDetailsPage>
    with WidgetsBindingObserver {
  late AccountRecord _account;
  bool _passwordVisible = false;
  bool _actionBusy = false;
  Timer? _passwordTimer;

  List<SubscriptionRecord> get _subscriptions =>
      widget.subscriptionsProvider?.call(_account) ?? widget.subscriptions;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant AccountDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account) {
      _account = widget.account;
      _hidePassword();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _hidePassword();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordTimer?.cancel();
    super.dispose();
  }

  void _hidePassword() {
    _passwordTimer?.cancel();
    _passwordTimer = null;
    if (_passwordVisible && mounted) {
      setState(() => _passwordVisible = false);
    } else {
      _passwordVisible = false;
    }
  }

  void _togglePassword() {
    _passwordTimer?.cancel();
    setState(() => _passwordVisible = !_passwordVisible);
    if (_passwordVisible) {
      _passwordTimer = Timer(widget.passwordRevealDuration, _hidePassword);
    }
  }

  Future<void> _copySensitive(String value, String label) async {
    final localizedLabel = context.tr(label);
    try {
      await widget.sensitiveClipboard.copySensitive(
        text: value,
        label: localizedLabel,
        clearAfter: const Duration(seconds: 60),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              context.tr('已安全复制{label}，60秒后自动清除。', <String, Object?>{
                'label': localizedLabel,
              }),
              translate: false,
            ),
          ),
        );
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('复制失败，未写入剪贴板。')));
    }
  }

  Future<void> _openWebsite() async {
    final website = _account.website;
    if (website == null) {
      return;
    }
    try {
      final opened = await widget.urlLauncher.open(website);
      if (!opened && mounted) {
        _showMessage('系统没有可打开该网址的应用。');
      }
    } on FormatException {
      if (mounted) {
        _showMessage('网址格式无效，仅支持安全的 http/https 地址。');
      }
    } on Object {
      if (mounted) {
        _showMessage('打开网址失败。');
      }
    }
  }

  Future<void> _edit() async {
    final onEdit = widget.onEdit;
    if (onEdit == null || _actionBusy) {
      return;
    }
    setState(() => _actionBusy = true);
    try {
      final updated = await onEdit(_account);
      if (updated != null && mounted) {
        setState(() {
          _account = updated;
          _passwordVisible = false;
        });
        _passwordTimer?.cancel();
        _showMessage('账号修改已加密保存。');
      }
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  Future<void> _addSubscription() async {
    final action = widget.onAddSubscription;
    if (action == null || _actionBusy) {
      return;
    }
    setState(() => _actionBusy = true);
    try {
      await action(_account);
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null || _actionBusy) {
      return;
    }
    final subscriptionCount = _subscriptions.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移入回收站？'),
        content: Text(
          subscriptionCount == 0
              ? '记录将在回收站保留 30 天，可恢复。这不会注销对应平台账号。'
              : dialogContext.tr(
                  '这个账号关联了{countLabel}，将一起移入回收站保留 30 天。历史费用保留；这不会在对应平台取消订阅或停止扣费。',
                  <String, Object?>{
                    'countLabel': localizedSubscriptionItemCount(
                      dialogContext.l10n.language,
                      subscriptionCount,
                    ),
                  },
                ),
        ),
        actions: [
          TextButton(
            key: const ValueKey<String>('cancel-delete-account'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('confirm-delete-account'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _actionBusy = true);
    bool deleted = false;
    try {
      deleted = await onDelete(_account);
    } finally {
      if (mounted && !deleted) {
        setState(() => _actionBusy = false);
      }
    }
    if (!mounted) {
      return;
    }
    if (deleted) {
      Navigator.of(context).pop(true);
    } else {
      _showMessage('删除失败，原记录仍保留。');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final password = _account.password;
    final subscriptions = _subscriptions;
    final palette = context.cardockTheme.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('账号详情'),
        actions: [
          if (widget.onEdit != null)
            IconButton(
              key: const ValueKey<String>('edit-account-action'),
              tooltip: context.tr('编辑账号'),
              onPressed: _actionBusy ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (widget.onDelete != null)
            IconButton(
              key: const ValueKey<String>('delete-account-action'),
              tooltip: context.tr('删除账号'),
              onPressed: _actionBusy ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SingleChildScrollView(
        key: const ValueKey<String>('account-details-page'),
        padding: const EdgeInsets.fromLTRB(
          CardockLayout.screenHorizontal,
          8,
          CardockLayout.screenHorizontal,
          32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardockSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CardockResolvedPlatformIcon(
                        key: ValueKey<String>(
                          'account-detail-brand-icon-${_account.id}',
                        ),
                        name: _account.platformName,
                        category: _account.category,
                        size: 48,
                        role: CardockPlatformIconRole.account,
                        semanticLabel: context.tr('{name}图标', <String, Object?>{
                          'name': _account.platformName,
                        }),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _account.platformName,
                              style: Theme.of(context).textTheme.titleLarge,
                              translate: false,
                            ),
                            if (_account.category case final category?) ...[
                              const SizedBox(height: 8),
                              _AccountCategoryPill(label: category),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _DetailSectionLabel(label: '基本资料'),
                  _DetailRow(
                    icon: Icons.badge_outlined,
                    color: palette.fieldLogin,
                    label: '用户名',
                    value: _account.username,
                    onCopy: _account.username == null
                        ? null
                        : () => _copySensitive(_account.username!, '用户名'),
                  ),
                  _DetailRow(
                    icon: Icons.person_outline_rounded,
                    color: palette.fieldLogin,
                    label: '登录账号',
                    value: _account.loginAccount,
                    onCopy: _account.loginAccount == null
                        ? null
                        : () => _copySensitive(_account.loginAccount!, '登录账号'),
                  ),
                  const _DetailSectionDivider(),
                  const _DetailSectionLabel(label: '联系绑定'),
                  _DetailRow(
                    icon: Icons.phone_outlined,
                    color: palette.fieldPhone,
                    label: '绑定手机号',
                    value: _account.boundPhone,
                  ),
                  _DetailRow(
                    icon: Icons.email_outlined,
                    color: palette.fieldEmail,
                    label: '绑定邮箱',
                    value: _account.boundEmail,
                  ),
                  const _DetailSectionDivider(),
                  const _DetailSectionLabel(label: '安全信息'),
                  _PasswordRow(
                    password: password,
                    visible: _passwordVisible,
                    onToggle: password == null ? null : _togglePassword,
                    onCopy: password == null
                        ? null
                        : () => _copySensitive(password, '登录密码'),
                  ),
                  const _DetailSectionDivider(),
                  const _DetailSectionLabel(label: '补充信息'),
                  _DetailRow(
                    icon: Icons.language_outlined,
                    color: palette.fieldUrl,
                    label: '网址',
                    value: _account.website,
                    action: _account.website == null
                        ? null
                        : IconButton(
                            key: const ValueKey<String>('open-account-website'),
                            tooltip: context.tr('使用系统浏览器打开'),
                            onPressed: _openWebsite,
                            icon: const Icon(Icons.open_in_new),
                          ),
                  ),
                  _DetailRow(
                    icon: Icons.notes_outlined,
                    color: palette.fieldNote,
                    label: '备注',
                    value: _account.notes,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_account.customFields.isNotEmpty) ...[
              AccountCustomFieldsCard(
                fields: _account.customFields,
                sensitiveClipboard: widget.sensitiveClipboard,
                urlLauncher: widget.urlLauncher,
                revealDuration: widget.passwordRevealDuration,
              ),
              const SizedBox(height: 12),
            ],
            if (password != null ||
                _account.passwordChangeHistory.isNotEmpty) ...[
              PasswordChangeHistoryCard(account: _account),
              const SizedBox(height: 12),
            ],
            CardockSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CardockSemanticIcon(
                        icon: Icons.event_repeat_rounded,
                        color: palette.fieldSubscription,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.tr('订阅记录（{count}）', <String, Object?>{
                            'count': subscriptions.length,
                          }),
                          style: Theme.of(context).textTheme.titleMedium,
                          translate: false,
                        ),
                      ),
                      if (widget.onAddSubscription != null)
                        TextButton.icon(
                          key: const ValueKey<String>(
                            'add-subscription-for-account',
                          ),
                          onPressed: _actionBusy ? null : _addSubscription,
                          icon: const Icon(Icons.add),
                          label: const Text('新增订阅'),
                        ),
                    ],
                  ),
                  if (subscriptions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('这个账号暂无订阅记录。'),
                    )
                  else
                    for (final subscription in subscriptions) ...[
                      const Divider(height: 20),
                      Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            subscription.serviceName,
                            translate: false,
                          ),
                          subtitle: Text(
                            context.tr('{cycle} · {date}续费', <String, Object?>{
                              'cycle': localizedSubscriptionCycle(
                                context.l10n.language,
                                subscription.cycleUnit,
                                subscription.cycleCount,
                              ),
                              'date': localizedRecordDate(
                                context.l10n.language,
                                subscription.nextRenewalOn,
                              ),
                            }),
                            translate: false,
                          ),
                          trailing: CardockStatusPill(
                            status: _visualStatus(subscription.status),
                            label: localizedSubscriptionStatus(
                              context.l10n.language,
                              subscription.status,
                            ),
                          ),
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSectionLabel extends StatelessWidget {
  const _DetailSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: context.cardockTheme.palette.textSecondary,
        ),
      ),
    );
  }
}

class _DetailSectionDivider extends StatelessWidget {
  const _DetailSectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.onCopy,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String? value;
  final VoidCallback? onCopy;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardockSemanticIcon(icon: icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  value ?? context.tr('未填写'),
                  key: ValueKey<String>('account-detail-$label'),
                  style: value == null
                      ? TextStyle(color: Theme.of(context).colorScheme.outline)
                      : null,
                  translate: false,
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              key: ValueKey<String>('copy-account-$label'),
              tooltip: context.tr('复制{label}', <String, Object?>{
                'label': context.tr(label),
              }),
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
            ),
          ?action,
        ],
      ),
    );
  }
}

class _PasswordRow extends StatelessWidget {
  const _PasswordRow({
    required this.password,
    required this.visible,
    required this.onToggle,
    required this.onCopy,
  });

  final String? password;
  final bool visible;
  final VoidCallback? onToggle;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardockSemanticIcon(
            icon: Icons.password_outlined,
            color: context.cardockTheme.palette.fieldPassword,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('登录密码', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                if (password == null)
                  Text(
                    '未填写',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  )
                else if (visible)
                  ExcludeSemantics(
                    child: Text(
                      password!,
                      key: const ValueKey<String>('visible-account-password'),
                      translate: false,
                    ),
                  )
                else
                  const Text('••••••••'),
              ],
            ),
          ),
          if (onToggle != null)
            IconButton(
              key: const ValueKey<String>('toggle-detail-password'),
              tooltip: context.tr(visible ? '隐藏密码' : '显示密码30秒'),
              onPressed: onToggle,
              icon: Icon(
                visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          if (onCopy != null)
            IconButton(
              key: const ValueKey<String>('copy-account-password'),
              tooltip: context.tr('安全复制登录密码'),
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
            ),
        ],
      ),
    );
  }
}

class _AccountCategoryPill extends StatelessWidget {
  const _AccountCategoryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.cardockTheme.palette.statusInformation;
    final displayLabel = localizedAccountCategory(context.l10n.language, label);
    return Semantics(
      label: displayLabel,
      child: Tooltip(
        message: displayLabel,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(CardockRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  translate: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

CardockVisualStatus _visualStatus(SubscriptionStatus status) =>
    switch (status) {
      SubscriptionStatus.active => CardockVisualStatus.normal,
      SubscriptionStatus.paused => CardockVisualStatus.paused,
      SubscriptionStatus.cancelled => CardockVisualStatus.cancelled,
      SubscriptionStatus.expired => CardockVisualStatus.expired,
    };
