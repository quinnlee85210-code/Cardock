import 'package:flutter/services.dart' show Clipboard, MaxLengthEnforcement;
import '../../../l10n/localized_material.dart';
import '../../../l10n/context_l10n.dart';
import '../../../core/entitlements/entitlement_service.dart';
import '../../../core/entitlements/website_offline_codec.dart';
import 'website_purchase_access.dart';

Future<void> showWebsiteAuthorizationDialog(
  BuildContext context,
  ProductEntitlementController controller,
) async {
  final access = WebsitePurchaseScope.maybeOf(context);
  final lease = access?.lease() ?? () => context.mounted;
  final input = TextEditingController();
  String? error;
  var pasting = false;
  final credential = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, update) {
        void submit() {
          if (!lease()) return;
          final text = input.text.trim();
          if (text.isEmpty) {
            update(() => error = '请先复制官网的完整授权，再点击粘贴。');
            return;
          }
          if (text.length > WebsiteOfflineCodec.maxBytes) {
            update(() => error = '授权内容过长，请重新复制完整授权。');
            return;
          }
          Navigator.of(dialogContext).pop(text);
        }

        Future<void> paste({bool activate = false}) async {
          if (pasting || !lease()) return;
          if (input.text.isNotEmpty) {
            update(() => error = '请先清空输入，再粘贴新的完整授权。');
            return;
          }
          update(() {
            pasting = true;
            error = null;
          });
          try {
            final value = await Clipboard.getData(Clipboard.kTextPlain);
            if (!dialogContext.mounted || !lease()) return;
            if (input.text.isNotEmpty) {
              update(() => error = '输入内容已改变，未覆盖。请先清空后再粘贴。');
            } else if (value?.text?.trim().isNotEmpty != true) {
              update(() => error = '剪贴板没有可用文字，请先点击官网“复制完整授权”。');
            } else if (value!.text!.length > WebsiteOfflineCodec.maxBytes) {
              update(() => error = '剪贴板内容过长，请重新复制官网完整授权。');
            } else {
              update(() {
                input.text = value.text!;
                error = null;
              });
              if (activate) submit();
            }
          } on Object {
            if (dialogContext.mounted) {
              update(() => error = '无法读取剪贴板，请允许本次粘贴，或在输入框中手动粘贴。');
            }
          } finally {
            if (dialogContext.mounted) update(() => pasting = false);
          }
        }

        return AlertDialog(
          title: const Text('手动粘贴网站授权码'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('备用方式：复制官网准备好的完整授权，在此离线验证并激活。旧版独立授权码仍可使用。'),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('website-authorization-input'),
                  controller: input,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: WebsiteOfflineCodec.maxBytes,
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => update(() => error = null),
                  decoration: InputDecoration(
                    labelText: context.tr('网站授权码'),
                    hintText: context.tr('粘贴从官网订单页复制的完整授权'),
                    errorText: error == null ? null : context.tr(error!),
                    errorMaxLines: 4,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('paste-website-authorization'),
                      onPressed: pasting ? null : paste,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('粘贴'),
                    ),
                    TextButton(
                      key: const ValueKey('clear-website-authorization'),
                      onPressed: pasting
                          ? null
                          : () => update(() {
                              input.clear();
                              error = null;
                            }),
                      child: const Text('清空'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop('__website_recovery__'),
              child: const Text('恢复已有购买'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('activate-pasted-authorization'),
              onPressed: pasting
                  ? null
                  : () => input.text.trim().isEmpty
                        ? paste(activate: true)
                        : submit(),
              child: Text(input.text.trim().isEmpty ? '粘贴并激活' : '验证并激活'),
            ),
          ],
        );
      },
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  input.dispose();
  if (credential == null ||
      credential.isEmpty ||
      !context.mounted ||
      !lease()) {
    return;
  }
  final result = credential == '__website_recovery__'
      ? await controller.openWebsiteRecovery(authorized: lease)
      : await controller.importWebsiteAuthorization(
          credential,
          authorized: lease,
        );
  if (context.mounted && lease()) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr(result.message))));
  }
}
