import '../../../l10n/localized_material.dart';
import '../../../l10n/context_l10n.dart';
import '../../../core/entitlements/entitlement_service.dart';
import '../../../core/entitlements/website_license_verifier.dart';

Future<void> showWebsiteAuthorizationDialog(
  BuildContext context,
  ProductEntitlementController controller,
) async {
  final input = TextEditingController();
  final credential = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('导入本安装授权'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('粘贴官网付款后提供的授权文本。换机后请通过官网重新申请本安装授权。'),
            const SizedBox(height: 12),
            TextField(
              controller: input,
              minLines: 3,
              maxLines: 6,
              maxLength: WebsiteLicenseVerifier.maxCredentialCharacters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: context.tr('授权文本')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(input.text.trim()),
          child: const Text('验证授权'),
        ),
      ],
    ),
  );
  // The dialog's exit animation may still reference its controller.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  input.dispose();
  if (credential == null || credential.isEmpty || !context.mounted) return;
  final result = await controller.importWebsiteAuthorization(credential);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr(result.message))));
  }
}
