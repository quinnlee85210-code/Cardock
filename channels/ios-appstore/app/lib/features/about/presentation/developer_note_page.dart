import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cardock_tokens.dart';
import '../../../shared/widgets/cardock_ui.dart';
import 'about_cardock_page.dart';

const String _developerWechatId = 'kawucardock';
const String _developerRecommendationCopy =
    'Cardock：一款本地保存账号与订阅记录的工具，9.9 元一次买断，无广告、无订阅。';

const List<String> _developerLetterParagraphs = <String>[
  '账号、密码和订阅记录，都是非常私人的信息。',
  '我做 Cardock，不是想再建立一个要求用户注册、同步和交出数据的平台，而是想做一件安静、可靠、真正留在你设备里的工具。',
  'Cardock 是我完成的第一款正式 App。它不是一个做完就放下的试验项目，也不会因为使用者暂时不多就被随意搁置。',
  '无论最终有多少人使用，我都会继续认真维护它，修复发现的问题，跟进必要的系统适配，并在不破坏本地、简洁和可靠这些原则的前提下，把它一点点做好。',
];

const List<_DeveloperPrinciple> _developerPrinciples = <_DeveloperPrinciple>[
  _DeveloperPrinciple(
    number: '01',
    title: '认真维护',
    body: '不会因为用户暂时不多，就停止修复已知问题和必要的系统适配。',
  ),
  _DeveloperPrinciple(
    number: '02',
    title: '保持克制',
    body: '只加入真正有价值的改进，不为了堆积功能让 Cardock 变得臃肿复杂。',
  ),
  _DeveloperPrinciple(
    number: '03',
    title: '尊重购买',
    body: '9.9 元一次买断，不设置订阅、自动续费、广告或基于用户数据的商业追踪。',
  ),
];

/// A restrained developer letter that contains no entitlement or vault data.
class DeveloperNotePage extends StatefulWidget {
  const DeveloperNotePage({super.key});

  @override
  State<DeveloperNotePage> createState() => _DeveloperNotePageState();
}

class _DeveloperNotePageState extends State<DeveloperNotePage> {
  void _showMessage(String source) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(context.tr(source), translate: false)),
      );
  }

  Future<void> _copyText({
    required String text,
    required String successMessage,
  }) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      _showMessage(successMessage);
    } on Object {
      _showMessage('复制失败，请稍后重试');
    }
  }

  void _openPrivacyAndSecurity() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const AboutCardockPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '开发者的话',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        key: const ValueKey<String>('developer-note-page'),
        padding: const EdgeInsets.fromLTRB(
          CardockLayout.screenHorizontal,
          12,
          CardockLayout.screenHorizontal,
          40,
        ),
        children: <Widget>[
          const _DeveloperNoteHero(),
          const SizedBox(height: CardockLayout.cardGap),
          const _DeveloperLetterCard(),
          const SizedBox(height: CardockLayout.cardGap),
          const _DeveloperPrinciplesCard(),
          const SizedBox(height: CardockLayout.cardGap),
          _PurchaseSupportCard(
            onCopyRecommendation: () => _copyText(
              text: _developerRecommendationCopy,
              successMessage: '推荐文案已复制',
            ),
          ),
          const SizedBox(height: CardockLayout.cardGap),
          _DeveloperContactCard(
            onCopyWechat: () =>
                _copyText(text: _developerWechatId, successMessage: '微信号已复制'),
            onOpenPrivacyAndSecurity: _openPrivacyAndSecurity,
          ),
          const SizedBox(height: CardockLayout.moduleGapLarge),
          const _DeveloperSignature(),
        ],
      ),
    );
  }
}

class _DeveloperNoteHero extends StatelessWidget {
  const _DeveloperNoteHero();

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final showWordmark =
        MediaQuery.sizeOf(context).width >= 360 && textScale <= 1.3;
    return CardockSurfaceCard(
      key: const ValueKey<String>('developer-note-hero'),
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CardockBrandMark(
            showWordmark: showWordmark,
            iconSize: showWordmark ? 36 : 42,
          ),
          const SizedBox(height: 18),
          Text(
            '谢谢你选择 Cardock',
            key: const ValueKey<String>('developer-note-hero-title'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            '这是我完成的第一款正式 App，\n也是我准备认真维护下去的一款 App。',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 16),
          const Wrap(
            key: ValueKey<String>('developer-note-tags'),
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _DeveloperTag(label: '第一款作品'),
              _DeveloperTag(label: '9.9 元一次买断'),
              _DeveloperTag(label: '长期维护'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeveloperTag extends StatelessWidget {
  const _DeveloperTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(CardockRadius.pill),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: palette.textSecondary),
        ),
      ),
    );
  }
}

