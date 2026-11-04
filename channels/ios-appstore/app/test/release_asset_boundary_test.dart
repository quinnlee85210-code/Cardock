import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:account_subscription_manager/core/app_metadata.dart';
import 'package:account_subscription_manager/l10n/app_localizations.dart';

void main() {
  test('release version display matches the package version and build', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final packageVersion = RegExp(
      r'^version: (.+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!.trim();
    expect(AppMetadata.version, packageVersion);
    expect(AppMetadata.displayVersion, '1.0.1');
    expect(packageVersion.split('+').last, '92');
  });

  test(
    'localized app names match iOS launcher names and preserve the Cardock brand',
    () {
      expect(AppMetadata.name, 'Cardock账号密码订阅管理器');
      for (final locale in AppLocalizations.supportedLocales) {
        final localizations = AppLocalizations(locale);
        final directory = switch (locale.languageCode) {
          'zh' => 'zh-Hans',
          'ja' => 'ja',
          _ => 'en',
        };
        final strings = File(
          'ios/Runner/$directory.lproj/InfoPlist.strings',
        ).readAsStringSync();
        expect(
          strings,
          contains('"CFBundleDisplayName" = "${localizations.appTitle}";'),
        );
        expect(localizations.appTitle, startsWith('Cardock'));
        expect(localizations.appTitle.runes.length, lessThanOrEqualTo(30));
        final title = localizations.translate('Cardock 完整版');
        expect(title, contains('Cardock'));
        if (locale.languageCode != 'zh') {
          expect(localizations.hasTranslation('Cardock 完整版'), isTrue);
        }
        expect(localizations.translate('关于 Cardock'), contains('Cardock'));
      }
    },
  );

  test('pubspec只打包三项临时网页运行资源', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final temporaryWebAssets = pubspec
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('- assets/temporary_web/'))
        .toList(growable: false);

    expect(temporaryWebAssets, const <String>[
      '- assets/temporary_web/index.html',
      '- assets/temporary_web/app.css',
      '- assets/temporary_web/app.js',
    ]);
    expect(pubspec, isNot(contains('- assets/temporary_web/\n')));
    final physicalAssets = await Directory('assets/temporary_web')
        .list(followLinks: false)
        .where((entry) => entry is File)
        .map((entry) => entry.uri.pathSegments.last)
        .toList();
    physicalAssets.sort();
    expect(physicalAssets, <String>['app.css', 'app.js', 'index.html']);
    expect(
      physicalAssets.where(
        (name) => name.endsWith('.map') || name.endsWith('.deps'),
      ),
      isEmpty,
    );
  });

  test('主题 production asset 仅包含 Paper Archive 纸张纹理', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final themeAssets = pubspec
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('- assets/theme/'))
        .toList(growable: false);

    expect(themeAssets, const <String>['- assets/theme/paper_grain_128.webp']);
    final texture = File('assets/theme/paper_grain_128.webp');
    expect(await texture.exists(), isTrue);
    expect(await texture.length(), 19662);
    expect(pubspec, isNot(contains('reference_mode_contact_sheets')));
    expect(pubspec, isNot(contains('original_color_references')));
    expect(pubspec, isNot(contains('cardock-signature-v7-themes')));
  });
  test('发布资产不包含交付包、上游源包或审计目录', () async {
    final pubspec = await File('pubspec.yaml').readAsString();

    expect(pubspec, contains('- assets/brands/v1/'));
    expect(pubspec, contains('- assets/brands/v1/icons/'));
    expect(pubspec, isNot(contains('_handoff')));
    expect(pubspec, isNot(contains('vendor/')));
    expect(pubspec, isNot(contains('manifests/')));
    expect(pubspec, isNot(contains('assets/donate')));
    expect(pubspec, contains('version: 1.0.1+92'));
    expect(pubspec, isNot(contains('golden_screens')));
  });

  test('关于页版本与离线品牌免责声明同步到发布候选', () async {
    final metadataSource = await File(
      'lib/core/app_metadata.dart',
    ).readAsString();
    final aboutSource = await File(
      'lib/features/about/presentation/about_cardock_page.dart',
    ).readAsString();

    expect(metadataSource, contains("version = '1.0.1+92'"));
    expect(aboutSource, contains('关于 Cardock'));
    expect(aboutSource, contains('随机 256 位数据密钥'));
    expect(aboutSource, contains('AES-256-GCM'));
    expect(aboutSource, contains('安装标识和推广激活码不进入备份'));
    expect(aboutSource, contains('Simple Icons（CC0-1.0）'));
    expect(aboutSource, contains('不代表授权、关联、赞助或背书'));
    expect(aboutSource, contains('不会申请通讯录、位置、外部存储或媒体读取权限'));
    expect(aboutSource, contains('不会扫描设备上的其他文件'));
    expect(aboutSource, contains('INTERNET 权限仅用于'));
    expect(aboutSource, contains('不会连接公网、云端或中继'));
  });

  test('iOS构建版本沿用Flutter发布版本变量', () async {
    final info = await File('ios/Runner/Info.plist').readAsString();
    final project = await File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsString();
    expect(info, contains(r'$(FLUTTER_BUILD_NAME)'));
    expect(info, contains(r'$(FLUTTER_BUILD_NUMBER)'));
    expect(
      project,
      contains(r'CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)"'),
    );
  });

  test('产品正式界面不包含开发状态或虚假操作入口', () async {
    final sources = <String>[
      await File(
        'lib/features/settings/presentation/settings_page.dart',
      ).readAsString(),
      await File(
        'lib/features/product/presentation/full_version_page.dart',
      ).readAsString(),
      await File(
        'lib/features/about/presentation/about_cardock_page.dart',
      ).readAsString(),
    ].join('\n');

    expect(sources, isNot(contains('产品账号')));
    expect(sources, isNot(contains('暂不开发')));
    expect(sources, isNot(contains('模拟商店已完成')));
    expect(sources, isNot(contains('正式 IAP 尚未接入')));
    expect(sources, isNot(contains('登录账号')));
    expect(sources, isNot(contains('授权码')));
    expect(sources, isNot(contains('检查更新')));
  });

  test('开发者来信不包含赞赏收款能力且收款码资产已退出发布边界', () async {
    final source = await File(
      'lib/features/about/presentation/developer_note_page.dart',
    ).readAsString();
    expect(source, isNot(contains('http://')));
    expect(source, isNot(contains('https://')));
    expect(source, isNot(contains('url_launcher')));
    expect(source, isNot(contains('HttpClient')));
    expect(source, isNot(contains('赞赏')));
    expect(source, isNot(contains('捐赠')));
    expect(source, isNot(contains('收款码')));
    expect(source, isNot(contains('¥6')));
    expect(source, isNot(contains('¥18')));
    expect(source, isNot(contains('¥66')));
    expect(await Directory('assets/donate').exists(), isFalse);
    expect(
      await File('lib/core/platform/donation_image_saver.dart').exists(),
      isFalse,
    );
    expect(
      await File(
        'lib/features/about/presentation/support_developer_page.dart',
      ).exists(),
      isFalse,
    );
  });

  test('推广激活仅内置公钥且本地私钥与签发记录受Git忽略', () async {
    final config = await File(
      'lib/core/entitlements/promo_activation_config.dart',
    ).readAsString();
    final gitignore = await File('../.gitignore').readAsString();
    final toolSource = await File(
      'tool/promo_signer/promo_signer.dart',
    ).readAsString();
    final batchSource = await File(
      'tool/promo_signer/promo_sign.bat',
    ).readAsString();

    expect(config, contains('publicKeyBytes'));
    expect(config, isNot(contains('privateSeed')));
    expect(gitignore, contains('**/promo_private.key'));
    expect(gitignore, contains('**/issued_codes.csv'));
    expect(toolSource, isNot(contains('HttpClient')));
    expect(toolSource, isNot(contains('http://')));
    expect(toolSource, isNot(contains('https://')));
    expect(batchSource, contains('promo_signer.dart interactive'));
    expect(batchSource, isNot(contains('keygen')));
    expect(batchSource, isNot(contains('http://')));
    expect(batchSource, isNot(contains('https://')));
  });

  test('推广激活与开发者来信实现不新增任何网络请求', () async {
    final sources = <String>[
      'lib/core/entitlements/promo_activation_codec.dart',
      'lib/core/entitlements/promo_activation_config.dart',
      'lib/core/entitlements/promo_activation_service.dart',
      'lib/core/entitlements/promo_activation_store.dart',
      'lib/features/product/presentation/promo_activation_section.dart',
      'lib/features/about/presentation/developer_note_page.dart',
      'tool/promo_signer/promo_signer.dart',
      'tool/promo_signer/promo_sign.bat',
    ];
    final joined = (await Future.wait(
      sources.map((path) => File(path).readAsString()),
    )).join('\n');

    expect(joined, isNot(contains('HttpClient')));
    expect(joined, isNot(contains('Socket.connect')));
    expect(joined, isNot(contains('http://')));
    expect(joined, isNot(contains('https://')));
    expect(joined, isNot(contains('url_launcher')));
  });
}
