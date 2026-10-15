import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android包名、完整品牌名、alias与权限边界保持稳定', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    final gradle = await File('android/app/build.gradle.kts').readAsString();
    final strings = await File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsString();

    expect(
      gradle,
      contains('namespace = "com.localaccount.account_subscription_manager"'),
    );
    expect(
      gradle,
      contains(
        'applicationId = "com.localaccount.account_subscription_manager"',
      ),
    );
    expect(strings, contains('<string name="app_name">Cardock</string>'));
    expect(manifest, contains('android:label="@string/app_name"'));
    expect(
      manifest,
      contains('android:icon="@mipmap/ic_launcher_ceramic_blue"'),
    );
    expect(
      manifest,
      contains('android:roundIcon="@mipmap/ic_launcher_ceramic_blue_round"'),
    );
    expect(manifest, contains('android:allowBackup="false"'));

    final mainActivity = RegExp(
      r'<activity\s+[^>]*android:name="\.MainActivity"[^>]*>'
      r'[\s\S]*?</activity>',
    ).firstMatch(manifest)?.group(0);
    expect(mainActivity, isNotNull);
    expect(mainActivity, isNot(contains('android.intent.action.MAIN')));
    expect(mainActivity, isNot(contains('android.intent.category.LAUNCHER')));

    final aliasBlocks = RegExp(
      r'<activity-alias[\s\S]*?</activity-alias>',
    ).allMatches(manifest).map((match) => match.group(0)!).toList();
    expect(aliasBlocks, hasLength(11));
    expect(
      RegExp('android.intent.action.MAIN').allMatches(manifest),
      hasLength(11),
    );
    expect(
      RegExp('android.intent.category.LAUNCHER').allMatches(manifest),
      hasLength(11),
    );
    const aliases = <String, ({String icon, bool enabled})>{
      'CeramicBlueAlias': (icon: 'ceramic_blue', enabled: false),
      'SakuraMistAlias': (icon: 'sakura_mist', enabled: false),
      'PaperArchiveAlias': (icon: 'paper_archive', enabled: true),
      'LilacMoonAlias': (icon: 'lilac_moon', enabled: false),
      'GlacierBlueAlias': (icon: 'glacier_blue', enabled: false),
      'MistCoralAlias': (icon: 'mist_coral', enabled: false),
      'NeonZeroAlias': (icon: 'neon_zero', enabled: false),
      'ObsidianGoldAlias': (icon: 'obsidian_gold', enabled: false),
      'StandardAlias': (icon: 'standard', enabled: false),
      'PrimeAlias': (icon: 'prime', enabled: false),
      'VividAlias': (icon: 'vivid', enabled: false),
    };
    for (final entry in aliases.entries) {
      final block = aliasBlocks.singleWhere(
        (candidate) => candidate.contains('.launcher.${entry.key}'),
      );
      expect(
        block,
        contains(
          'android:targetActivity="com.localaccount.'
          'account_subscription_manager.MainActivity"',
        ),
      );
      expect(block, contains('android:exported="true"'));
      expect(block, contains('android:label="@string/app_name"'));
      expect(block, contains('android:enabled="${entry.value.enabled}"'));
      expect(
        block,
        contains('android:icon="@mipmap/ic_launcher_${entry.value.icon}"'),
      );
      expect(
        block,
        contains(
          'android:roundIcon="@mipmap/'
          'ic_launcher_${entry.value.icon}_round"',
        ),
      );
    }

    final permissions = RegExp(
      r'<uses-permission\s+android:name="([^"]+)"\s*/>',
    ).allMatches(manifest).map((match) => match.group(1)).toSet();
    expect(permissions, <String?>{
      'android.permission.USE_BIOMETRIC',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.RECEIVE_BOOT_COMPLETED',
      'android.permission.SCHEDULE_EXACT_ALARM',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
      'android.permission.WAKE_LOCK',
      'android.permission.INTERNET',
    });
    expect(
      manifest,
      contains(
        'User-started trusted LAN input and explicit commercial purchase/license requests.',
      ),
    );
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(manifest, isNot(contains('USE_EXACT_ALARM')));
  });

  test('八套Adaptive、themed、legacy与round桌面图标资源完整', () async {
    const legacySizes = <String, int>{
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    const foregroundSizes = <String, int>{
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };
    const launcherFamilies = <String>[
      'ceramic_blue',
      'sakura_mist',
      'paper_archive',
      'lilac_moon',
      'glacier_blue',
      'mist_coral',
      'neon_zero',
      'obsidian_gold',
    ];
    for (final family in launcherFamilies) {
      for (final suffix in <String>['', '_round']) {
        final adaptive = File(
          'android/app/src/main/res/mipmap-anydpi-v26/'
          'ic_launcher_$family$suffix.xml',
        );
        final themed = File(
          'android/app/src/main/res/mipmap-anydpi-v33/'
          'ic_launcher_$family$suffix.xml',
        );
        expect(await adaptive.exists(), isTrue, reason: adaptive.path);
        expect(await themed.exists(), isTrue, reason: themed.path);
        final adaptiveContents = await adaptive.readAsString();
        final themedContents = await themed.readAsString();
        for (final contents in <String>[adaptiveContents, themedContents]) {
          expect(contents, contains('<adaptive-icon'));
          expect(
            contents,
            contains('@drawable/ic_launcher_${family}_background'),
          );
          expect(
            contents,
            contains('@drawable/ic_launcher_${family}_foreground'),
          );
        }
        expect(themedContents, contains('@drawable/ic_launcher_monochrome'));
        expect(themedContents, isNot(contains('ic_launcher_monochrome_c')));
      }

      for (final entry in legacySizes.entries) {
        for (final suffix in <String>['', '_round']) {
          final file = File(
            'android/app/src/main/res/mipmap-${entry.key}/'
            'ic_launcher_$family$suffix.png',
          );
          expect(await file.exists(), isTrue, reason: file.path);
          final dimensions = await _readPngDimensions(file);
          expect(dimensions.width, entry.value, reason: file.path);
          expect(dimensions.height, entry.value, reason: file.path);
        }

        final legacy = await File(
          'android/app/src/main/res/mipmap-${entry.key}/'
          'ic_launcher_$family.png',
        ).readAsBytes();
        final round = await File(
          'android/app/src/main/res/mipmap-${entry.key}/'
          'ic_launcher_${family}_round.png',
        ).readAsBytes();
        expect(
          round,
          isNot(orderedEquals(legacy)),
          reason: '$family ${entry.key} 的 round 资源不得复用普通 legacy 图',
        );
      }

      for (final entry in foregroundSizes.entries) {
        final file = File(
          'android/app/src/main/res/drawable-${entry.key}/'
          'ic_launcher_${family}_foreground.png',
        );
        expect(await file.exists(), isTrue, reason: file.path);
        final dimensions = await _readPngDimensions(file);
        expect(dimensions.width, entry.value, reason: file.path);
        expect(dimensions.height, entry.value, reason: file.path);
        final bounds = await _readAlphaBounds(file);
        expect(bounds.edgeHasAlpha, isFalse, reason: file.path);
        expect(
          bounds.maxRatio,
          lessThanOrEqualTo(0.62),
          reason: '${file.path} alpha bbox=${bounds.maxRatio}',
        );
      }
    }

    final launcherPreviewHashes = <String>{};
    for (final family in launcherFamilies) {
      final preview = File('assets/branding/cardock_launcher_$family.png');
      expect(await preview.exists(), isTrue, reason: preview.path);
      expect(await _readPngDimensions(preview), (
        width: 1024,
        height: 1024,
      ), reason: preview.path);
      launcherPreviewHashes.add(await _sha256Hex(preview));
    }
    expect(launcherPreviewHashes, hasLength(8));

    final monochrome = await File(
      'android/app/src/main/res/drawable/ic_launcher_monochrome.xml',
    ).readAsString();
    expect(monochrome, contains('M34,33 V59'));
    expect(monochrome, contains('M43,25 H59 L67,33'));
    expect(monochrome, contains('M54,40 L61,44 L54,48 L47,44'));
    expect(monochrome, contains('M47,49 L54,53 L61,49'));
    expect(monochrome, isNot(contains('M39,18h30')));

    const backgrounds = <String, String>{
      'ceramic_blue': '#E7E7E7',
      'sakura_mist': '#FDE8EC',
      'paper_archive': '#F3E8D3',
      'lilac_moon': '#F4F0F7',
      'glacier_blue': '#D7E7F3',
      'mist_coral': '#DCEAE6',
      'neon_zero': '#000000',
      'obsidian_gold': '#06090E',
    };
    for (final entry in backgrounds.entries) {
      final contents = await File(
        'android/app/src/main/res/drawable/'
        'ic_launcher_${entry.key}_background.xml',
      ).readAsString();
      expect(contents, contains('<solid android:color="${entry.value}" />'));
      expect(contents, isNot(contains('<gradient')));
    }

    for (final density in legacySizes.keys) {
      final generic = File(
        'android/app/src/main/res/mipmap-$density/ic_launcher.png',
      );
      expect(await generic.exists(), isTrue, reason: generic.path);
    }

    const splashHashes = <String, String>{
      'android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png':
          '3CA5258AAF175358F59ECEEF83AADF3F10F59BAC21556BE8FB33B7974D70D16F',
      'android/app/src/main/res/drawable-night-nodpi/'
              'ic_launcher_foreground.png':
          '3CA5258AAF175358F59ECEEF83AADF3F10F59BAC21556BE8FB33B7974D70D16F',
    };
    for (final entry in splashHashes.entries) {
      final file = File(entry.key);
      expect(await file.exists(), isTrue, reason: file.path);
      final dimensions = await _readPngDimensions(file);
      expect(dimensions, (width: 1024, height: 1024), reason: file.path);
      expect(await _sha256Hex(file), entry.value, reason: file.path);
    }
  });

  test('Android 12浅深色启动主题引用Cardock资源且仅使用平台属性', () async {
    for (final path in <String>[
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final file = File(path);
      expect(await file.exists(), isTrue, reason: path);
      final contents = await file.readAsString();
      expect(
        contents,
        contains('parent="Theme.AppCompat.DayNight.NoActionBar"'),
      );
      expect(
        contents,
        contains(
          'android:windowSplashScreenBackground">'
          '@color/cardock_splash_background',
        ),
      );
      expect(
        contents,
        contains(
          'android:windowSplashScreenAnimatedIcon">'
          '@drawable/ic_launcher_foreground',
        ),
      );
      expect(
        contents,
        contains(
          'android:windowSplashScreenIconBackgroundColor">'
          '@color/cardock_launcher_background',
        ),
      );
      expect(contents, isNot(contains('postSplashScreenTheme')));
      expect(contents, contains('<style name="NormalTheme"'));
    }

    final lightColors = await File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsString();
    final darkColors = await File(
      'android/app/src/main/res/values-night/colors.xml',
    ).readAsString();
    expect(lightColors, contains('#F0F3F9'));
    expect(lightColors, contains('#CBD1F3'));
    expect(darkColors, contains('#1D2940'));
    expect(darkColors, contains('#221C3A'));
  });

  test('Flutter固定品牌资源均映射为V4 Logo C且旧文件名不残留旧标', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('- assets/branding/'));

    const symbolHashes = <String, String>{
      'standard':
          '3CA5258AAF175358F59ECEEF83AADF3F10F59BAC21556BE8FB33B7974D70D16F',
      'prime':
          'BB13CECCCDC6296B794B36EA4A1ECC3293958497CADF610A9CA3C9CA4B411B44',
      'vivid':
          '81F24B06CDA3B53C61AD6DE693642E011A640836E20C6563E51D8870F5F54E27',
    };
    const wordmarkHashes = <String, String>{
      'light':
          'D34C751961711E8214B2286FA566629CA76BF6490FC67F1240CB2B1F37F1A303',
      'dark':
          'EB23BC6E7F1C9891B669410302B05505D6125954D9BE249CEEC5FD26692F48F8',
    };
    const launcherHashes = <String, String>{
      'standard':
          'D2886B868F54348E61327BD0515A4484C43FB762E5071348756C249A0E0DC5DA',
      'prime':
          '98ED8456A6F91EF379BB3D73C9569C4C120E33B6A951E4E1C3BD55EF8438B926',
      'vivid':
          '85D97C27D6B382F34CBD7601D575359881D8AB11A5A6FF3B30FD4A768352E238',
    };
    for (final family in <String>['standard', 'prime', 'vivid']) {
      for (final mode in <String>['light', 'dark']) {
        final file = File('assets/branding/cardock_${family}_$mode.png');
        expect(await file.exists(), isTrue, reason: file.path);
        final dimensions = await _readPngDimensions(file);
        expect(dimensions, (width: 1024, height: 1024), reason: file.path);
        expect(await _sha256Hex(file), symbolHashes[family], reason: file.path);

        final wordmark = File(
          'assets/branding/cardock_wordmark_${family}_$mode.png',
        );
        expect(await wordmark.exists(), isTrue, reason: wordmark.path);
        expect(
          await _sha256Hex(wordmark),
          wordmarkHashes[mode],
          reason: wordmark.path,
        );
      }

      final launcher = File('assets/branding/cardock_launcher_$family.png');
      expect(await launcher.exists(), isTrue, reason: launcher.path);
      final launcherDimensions = await _readPngDimensions(launcher);
      expect(launcherDimensions, (
        width: 1024,
        height: 1024,
      ), reason: launcher.path);
      expect(
        await _sha256Hex(launcher),
        launcherHashes[family],
        reason: launcher.path,
      );
    }
  });
}

