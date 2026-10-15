import '../../../core/entitlements/distribution_channel.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

import '../../../core/app_metadata.dart';
import '../../../core/entitlements/entitlement_service.dart';
import '../../../core/theme/cardock_tokens.dart';
import 'full_version_page.dart';

enum FullVersionUpsellScene { accountLimit, subscriptionLimit, premiumTheme }

final Set<FullVersionUpsellScene> _visibleUpsellScenes =
    <FullVersionUpsellScene>{};

Future<void> showFullVersionUpsell(
  BuildContext context, {
  required FullVersionUpsellScene scene,
  String? usageLabel,
}) async {
  if (!_visibleUpsellScenes.add(scene)) return;
  final controller = ProductEntitlementScope.of(context);
  try {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => _FullVersionUpsellSheet(
        scene: scene,
        store: controller.distributionChannel.isStore,
        usageLabel: usageLabel,
        onUnlock: () async {
          Navigator.of(sheetContext).pop();
          if (!context.mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) => FullVersionPage(controller: controller),
            ),
          );
        },
      ),
    );
  } finally {
    _visibleUpsellScenes.remove(scene);
  }
}

class _FullVersionUpsellSheet extends StatelessWidget {
  const _FullVersionUpsellSheet({
    required this.scene,
    required this.store,
    required this.usageLabel,
    required this.onUnlock,
  });

  final FullVersionUpsellScene scene;
  final bool store;
  final String? usageLabel;
  final VoidCallback onUnlock;

  String get _title => switch (scene) {
    FullVersionUpsellScene.accountLimit => '免费版账户数量已达上限',
    FullVersionUpsellScene.subscriptionLimit => '免费版订阅数量已达上限',
    FullVersionUpsellScene.premiumTheme => '该主题为完整版专属',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          CardockLayout.screenHorizontal,
          4,
          CardockLayout.screenHorizontal,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          key: ValueKey<String>('full-version-upsell-${scene.name}'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.workspace_premium_outlined,
              color: palette.primary,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(_title),
              key: const ValueKey<String>('full-version-upsell-title'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (usageLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                context.tr(usageLabel!),
                key: const ValueKey<String>('full-version-upsell-usage'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey<String>('full-version-upsell-unlock'),
              onPressed: onUnlock,
              child: Text(
                store
                    ? context.tr('解锁完整版')
                    : context.tr('解锁完整版 {price}', <String, Object?>{
                        'price': AppMetadata.fullVersionPrice,
                      }),
              ),
            ),
            TextButton(
              key: const ValueKey<String>('full-version-upsell-dismiss'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('暂不'),
            ),
          ],
        ),
      ),
    );
  }
}
