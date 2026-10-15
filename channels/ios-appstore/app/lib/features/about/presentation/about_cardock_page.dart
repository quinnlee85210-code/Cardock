import 'play_privacy_page.dart';
import '../../../core/entitlements/distribution_channel.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

import '../../../core/app_metadata.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../shared/widgets/cardock_ui.dart';

class AboutCardockPage extends StatelessWidget {
  const AboutCardockPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于 Cardock')),
    body: ListView(
      key: const ValueKey<String>('about-cardock-page'),
      padding: const EdgeInsets.fromLTRB(
        CardockLayout.screenHorizontal,
        12,
        CardockLayout.screenHorizontal,
        32,
      ),
      children: [
        CardockSurfaceCard(
          elevated: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                AppMetadata.name,
                translate: false,
                key: const ValueKey<String>('about-application-name'),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('版本 {version}', <String, Object?>{
                  'version': AppMetadata.displayVersion,
                }),
                key: const ValueKey<String>('about-application-version'),
              ),
            ],
          ),
        ),
        if (CardockDistributionConfig.channel ==
            CardockDistributionChannel.googlePlay)
          ListTile(
            key: const ValueKey('play-privacy-entry'),
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(PlayPrivacyPage.title(context), translate: false),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PlayPrivacyPage()),
            ),
          ),
        const SizedBox(height: 14),
        _AboutSection(
          key: ValueKey<String>('about-local-boundary'),
          icon: Icons.phonelink_lock_outlined,
          title: '本地存储与隐私边界',
          body:
              CardockDistributionConfig.channel ==
                  CardockDistributionChannel.development
              ? '账号与订阅数据默认加密保存在本机，不上传云端，也不进行云同步。Cardock 不会申请通讯录、位置、外部存储或媒体读取权限，也不会扫描设备上的其他文件；导入或导出加密备份时，只会通过系统文件选择器处理你当次明确指定的文件。应用所需的 INTERNET 权限仅用于你主动开启“电脑临时录入”后，在自己的手机热点或可信 Wi-Fi 上提供短时局域网连接，不会连接公网、云端或中继，结束会话即停止。Cardock 是一款真正属于你个人的本地工具，数据与使用方式的控制权始终在你手中。'
              : '账号与订阅数据默认加密保存在本机，购买和授权验证不会读取或上传保险库、主密码或备份密码。日常记录保持离线；你主动开启的电脑临时录入仅在可信局域网运行。购买、恢复购买和查询商店价格需要官方商店或官网联网；网站购买链接只携带本安装的公开授权标识。Cardock 不会申请通讯录、位置、外部存储或媒体读取权限，也不会扫描设备上的其他文件。',
        ),
        const SizedBox(height: 12),
        const _AboutSection(
          key: ValueKey<String>('about-encryption-backup'),
          icon: Icons.enhanced_encryption_outlined,
          title: '保险库如何加密',
          body:
              '每个保险库都会生成独立的随机 256 位数据密钥，并使用 AES-256-GCM 加密账号和订阅数据。它不仅隐藏内容，还会校验密文完整性；文件被篡改或损坏时，应用会拒绝把异常内容当作有效数据读取。主密码不会以明文保存，也不直接充当数据密钥。',
        ),
        const SizedBox(height: 12),
        const _AboutSection(
          key: ValueKey<String>('about-password-protection'),
          icon: Icons.password_rounded,
          title: '主密码与密钥保护',
          body:
              '主密码配合每次随机生成的盐，经 Argon2id 内存困难型算法派生密钥，再用于保护保险库的数据密钥。当前参数为 19 MiB 内存、2 次迭代、并行度 1。生物识别只调用系统认证并保护本机快速解锁材料；认证失败时仍需主密码。',
        ),
        const SizedBox(height: 12),
        const _AboutSection(
          key: ValueKey<String>('about-encrypted-backup'),
          icon: Icons.backup_outlined,
          title: '独立加密备份',
          body:
              '.asmbackup 便携备份使用独立备份密码，并继续采用 Argon2id 与 AES-256-GCM 保护。备份文件由你自行离线保管；恢复时不会更改手机当前主密码。安装标识和推广激活码不进入备份，因此完整版权益不会随数据文件迁移到另一台设备。',
        ),
        const SizedBox(height: 12),
        const _AboutSection(
          key: ValueKey<String>('about-licenses'),
          icon: Icons.policy_outlined,
          title: '开源许可与品牌声明',
          body:
              '内置单色品牌识别图形部分来自 Simple Icons（CC0-1.0）。第三方名称与商标归各权利人所有，仅用于识别用户记录的平台，不代表授权、关联、赞助或背书；字母标是 Cardock 生成的非官方占位图形。',
        ),
      ],
    ),
  );
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.cardockTheme.palette;
    return CardockSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardockSemanticIcon(icon: icon, color: palette.primary, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(body, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