Future<String> _sha256Hex(File file) async {
  final digest = await Sha256().hash(await file.readAsBytes());
  return digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

Future<({bool edgeHasAlpha, double maxRatio})> _readAlphaBounds(
  File file,
) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final frame = await codec.getNextFrame();
  try {
    final image = frame.image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(rgba, isNotNull, reason: file.path);
    final width = image.width;
    final height = image.height;
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    var edgeHasAlpha = false;
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final alpha = rgba!.getUint8(((y * width) + x) * 4 + 3);
        if (alpha == 0) {
          continue;
        }
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
        if (x == 0 || y == 0 || x == width - 1 || y == height - 1) {
          edgeHasAlpha = true;
        }
      }
    }
    expect(maxX, greaterThanOrEqualTo(0), reason: file.path);
    final alphaWidth = maxX - minX + 1;
    final alphaHeight = maxY - minY + 1;
    return (
      edgeHasAlpha: edgeHasAlpha,
      maxRatio: math.max(alphaWidth / width, alphaHeight / height),
    );
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}

Future<({int width, int height})> _readPngDimensions(File file) async {
  final bytes = await file.readAsBytes();
  expect(bytes.sublist(0, 8), <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ], reason: file.path);
  final data = ByteData.sublistView(bytes);
  return (width: data.getUint32(16), height: data.getUint32(20));
}
