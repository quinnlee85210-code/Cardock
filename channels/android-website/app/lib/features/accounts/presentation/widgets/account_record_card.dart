import '../../../../l10n/localized_material.dart';

import '../../../../core/preferences/record_display_mode.dart';
import '../../../../core/theme/cardock_tokens.dart';
import '../../../../l10n/context_l10n.dart';
import '../../../../l10n/translations_records.dart';
import '../../../../shared/widgets/cardock_platform_icon.dart';
import '../../../../shared/widgets/cardock_ui.dart';
import '../../../subscriptions/domain/subscription_record.dart';
import '../../domain/account_record.dart';

class AccountRecordCard extends StatefulWidget {
  const AccountRecordCard({
    required this.account,
    required this.subscriptions,
    this.displayMode = RecordDisplayMode.expandedCards,
    this.showCategory = true,
    this.onOpen,
    this.onEdit,
    this.onDelete,
    this.onAddSubscription,
    super.key,
  });

  final AccountRecord account;
  final List<SubscriptionRecord> subscriptions;
  final RecordDisplayMode displayMode;
  final bool showCategory;
  final VoidCallback? onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onAddSubscription;

  @override
  State<AccountRecordCard> createState() => _AccountRecordCardState();
}

class _AccountRecordCardState extends State<AccountRecordCard> {
  late bool _expanded;

  bool get _hasMenu =>
      widget.onEdit != null ||
      widget.onDelete != null ||
      widget.onAddSubscription != null;

  @override
  void initState() {
    super.initState();
    _expanded = widget.displayMode != RecordDisplayMode.collapsibleCards;
  }

  @override
  void didUpdateWidget(covariant AccountRecordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayMode != widget.displayMode) {
      _expanded = widget.displayMode != RecordDisplayMode.collapsibleCards;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.displayMode == RecordDisplayMode.compactList) {
      return _buildCompactCard(context);
    }

