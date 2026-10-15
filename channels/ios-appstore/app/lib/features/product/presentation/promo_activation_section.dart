import 'package:flutter/services.dart';

import '../../../core/entitlements/entitlement_service.dart';
import '../../../core/entitlements/promo_activation_service.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../shared/widgets/cardock_ui.dart';

class PromoActivationSection extends StatefulWidget {
  const PromoActivationSection({
    required this.promoController,
    required this.entitlementController,
    this.enabled = true,
    super.key,
  });

  final PromoActivationController promoController;
  final ProductEntitlementController entitlementController;
  final bool enabled;

  @override
  State<PromoActivationSection> createState() => _PromoActivationSectionState();
}

class _PromoActivationSectionState extends State<PromoActivationSection> {
  final TextEditingController _activationCodeController =
      TextEditingController();
  bool _expanded = false;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(text))));
  }

  Future<void> _copyRequestCode(String requestCode) async {
    await Clipboard.setData(ClipboardData(text: requestCode));
    _message('本机申请码已复制。');
  }

  Future<void> _activate() async {
    final controller = widget.promoController;
    if (!widget.enabled || controller.isBusy) return;
    final result = await controller.activate(_activationCodeController.text);
    if (result.succeeded) _activationCodeController.clear();
    _message(result.message);
  }

  @override
  void dispose() {
    _activationCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.promoController,
    builder: (context, child) => ListenableBuilder(
      listenable: widget.entitlementController,
      builder: (context, child) {
        final promoController = widget.promoController;
        final hasStorePurchase = widget.entitlementController.hasStorePurchase;
        final promoActivated = promoController.isActivated;
        final canActivate =
            widget.enabled &&
            !promoController.isBusy &&
            promoController.requestCode != null;
        return Column(
          key: const ValueKey<String>('promo-activation-section'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '其他激活方式',
              key: const ValueKey<String>('other-activation-methods-title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            CardockSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasStorePurchase)
                    const _ActivationState(
                      key: ValueKey<String>('promo-store-purchased-state'),
                      icon: Icons.verified_rounded,
                      text: '已通过购买解锁完整版',
                    )
                  else if (promoActivated)
                    const _ActivationState(
                      key: ValueKey<String>('promo-activated-state'),
                      icon: Icons.verified_user_rounded,
                      text: '已通过推广激活解锁完整版',
                    )
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey<String>(
                          'promo-activation-disclosure',
                        ),
                        onPressed: widget.enabled
                            ? () => setState(() => _expanded = !_expanded)
                            : null,
                        icon: Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        label: const Text('已获得推广激活码'),
                      ),
                    ),
                    if (_expanded) ...[
                      const SizedBox(height: 14),
                      const Text(
                        '如果你已获得开发者签发的推广激活码，可在此使用本机申请码完成离线激活。',
                        key: ValueKey<String>('promo-activation-explanation'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '本机申请码',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: SelectableText(
                              promoController.requestCode ??
                                  context.tr(
                                    promoController.isInitialized
                                        ? '暂不可用'
                                        : '准备中…',
                                  ),
                              key: const ValueKey<String>('promo-request-code'),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontFamily: 'monospace',
                                    letterSpacing: 2,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            key: const ValueKey<String>(
                              'copy-promo-request-code',
                            ),
                            onPressed: promoController.requestCode == null
                                ? null
                                : () => _copyRequestCode(
                                    promoController.requestCode!,
                                  ),
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('复制'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const ValueKey<String>(
                          'promo-activation-code-field',
                        ),
                        controller: _activationCodeController,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        ],
                        decoration: InputDecoration(
                          labelText: context.tr('激活码'),
                          hintText: context.tr('粘贴开发者签发的激活码'),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey<String>(
                            'activate-promo-code-button',
                          ),
                          onPressed: canActivate ? _activate : null,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('激活完整版'),
                        ),
                      ),
                    ],
                  ],
                  if (promoController.isBusy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(
                      key: ValueKey<String>('promo-activation-progress'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ActivationState extends StatelessWidget {
  const _ActivationState({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Row(
      children: [
        Icon(icon, color: palette.statusNormal),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}
