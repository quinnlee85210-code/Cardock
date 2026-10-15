import 'dart:ui' as ui;

import 'package:account_subscription_manager/core/branding/brand_catalog_loader.dart';
import 'package:account_subscription_manager/core/preferences/appearance_preferences.dart';
import 'package:account_subscription_manager/core/theme/cardock_theme_types.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('八种桌面预览从实际资源包加载并解码', (tester) async {
    await tester.runAsync(() async {
      final assets = (await AssetManifest.loadFromAssetBundle(
        rootBundle,
      )).listAssets().toSet();
      expect(cardockLauncherFamilies, hasLength(8));
      for (final family in cardockLauncherFamilies) {
        final path = family.launcherAssetName;
        expect(assets, contains(path), reason: family.name);
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            expect(frame.image.width, 1024, reason: path);
            expect(frame.image.height, 1024, reason: path);
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    });
  });

  test('v1至v4旧外观偏好迁移后始终引用现存预览资源', () async {
    final assets = (await AssetManifest.loadFromAssetBundle(
      rootBundle,
    )).listAssets().toSet();
    final payloads = <Map<String, Object>>[
      for (final family in ['standard', 'prime', 'vivid']) ...[
        {
          'version': 1,
          'family': family,
          'logoFamily': 'ignored-legacy-logo',
          'brightnessMode': 'light',
        },
        for (final icon in ['standard', 'prime', 'vivid'])
          {
            'version': 2,
            'family': family,
            'desktopIconFamily': icon,
            'brightnessMode': 'dark',
          },
      ],
      for (final family in ['standard', 'prime', 'vivid', 'mono', 'custom'])
        for (final mode in ['followTheme', 'standard', 'prime', 'vivid'])
          {
            'version': 3,
            'family': family,
            'desktopIconMode': mode,
            'brightnessMode': 'system',
          },
      for (final family in CardockThemeFamily.values)
        for (final mode in ['followTheme', 'standard', 'prime', 'vivid'])
          {
            'version': 4,
            'family': family.name,
            'desktopIconMode': mode,
            'brightnessMode': 'dark',
          },
    ];
    for (final payload in payloads) {
      final migrated = AppearancePreferences.tryParse(payload);
      expect(migrated, isNotNull, reason: payload.toString());
      final path = migrated!.resolvedLauncherFamily.launcherAssetName;
      expect(assets, contains(path), reason: payload.toString());
      expect(await rootBundle.load(path), isA<ByteData>());
    }
  });

  test('离线目录中600个动态品牌路径都可从实际资源包读取', () async {
    final assets = (await AssetManifest.loadFromAssetBundle(
      rootBundle,
    )).listAssets().toSet();
    final catalog = await const CardockBrandCatalogLoader().load();
    expect(catalog.entries, hasLength(600));
    final iconAssets = assets
        .where((path) => path.startsWith('assets/brands/v1/icons/'))
        .toSet();
    expect(iconAssets, hasLength(600));
    for (final entry in catalog.entries) {
      expect(iconAssets, contains(entry.assetPath), reason: entry.brandId);
      final data = await rootBundle.load(entry.assetPath);
      expect(data.lengthInBytes, greaterThan(8), reason: entry.assetPath);
      expect(data.buffer.asUint8List(data.offsetInBytes, 8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ], reason: entry.assetPath);
    }
  });

  test('archive附属许可证全文随资源包分发且与锁定原文相同', () async {
    const path = 'assets/licenses/archive-3.6.1-LICENSE-other.md';
    final data = await rootBundle.load(path);
    final digest = await Sha256().hash(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final hex = digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(
      hex,
      'ebe5a199af245d7e3e761673fbf3db341427060407e50713861ab24bb2cb1552',
    );
  });

  test('Tika完整复合许可及NOTICE随资源包分发', () async {
    const checksums = <String, String>{
      'LICENSE':
          '9798f8a331a824364d0507bc2e8ccf58ded9204f6839f48ec4f10556116e40ac',
      'NOTICE':
          'd4fc95518b2d570faa040236106e26bc60510a463566e1e1f6a1b8190bb258e7',
    };
    for (final entry in checksums.entries) {
      final data = await rootBundle.load(
        'assets/licenses/tika-core-3.2.3-${entry.key}.txt',
      );
      final digest = await Sha256().hash(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final actual = digest.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(actual, entry.value, reason: entry.key);
    }
  });

  test('原生转依赖完整LICENSE及NOTICE随资源包分发', () async {
    const checksums = <String, String>{
      'slf4j-api-2.0.17-LICENSE.txt':
          '4e7f90c86ab51278228bce153122f1d8df30149d13ce9ef524c8444a84c32dcc',
      'commons-io-2.20.0-LICENSE.txt':
          'c1d1a38c99c48ccad170890ade6066e2e240bb6ce59861d4eb7f672eddd2a4c6',
      'commons-io-2.20.0-NOTICE.txt':
          'b54b0db6c617273efff79ba193bb01b05eadcddfff55c24063b38b2acef714c3',
    };
    for (final entry in checksums.entries) {
      final data = await rootBundle.load('assets/licenses/${entry.key}');
      final digest = await Sha256().hash(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final actual = digest.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(actual, entry.value, reason: entry.key);
    }
  });
}
