import '../../../core/entitlements/entitlement_service.dart';
import '../../../l10n/localized_material.dart';
import '../../../l10n/context_l10n.dart';
import 'website_authorization_dialog.dart';
import 'website_purchase_access.dart';

/// Local help for old navigation routes. Opening the page never opens the network.
class WebsiteOrdersPage extends StatelessWidget {
  const WebsiteOrdersPage({
    required this.controller,
    required this.access,
    super.key,
  });
  final ProductEntitlementController controller;
  final WebsitePurchaseAccess access;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的官网订单')),
    body: ListenableBuilder(
      listenable: access,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '在浏览器中查看付款进度。核验通过后，点击网页“在Cardock中激活”，即可完成激活；Cardock本身不联网。',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: !access.allowed
                ? null
                : () async {
                    final result = await controller.openWebsiteOrders(
                      access.lease(),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.tr(result.message))),
                      );
                    }
                  },
            icon: const Icon(Icons.open_in_new),
            label: const Text('在浏览器中打开官网订单'),
          ),
          TextButton(
            onPressed: !access.allowed
                ? null
                : () => showWebsiteAuthorizationDialog(context, controller),
            child: const Text('手动粘贴网站授权码'),
          ),
        ],
      ),
    ),
  );
}