    final showDetails =
        widget.displayMode == RecordDisplayMode.expandedCards || _expanded;
    final palette = context.cardockTheme.palette;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (showDetails) ...[
          Positioned(
            left: 10,
            top: 8,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surfaceAlt.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(CardockRadius.card),
                border: Border.all(color: palette.border),
              ),
            ),
          ),
          Positioned(
            left: 5,
            top: 4,
            right: 5,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surface.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(CardockRadius.card),
                border: Border.all(color: palette.border),
              ),
            ),
          ),
        ],
        Padding(
          padding: EdgeInsets.only(
            right: showDetails ? 10 : 0,
            bottom: showDetails ? 8 : 0,
          ),
          child: CardockSurfaceCard(
            key: ValueKey<String>('account-card-${widget.account.id}'),
            padding: EdgeInsets.zero,
            onTap: widget.onOpen,
            semanticLabel: context.tr('账号卡片，{name}', <String, Object?>{
              'name': widget.account.platformName,
            }),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: showDetails ? 181 : 68,
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(CardockRadius.card),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context),
                        AnimatedSize(
                          duration: CardockMotion.resolve(
                            context,
                            CardockMotion.cardExpand,
                          ),
                          curve: CardockMotion.standard,
                          alignment: Alignment.topCenter,
                          child: showDetails
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: _detailWidgets(context),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCard(BuildContext context) {
    final account = widget.account;
    final subscriptionLabel = _subscriptionCountLabel(
      context,
      widget.subscriptions.length,
    );

    return CardockSurfaceCard(
      key: ValueKey<String>('account-card-${account.id}'),
      padding: EdgeInsets.zero,
      onTap: widget.onOpen,
      semanticLabel: context.tr(
        '账号卡片，{name}，{subscriptions}',
        <String, Object?>{
          'name': account.platformName,
          'subscriptions': subscriptionLabel,
        },
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 68,
            decoration: BoxDecoration(
              color: context.cardockTheme.palette.primary,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(CardockRadius.card),
              ),
            ),
          ),
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 68),
                child: ListTile(
                  dense: true,
                  minTileHeight: 68,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  leading: CardockResolvedPlatformIcon(
                    key: ValueKey<String>('account-brand-icon-${account.id}'),
                    name: account.platformName,
                    category: account.category,
                    size: 38,
                    role: CardockPlatformIconRole.account,
                    semanticLabel: context.tr('{name}图标', <String, Object?>{
                      'name': account.platformName,
                    }),
                  ),
                  title: Text(
                    account.platformName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    translate: false,
                  ),
                  subtitle: Text(
                    '${_maskedLoginSummary(context, account)} · $subscriptionLabel',
                    key: ValueKey<String>(
                      'account-login-visible-${account.id}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    translate: false,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasMenu) _buildMenu(),
                      if (widget.onOpen != null)
                        const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final account = widget.account;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final subscriptionLabel = _subscriptionCountLabel(
      context,
      widget.subscriptions.length,
    );
    return SizedBox(
      height: 48 + ((textScale - 1).clamp(0.0, 1.0) * 34.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CardockResolvedPlatformIcon(
            key: ValueKey<String>('account-brand-icon-${account.id}'),
            name: account.platformName,
            category: account.category,
            size: 42,
            role: CardockPlatformIconRole.account,
            semanticLabel: context.tr('{name}图标', <String, Object?>{
              'name': account.platformName,
            }),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.platformName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  translate: false,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_maskedLoginSummary(context, account)} · $subscriptionLabel',
                  key: ValueKey<String>('account-login-visible-${account.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  translate: false,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.cardockTheme.palette.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (widget.displayMode == RecordDisplayMode.collapsibleCards)
            IconButton(
              key: ValueKey<String>('toggle-account-${account.id}'),
              tooltip: context.tr(_expanded ? '折叠卡片' : '展开卡片'),
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            ),
          if (_hasMenu) _buildMenu(),
        ],
      ),
    );
  }

  PopupMenuButton<_AccountCardAction> _buildMenu() {
    return PopupMenuButton<_AccountCardAction>(
      key: ValueKey<String>('account-menu-${widget.account.id}'),
      tooltip: context.tr('账号操作'),
      onSelected: (action) {
        switch (action) {
          case _AccountCardAction.edit:
            widget.onEdit?.call();
          case _AccountCardAction.addSubscription:
            widget.onAddSubscription?.call();
          case _AccountCardAction.delete:
            widget.onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        if (widget.onEdit != null)
          const PopupMenuItem<_AccountCardAction>(
            value: _AccountCardAction.edit,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('编辑账号'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (widget.onAddSubscription != null)
          const PopupMenuItem<_AccountCardAction>(
            value: _AccountCardAction.addSubscription,
            child: ListTile(
              leading: Icon(Icons.add_card_outlined),
              title: Text('新增订阅'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (widget.onDelete != null)
          const PopupMenuItem<_AccountCardAction>(
            value: _AccountCardAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('删除账号'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  List<Widget> _detailWidgets(BuildContext context) {
    final account = widget.account;
    final subscriptions = widget.subscriptions;
    final palette = context.cardockTheme.palette;
    final visibleSubscriptions = subscriptions
        .take(2)
        .map((item) => item.serviceName)
        .join(context.tr('、'));
    final relatedSubscriptionLabel = subscriptions.isEmpty
        ? context.tr('关联订阅：暂无')
        : subscriptions.length > 2
        ? context.tr('关联订阅：{names}，另有{count}项', <String, Object?>{
            'names': visibleSubscriptions,
            'count': subscriptions.length - 2,
          })
        : context.tr('关联订阅：{names}', <String, Object?>{
            'names': visibleSubscriptions,
          });
    return <Widget>[
      Divider(height: 1, color: palette.divider),
      const SizedBox(height: 5),
      _AccountStatusGrid(
        statuses: [
          _AccountFieldStatus(
            Icons.badge_outlined,
            palette.fieldLogin,
            '用户名',
            account.username != null,
          ),
          _AccountFieldStatus(
            Icons.person_outline,
            palette.fieldLogin,
            '登录账号',
            account.loginAccount != null,
          ),
          _AccountFieldStatus(
            Icons.phone_outlined,
            palette.fieldPhone,
            '绑定手机号',
            account.boundPhone != null,
          ),
          _AccountFieldStatus(
            Icons.email_outlined,
            palette.fieldEmail,
            '绑定邮箱',
            account.boundEmail != null,
          ),
          _AccountFieldStatus(
            Icons.password_outlined,
            palette.fieldPassword,
            '登录密码',
            account.password != null,
          ),
          _AccountFieldStatus(
            Icons.language_outlined,
            palette.fieldUrl,
            '网址',
            account.website != null,
          ),
          _AccountFieldStatus(
            Icons.notes_outlined,
            palette.fieldNote,
            '备注',
            account.notes != null,
          ),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Icon(Icons.link_rounded, size: 15, color: palette.fieldSubscription),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              relatedSubscriptionLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              translate: false,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 10),
            ),
          ),
          if (widget.onOpen != null)
            IconButton(
              key: ValueKey<String>('open-account-${account.id}'),
              onPressed: widget.onOpen,
              tooltip: context.tr('查看详情'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
            ),
        ],
      ),
    ];
  }
}

String _subscriptionCountLabel(BuildContext context, int count) => count == 0
    ? context.tr('无订阅')
    : localizedSubscriptionItemCount(context.l10n.language, count);

String _maskedLoginSummary(BuildContext context, AccountRecord account) {
  final raw = account.loginAccount ?? account.username;
  if (raw == null || raw.trim().isEmpty) {
    return context.tr('账号摘要：未填写');
  }
  final value = raw.trim();
  final at = value.indexOf('@');
  if (at > 0 && at < value.length - 1) {
    final local = value.substring(0, at);
    final domain = value.substring(at + 1);
    final visibleLocal = local.characters.take(local.length > 1 ? 2 : 1).join();
    return context.tr('账号摘要：{value}', <String, Object?>{
      'value': '$visibleLocal•••@$domain',
    });
  }
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 7 && digits.length == value.length) {
    return context.tr('账号摘要：{value}', <String, Object?>{
      'value':
          '${digits.substring(0, 3)}••••'
          '${digits.substring(digits.length - 4)}',
    });
  }
  final characters = value.characters.toList(growable: false);
  if (characters.length <= 2) {
    return context.tr('账号摘要：{value}', <String, Object?>{
      'value': '${characters.first}•',
    });
  }
  if (characters.length <= 6) {
    return context.tr('账号摘要：{value}', <String, Object?>{
      'value': '${characters.first}•••${characters.last}',
    });
  }
  return context.tr('账号摘要：{value}', <String, Object?>{
    'value':
        '${characters.take(2).join()}••••'
        '${characters.skip(characters.length - 2).join()}',
  });
}

enum _AccountCardAction { edit, addSubscription, delete }

final class _AccountFieldStatus {
  const _AccountFieldStatus(this.icon, this.color, this.label, this.filled);

  final IconData icon;
  final Color color;
  final String label;
  final bool filled;
}

class _AccountStatusGrid extends StatelessWidget {
  const _AccountStatusGrid({required this.statuses});

  final List<_AccountFieldStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 2,
          children: [
            for (final status in statuses)
              SizedBox(
                width: itemWidth,
                height: 22 + ((textScale - 1).clamp(0.0, 1.0) * 18.0),
                child: Row(
                  children: [
                    Icon(status.icon, size: 14, color: status.color),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        context.tr('{label}：{status}', <String, Object?>{
                          'label': context.tr(status.label),
                          'status': context.tr(status.filled ? '已填写' : '未填写'),
                        }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        translate: false,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(fontSize: 9.5),
                      ),
                    ),
                    Icon(
                      status.filled
                          ? Icons.check_rounded
                          : Icons.remove_rounded,
                      size: 13,
                      color: status.filled
                          ? context.cardockTheme.palette.statusNormal
                          : context.cardockTheme.palette.textTertiary,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
