import 'review_access_page.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

import '../../../core/app_metadata.dart';
import '../../../core/entitlements/distribution_channel.dart';
import '../../../core/entitlements/entitlement_model.dart';
import '../../../core/entitlements/entitlement_service.dart';
import '../../../core/entitlements/promo_activation_service.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../shared/widgets/cardock_ui.dart';
import 'promo_activation_section.dart';
import 'website_authorization_dialog.dart';

class FullVersionPage extends StatefulWidget {
  const FullVersionPage({this.controller, super.key});

  final ProductEntitlementController? controller;

  @override
  State<FullVersionPage> createState() => _FullVersionPageState();
}

class _FullVersionPageState extends State<FullVersionPage> {
  bool _operationRunning = false;
  bool _priceRequested = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_priceRequested) {
      _priceRequested = true;
      _controller(context).loadStorePrice();
    }
  }

  ProductEntitlementController _controller(BuildContext context) =>
      widget.controller ?? ProductEntitlementScope.of(context);

  PromoActivationController? _promoController(BuildContext context) =>
      PromoActivationScope.maybeOf(context);

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(text))));
  }

  Future<void> _purchase(ProductEntitlementController controller) async {
    if (_operationRunning) return;
    setState(() => _operationRunning = true);
    final result = await controller.purchase();
    if (mounted) setState(() => _operationRunning = false);
    _message(result.message);
  }

  Future<void> _restore(ProductEntitlementController controller) async {
    if (_operationRunning) return;
    setState(() => _operationRunning = true);
    if (controller.distributionChannel == CardockDistributionChannel.website) {
      await showWebsiteAuthorizationDialog(context, controller);
      if (mounted) setState(() => _operationRunning = false);
      return;
    }
    final result = await controller.restore();
    if (mounted) setState(() => _operationRunning = false);
    _message(result.message);
  }

  Future<void> _setDebugEntitlement(
    ProductEntitlementController controller,
    ProductEntitlement entitlement,
  ) async {
    if (_operationRunning) return;
    setState(() => _operationRunning = true);
    await controller.debugSetEntitlement(entitlement);
    if (!mounted) return;
    setState(() => _operationRunning = false);
    _message(entitlement.hasFullVersion ? '调试状态：已购。' : '调试状态：免费。');
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller(context);
    final promoController = _promoController(context);
    final store = controller.distributionChannel.isStore;
    return Scaffold(
      appBar: AppBar(title: const Text('解锁完整版')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          final purchased = controller.value.hasFullVersion;
          final promoActivated =
              controller.isPromoActivated && !controller.hasStorePurchase;
          final busy = _operationRunning || controller.isBusy;
          return ListView(
            key: const ValueKey<String>('full-version-page'),
            padding: const EdgeInsets.fromLTRB(
              CardockLayout.screenHorizontal,
              12,
              CardockLayout.screenHorizontal,
              32,
            ),
            children: [
              _UnlockSummary(
                purchased: purchased,
                promoActivated: promoActivated,
                reviewAuthorized:
                    controller.isReviewAuthorized &&
                    !controller.hasStorePurchase,
                store: store,
                price: controller.storePrice,
              ),
              const SizedBox(height: 18),
              if (controller.reviewAccess != null) ...[
                ListTile(
                  key: const ValueKey('review-access-entry'),
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('审核访问'),
                  subtitle: Text(
                    controller.isReviewAuthorized
                        ? '免费审核授权已启用。'
                        : '免费审核授权，仅解锁功能权益',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ReviewAccessPage(
                        controller: controller.reviewAccess!,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const _FullVersionBenefits(),
              const SizedBox(height: 18),
              Text(
                '选择适合你的版本',
                key: const ValueKey<String>('edition-comparison-title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              const _EditionCard(
                key: ValueKey<String>('full-edition-card'),
                title: '完整版',
                subtitle: '一次解锁，长期使用',
                features: <String>[
                  '订阅和账户数量无限制',
                  '解锁七套高级固定主题与自定义主题',
                  '不是订阅制，没有持续会员费用',
                ],
                highlighted: true,
              ),
              const SizedBox(height: 12),
              const _EditionCard(
                key: ValueKey<String>('free-edition-card'),
                title: '免费版',
                subtitle: '核心记录能力可以长期使用',
                features: <String>['最多 5 个订阅项', '最多 15 个账户条目', '橙墨旧刊主题（免费）'],
              ),
              const SizedBox(height: 20),
              if (purchased)
                _PurchasedBanner(
                  promoActivated: promoActivated,
                  reviewAuthorized:
                      controller.isReviewAuthorized &&
                      !controller.hasStorePurchase,
                ),
              if (!controller.hasStorePurchase && !promoActivated)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey<String>(
                        'purchase-full-version-button',
                      ),
                      onPressed: busy ? null : () => _purchase(controller),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: Text(
                        store && controller.storePrice == null
                            ? context.tr('通过商店解锁完整版')
                            : context.tr(
                                store ? '商店价格 {price} · 一次买断' : '{price} 一次买断',
                                <String, Object?>{
                                  'price':
                                      controller.storePrice ??
                                      AppMetadata.fullVersionPrice,
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      store
                          ? '通过商店一次购买，永久解锁；实际金额以商店付款窗口为准。'
                          : '一杯饮品的价格，解锁不受数量限制的长期整理空间。',
                      key: const ValueKey<String>('purchase-value-copy'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey<String>('restore-purchase-button'),
                onPressed: busy ? null : () => _restore(controller),
                child: Text(
                  controller.distributionChannel ==
                          CardockDistributionChannel.website
                      ? '导入本安装授权'
                      : '恢复购买',
                ),
              ),
              if (promoController != null &&
                  controller.distributionChannel ==
                      CardockDistributionChannel.development) ...[
                const SizedBox(height: 16),
                PromoActivationSection(
                  promoController: promoController,
                  entitlementController: controller,
                  enabled: !busy,
                ),
              ],
              if (controller.debugOverrideAvailable) ...[
                const SizedBox(height: 12),
                _DebugEntitlementSwitch(
                  purchased: controller.hasStorePurchase,
                  enabled: !busy,
                  onChanged: (value) => _setDebugEntitlement(
                    controller,
                    value
                        ? ProductEntitlement.purchased
                        : ProductEntitlement.free,
                  ),
                ),
              ],
              if (busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  key: ValueKey<String>('purchase-operation-progress'),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                controller.distributionChannel ==
                        CardockDistributionChannel.development
                    ? '本地加密 · 无需注册账号 · 商店购买记录由应用商店托管 · 推广激活仅在本机离线验签。'
                    : '日常使用保持离线。购买核验仅处理授权信息，不上传保险库内容。',
                key: const ValueKey<String>('purchase-local-privacy-note'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UnlockSummary extends StatelessWidget {
  const _UnlockSummary({
    required this.purchased,
    required this.promoActivated,
    required this.reviewAuthorized,
    required this.store,
    this.price,
  });

  final bool store;
  final String? price;

  final bool purchased;
  final bool promoActivated;
  final bool reviewAuthorized;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final contentColor = palette.gradientContent;
    return Container(
      key: const ValueKey<String>('full-version-hero'),
      padding: const EdgeInsets.all(CardockLayout.cardPaddingLarge),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            palette.gradientStart,
            palette.gradientMiddle,
            palette.gradientEnd,
          ],
        ),
        borderRadius: BorderRadius.circular(CardockRadius.hero),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.elevation2,
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: contentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(CardockRadius.control),
                ),
                child: Icon(
                  purchased
                      ? Icons.verified_rounded
                      : Icons.workspace_premium_outlined,
                  color: contentColor,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  purchased ? '永久完整版' : '卡坞完整版',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: contentColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            reviewAuthorized
                ? '免费审核授权已启用。'
                : promoActivated
                ? '已通过推广激活解锁'
                : purchased
                ? '已解锁完整版'
                : '一次买断，长期使用',
            key: const ValueKey<String>('full-version-status-title'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: contentColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reviewAuthorized
                ? '免费审核授权，仅解锁功能权益'
                : promoActivated
                ? '完整版权益已在本机通过 Ed25519 签名验证。'
                : purchased
                ? '感谢支持卡坞持续维护。'
                : '无限记录、全套主题；继续保持本地加密与无需注册。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: contentColor),
          ),
          if (!purchased && (!store || price != null)) ...[
            const SizedBox(height: 18),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  price ?? AppMetadata.fullVersionPrice,
                  translate: false,
                  key: const ValueKey<String>('full-version-hero-price'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: contentColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '一次买断 · 不是订阅',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: contentColor),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FullVersionBenefits extends StatelessWidget {
  const _FullVersionBenefits();

  @override
  Widget build(BuildContext context) => const CardockSurfaceCard(
    child: Column(
      children: [
        _BenefitRow(
          icon: Icons.all_inclusive_rounded,
          title: '记录不设上限',
          body: '账号与订阅数量不再受免费额度限制，已有数据始终保留。',
        ),
        SizedBox(height: 14),
        _BenefitRow(
          icon: Icons.palette_outlined,
          title: '八套固定主题与自定义主题',
          body: '从瓷蓝晴光到曜石鎏金，并支持自定义配色。',
        ),
        SizedBox(height: 14),
        _BenefitRow(
          icon: Icons.lock_outline_rounded,
          title: '本地加密方式不变',
          body: '无需注册登录，不把保险库上传到公网或云端。',
        ),
      ],
    ),
  );
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CardockSemanticIcon(icon: icon, color: palette.primary, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(body, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditionCard extends StatelessWidget {
  const _EditionCard({
    required this.title,
    required this.subtitle,
    required this.features,
    this.highlighted = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<String> features;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return CardockSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 3),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          for (final feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    highlighted
                        ? Icons.check_circle_rounded
                        : Icons.check_rounded,
                    size: 19,
                    color: highlighted
                        ? palette.statusNormal
                        : palette.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(feature)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PurchasedBanner extends StatelessWidget {
  const _PurchasedBanner({
    required this.promoActivated,
    required this.reviewAuthorized,
  });

  final bool promoActivated;
  final bool reviewAuthorized;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Container(
      key: const ValueKey<String>('full-version-purchased-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.primarySoft,
        borderRadius: BorderRadius.circular(CardockRadius.control),
        border: Border.all(color: palette.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: palette.statusNormal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reviewAuthorized
                  ? '免费审核授权已启用。'
                  : promoActivated
                  ? '已通过推广激活解锁，所有数量限制与主题限制均已移除。'
                  : '已解锁，所有数量限制与主题限制均已移除。',
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugEntitlementSwitch extends StatelessWidget {
  const _DebugEntitlementSwitch({
    required this.purchased,
    required this.enabled,
    required this.onChanged,
  });

  final bool purchased;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => CardockSurfaceCard(
    child: SwitchListTile.adaptive(
      key: const ValueKey<String>('debug-entitlement-switch'),
      contentPadding: EdgeInsets.zero,
      title: const Text('调试权益状态'),
      subtitle: const Text('仅调试构建可见，用于验证免费版与已购态。'),
      value: purchased,
      onChanged: enabled ? onChanged : null,
    ),
  );
}
