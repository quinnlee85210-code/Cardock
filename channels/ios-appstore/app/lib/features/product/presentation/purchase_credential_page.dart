import '../../../core/entitlements/entitlement_service.dart';
import '../../../core/entitlements/purchase_credential_model.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../l10n/localized_material.dart';
import '../../../shared/widgets/cardock_ui.dart';

class PurchaseCredentialPage extends StatelessWidget {
  const PurchaseCredentialPage({
    required this.controller,
    required this.managementAllowed,
    this.snapshotOverride,
    this.onRestoreStorePurchase,
    this.onExportWebsiteRecovery,
    this.onImportWebsiteAuthorization,
    super.key,
  });

  final ProductEntitlementController controller;
  final bool managementAllowed;
  final PurchaseCredentialSnapshot? snapshotOverride;
  final Future<void> Function()? onRestoreStorePurchase;
  final VoidCallback? onExportWebsiteRecovery;
  final VoidCallback? onImportWebsiteAuthorization;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('购买凭证')),
    body: !managementAllowed
        ? const _UnavailableForCurrentVault()
        : ListenableBuilder(
            listenable: controller,
            builder: (context, child) {
              final snapshot =
                  snapshotOverride ??
                  PurchaseCredentialSnapshot.runtime(
                    hasStorePurchase: controller.hasStorePurchase,
                    isPromoActivated: controller.isPromoActivated,
                    debugOverrideAvailable: controller.debugOverrideAvailable,
                    distributionChannel: controller.distributionChannel,
                  );
              return ListView(
                key: const ValueKey<String>('purchase-credential-page'),
                padding: const EdgeInsets.fromLTRB(
                  CardockLayout.screenHorizontal,
                  12,
                  CardockLayout.screenHorizontal,
                  32,
                ),
                children: [
                  _CredentialSummary(snapshot: snapshot),
                  const SizedBox(height: 16),
                  _CredentialDetails(snapshot: snapshot),
                  const SizedBox(height: 16),
                  _SourceActions(
                    snapshot: snapshot,
                    onRestoreStorePurchase: onRestoreStorePurchase,
                    onExportWebsiteRecovery: onExportWebsiteRecovery,
                    onImportWebsiteAuthorization: onImportWebsiteAuthorization,
                  ),
                  const SizedBox(height: 16),
                  const _SafetyBoundary(),
                ],
              );
            },
          ),
  );
}