class _DeveloperLetterCard extends StatelessWidget {
  const _DeveloperLetterCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return CardockSurfaceCard(
      key: const ValueKey<String>('developer-note-letter'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DeveloperSectionHeader(
            icon: Icons.edit_note_outlined,
            title: '为什么做 Cardock',
            color: palette.primary,
          ),
          const SizedBox(height: 12),
          for (
            var index = 0;
            index < _developerLetterParagraphs.length;
            index += 1
          ) ...<Widget>[
            Text(
              _developerLetterParagraphs[index],
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.7),
            ),
            if (index != _developerLetterParagraphs.length - 1)
              const SizedBox(height: 13),
          ],
        ],
      ),
    );
  }
}

class _DeveloperPrinciplesCard extends StatelessWidget {
  const _DeveloperPrinciplesCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return CardockSurfaceCard(
      key: const ValueKey<String>('developer-note-principles'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DeveloperSectionHeader(
            icon: Icons.fact_check_outlined,
            title: '我会坚持的三件事',
            color: palette.primary,
          ),
          const SizedBox(height: 8),
          for (
            var index = 0;
            index < _developerPrinciples.length;
            index += 1
          ) ...<Widget>[
            _DeveloperPrincipleRow(principle: _developerPrinciples[index]),
            if (index != _developerPrinciples.length - 1)
              const Divider(height: 28),
          ],
        ],
      ),
    );
  }
}

class _DeveloperPrincipleRow extends StatelessWidget {
  const _DeveloperPrincipleRow({required this.principle});

  final _DeveloperPrinciple principle;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48),
            child: Text(
              principle.number,
              translate: false,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.primary,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  principle.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 5),
                Text(
                  principle.body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseSupportCard extends StatelessWidget {
  const _PurchaseSupportCard({required this.onCopyRecommendation});

  final VoidCallback onCopyRecommendation;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return CardockSurfaceCard(
      key: const ValueKey<String>('developer-note-purchase'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DeveloperSectionHeader(
            icon: Icons.verified_outlined,
            title: '一次购买，就是最直接的支持',
            color: palette.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Cardock 采用 9.9 元一次买断。完成购买之后，不需要再额外付费。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            '对 Cardock 最有帮助的，是告诉我哪里不好用、提出真实的改进建议，或者把它推荐给同样重视本地与隐私的人。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            '是否反馈或分享，都不会影响你获得的功能，也不会影响 Cardock 的后续维护。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const ValueKey<String>('developer-note-copy-recommendation'),
              onPressed: onCopyRecommendation,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.content_copy_outlined),
                  SizedBox(width: 8),
                  Expanded(child: Text('复制推荐文案', textAlign: TextAlign.center)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperContactCard extends StatelessWidget {
  const _DeveloperContactCard({
    required this.onCopyWechat,
    required this.onOpenPrivacyAndSecurity,
  });

  final VoidCallback onCopyWechat;
  final VoidCallback onOpenPrivacyAndSecurity;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return CardockSurfaceCard(
      key: const ValueKey<String>('developer-note-contact'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DeveloperSectionHeader(
            icon: Icons.chat_bubble_outline,
            title: '联系与反馈',
            color: palette.primary,
          ),
          const SizedBox(height: 12),
          Text(
            '遇到问题或有改进建议，可以通过微信联系开发者。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Text('微信号', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(CardockRadius.control),
              border: Border.all(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SelectableText(
                      _developerWechatId,
                      key: const ValueKey<String>('developer-note-wechat-id'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('developer-note-copy-wechat'),
                    tooltip: context.tr('复制微信号'),
                    onPressed: onCopyWechat,
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '用于问题反馈、故障说明和改进建议。添加时请备注“Cardock 反馈”。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(CardockRadius.control),
              border: Border.all(color: palette.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.shield_outlined, color: palette.statusInformation),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '反馈时请勿发送主密码、备份密码、密码恢复答案、完整账号密码，或包含敏感信息的截图。开发者不会通过微信向你索取这些信息。',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const ValueKey<String>('developer-note-open-about'),
              onPressed: onOpenPrivacyAndSecurity,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.privacy_tip_outlined),
                  SizedBox(width: 8),
                  Expanded(child: Text('隐私与安全说明', textAlign: TextAlign.center)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperSectionHeader extends StatelessWidget {
  const _DeveloperSectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CardockSemanticIcon(icon: icon, color: color, size: 36),
        const SizedBox(width: 11),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

class _DeveloperSignature extends StatelessWidget {
  const _DeveloperSignature();

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return Padding(
      key: const ValueKey<String>('developer-note-signature'),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '谢谢你愿意使用 Cardock。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text('我会认真把它维护下去。', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          Text(
            '—— Cardock 开发者',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperPrinciple {
  const _DeveloperPrinciple({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;
}