class _UnavailableForCurrentVault extends StatelessWidget {
  const _UnavailableForCurrentVault();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(CardockLayout.cardPaddingLarge),
      child: Text(
        '购买凭证只在真实保险库完整解锁后显示；订阅只读视图和诱饵保险库不会显示付款身份或恢复秘密。',
        key: ValueKey<String>('purchase-credential-access-denied'),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _CredentialSummary extends StatelessWidget {
  const _CredentialSummary({required this.snapshot});

  final PurchaseCredentialSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return CardockSurfaceCard(
      key: const ValueKey<String>('purchase-credential-summary'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardockSemanticIcon(
            icon:
                snapshot.authorizationState ==
                    InstallationAuthorizationState.active
                ? Icons.verified_user_outlined
                : Icons.receipt_long_outlined,
            color: palette.primary,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sourceTitle(snapshot),
                  key: const ValueKey<String>(
                    'purchase-credential-source-title',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(_stateLabel(snapshot.authorizationState)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialDetails extends StatelessWidget {
  const _CredentialDetails({required this.snapshot});

  final PurchaseCredentialSnapshot snapshot;

  @override
  Widget build(BuildContext context) => CardockSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('凭证信息', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        _DetailRow(label: '权益来源', value: _sourceTitle(snapshot)),
        _DetailRow(
          label: '订单参考',
          value: snapshot.orderReference ?? '未提供',
          translateValue: snapshot.orderReference == null,
        ),
        _DetailRow(
          label: '购买日期',
          value: snapshot.purchasedOn == null
              ? '未提供'
              : _dateOnly(snapshot.purchasedOn!),
          translateValue: snapshot.purchasedOn == null,
        ),
        _DetailRow(
          label: '本安装授权',
          value: _stateLabel(snapshot.authorizationState),
        ),
        if (snapshot.authorizationId case final id?)
          _DetailRow(label: '授权编号', value: id, translateValue: false),
        if (snapshot.remainingSlotsAtIssue case final remaining?)
          _DetailRow(
            label: '最近签发时剩余名额',
            value: '$remaining',
            translateValue: false,
          ),
        if (snapshot.remainingSlotsAtIssue != null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('这里只是最近一次签发时的记录，实时名额以官网为准。'),
          ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.translateValue = true,
  });

  final String label;
  final String value;
  final bool translateValue;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: Text(value, translate: translateValue)),
      ],
    ),
  );
}

class _SourceActions extends StatelessWidget {
  const _SourceActions({
    required this.snapshot,
    required this.onRestoreStorePurchase,
    required this.onExportWebsiteRecovery,
    required this.onImportWebsiteAuthorization,
  });

  final PurchaseCredentialSnapshot snapshot;
  final Future<void> Function()? onRestoreStorePurchase;
  final VoidCallback? onExportWebsiteRecovery;
  final VoidCallback? onImportWebsiteAuthorization;

  @override
  Widget build(BuildContext context) {
    final website = snapshot.source == PurchaseCredentialSource.website;
    final google = snapshot.source == PurchaseCredentialSource.googlePlay;
    return CardockSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('可用操作', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          if (website) ...[
            OutlinedButton.icon(
              key: const ValueKey<String>('export-website-recovery-proof'),
              onPressed: onExportWebsiteRecovery,
              icon: const Icon(Icons.download_outlined),
              label: const Text('导出购买恢复证明'),
            ),
            OutlinedButton.icon(
              key: const ValueKey<String>(
                'import-website-installation-license',
              ),
              onPressed: onImportWebsiteAuthorization,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('导入本安装授权'),
            ),
            const Text('新手机或清除数据后，需要通过官网核验恢复证明并领取新的本安装授权。'),
          ] else if (snapshot.source == PurchaseCredentialSource.appStore) ...[
            FilledButton.icon(
              onPressed: onRestoreStorePurchase,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('验证 App Store 购买'),
            ),
            const Text('通过商店一次购买，永久解锁；实际金额以商店付款窗口为准。'),
          ] else if (google) ...[
            FilledButton.icon(
              key: const ValueKey<String>('restore-google-play-purchase'),
              onPressed: onRestoreStorePurchase,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('从 Google Play 恢复购买'),
            ),
            const Text('通过商店一次购买，永久解锁；实际金额以商店付款窗口为准。'),
          ] else if (snapshot.source == PurchaseCredentialSource.promotion)
            const Text('既有推广激活继续使用独立的本机绑定规则，不会自动变成官网购买或 Google Play 订单。')
          else if (snapshot.source ==
              PurchaseCredentialSource.developmentSimulation)
            const Text('这是调试构建的模拟购买，不是付款记录，也不能导出生产凭证。')
          else if (snapshot.source == PurchaseCredentialSource.unknownStore)
            const Text('当前网关没有提供可核实的渠道元数据，因此不会把该权益标成官网或 Google Play 购买。')
          else
            const Text('当前没有可核实的购买凭证。官网与 Google Play 真实购买尚未接入当前 Release。'),
        ],
      ),
    );
  }
}

class _SafetyBoundary extends StatelessWidget {
  const _SafetyBoundary();

  @override
  Widget build(BuildContext context) => const CardockSurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('保管提醒'),
        SizedBox(height: 6),
        Text('订单编号不是购买者身份证明。官网购买恢复证明代表申请新安装授权的权利，请像重要密码一样保管，不要截图公开或通过普通链接分享。'),
        SizedBox(height: 6),
        Text('购买凭证不会读取或上传保险库、主密码、备份密码或业务加密密钥。'),
      ],
    ),
  );
}

String _sourceTitle(PurchaseCredentialSnapshot snapshot) {
  if (snapshot.authorizationState ==
      InstallationAuthorizationState.notConfigured) {
    if (snapshot.source == PurchaseCredentialSource.website) {
      return '官网渠道（当前未购买）';
    }
    if (snapshot.source == PurchaseCredentialSource.googlePlay) {
      return 'Google Play（当前未购买）';
    }
  }
  return switch (snapshot.source) {
    PurchaseCredentialSource.none => '未购买',
    PurchaseCredentialSource.website => '官网购买',
    PurchaseCredentialSource.googlePlay => 'Google Play',
    PurchaseCredentialSource.appStore => 'App Store',
    PurchaseCredentialSource.promotion => '既有推广激活',
    PurchaseCredentialSource.developmentSimulation => '开发环境模拟购买',
    PurchaseCredentialSource.unknownStore => '商店来源待确认',
  };
}

String _stateLabel(InstallationAuthorizationState state) => switch (state) {
  InstallationAuthorizationState.notConfigured => '未配置',
  InstallationAuthorizationState.pending => '等待核验',
  InstallationAuthorizationState.active => '当前安装有效',
  InstallationAuthorizationState.invalid => '无效或不匹配',
};

String _dateOnly(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
