import 'dart:convert';
import 'dart:io';

import 'package:account_subscription_manager/core/platform/desktop_icon_controller.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_guard.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/preferences/appearance_preferences.dart';
import 'package:account_subscription_manager/core/theme/cardock_theme_types.dart';
import 'package:account_subscription_manager/core/theme/custom_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('免费态启动时将持久化付费主题静默回退并修复为Paper Archive', () async {
    final store = MemoryAppearancePreferencesStore(
      const AppearancePreferences(family: CardockThemeFamily.neonZero),
    );
    final controller = CardockAppearanceController(
      store: store,
      desktopIconBridge: _RecordingDesktopIconBridge(
        active: CardockLauncherFamily.ceramicBlue,
      ),
    );
    addTearDown(controller.dispose);

    await controller.load(
      sanitizeFamily: (family) =>
          const EntitlementGuard().allowedPersistedTheme(
            entitlement: ProductEntitlement.free,
            requested: family,
          ),
    );

    expect(controller.family, CardockThemeFamily.paperArchive);
    expect(store.value?.family, CardockThemeFamily.paperArchive);
  });

  test('已购态启动时保留持久化付费主题', () async {
    final store = MemoryAppearancePreferencesStore(
      const AppearancePreferences(family: CardockThemeFamily.obsidianGold),
    );
    final controller = CardockAppearanceController(
      store: store,
      desktopIconBridge: _RecordingDesktopIconBridge(
        active: CardockLauncherFamily.obsidianGold,
      ),
    );
    addTearDown(controller.dispose);

    await controller.load(
      sanitizeFamily: (family) =>
          const EntitlementGuard().allowedPersistedTheme(
            entitlement: ProductEntitlement.purchased,
            requested: family,
          ),
    );

    expect(controller.family, CardockThemeFamily.obsidianGold);
    expect(store.value?.family, CardockThemeFamily.obsidianGold);
  });

  test('权益降级回退即使偏好写入失败也保持安全的内存主题', () async {
    final store = _FailingWriteAppearanceStore(
      const AppearancePreferences(family: CardockThemeFamily.mistCoral),
    );
    final controller = CardockAppearanceController(
      store: store,
      desktopIconBridge: _RecordingDesktopIconBridge(
        active: CardockLauncherFamily.mistCoral,
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.family, CardockThemeFamily.mistCoral);
    store.failNextWrite = true;

    await controller.enforceFamilyFallback(CardockThemeFamily.paperArchive);

    expect(controller.family, CardockThemeFamily.paperArchive);
    expect(store.writeCalls, 1);
  });

  test('V5 Neon Zero主题与固定桌面图标选择可往返持久化', () {
    const original = AppearancePreferences(
      family: CardockThemeFamily.neonZero,
      desktopIconMode: CardockDesktopIconMode.obsidianGold,
      brightnessMode: CardockBrightnessMode.dark,
    );

    final restored = AppearancePreferences.tryParse(original.toJson());

    expect(restored, original);
    expect(
      restored!.resolvedLauncherFamily,
      CardockLauncherFamily.obsidianGold,
    );
  });

  test('V5往返保留主题、桌面模式、自定义配色、回退与亮度', () {
    final custom = CardockCustomTheme.defaults.copyWith(
      launcherFallback: CardockLauncherFamily.mistCoral,
      quickSettings: const CardockCustomQuickSettings(
        accentHue: 172,
        chromaPreset: CardockCustomChromaPreset.vivid,
        backgroundDepth: CardockCustomBackgroundDepth.oled,
        neutralTemperature: CardockCustomNeutralTemperature.cool,
      ),
      light: CardockCustomTheme.defaults.light.copyWith(
        background: const Color(0xFFEEF2FA),
      ),
      dark: CardockCustomTheme.defaults.dark.copyWith(
        background: const Color(0xFF101827),
      ),
    );
    final original = AppearancePreferences(
      family: CardockThemeFamily.custom,
      desktopIconMode: CardockDesktopIconMode.followTheme,
      brightnessMode: CardockBrightnessMode.dark,
      customTheme: custom,
    );

    final json = original.toJson();
    final restored = AppearancePreferences.tryParse(json);

    expect(json['version'], AppearancePreferences.formatVersion);
    expect(AppearancePreferences.formatVersion, 5);
    expect(
      (json['customTheme']! as Map<String, Object>)['schemaVersion'],
      CardockCustomTheme.schemaVersion,
    );
    expect(json, isNot(contains('desktopIconFamily')));
    expect(restored, original);
    expect(restored!.resolvedLauncherFamily, CardockLauncherFamily.mistCoral);
    expect(restored.customTheme.quickSettings, custom.quickSettings);
    expect(restored.brightnessMode.themeMode, ThemeMode.dark);
  });

  test('V4 Paper Archive跟随模式迁移为橙墨旧刊专属桌面图标', () {
    final restored = AppearancePreferences.tryParse(<String, Object>{
      'version': 4,
      'family': 'paperArchive',
      'desktopIconMode': 'followTheme',
      'brightnessMode': 'system',
      'customTheme': CardockCustomTheme.defaults.toJson(),
    });

    expect(restored, isNotNull);
    expect(restored!.family, CardockThemeFamily.paperArchive);
    expect(restored.desktopIconMode, CardockDesktopIconMode.followTheme);
    expect(restored.resolvedLauncherFamily, CardockLauncherFamily.paperArchive);
  });
  test('V1迁移固定Standard且忽略旧Logo，绝不迁为followTheme', () {
    final restored = AppearancePreferences.tryParse(<String, Object>{
      'version': 1,
      'family': 'vivid',
      'logoFamily': 'prime',
      'brightnessMode': 'light',
    });
    final invalidLegacyLogo = AppearancePreferences.tryParse(<String, Object>{
      'version': 1,
      'family': 'prime',
      'logoFamily': 'future-is-ignored',
      'brightnessMode': 'dark',
    });

    expect(restored, isNotNull);
    expect(restored!.family, CardockThemeFamily.mistCoral);
    expect(restored.desktopIconMode, CardockDesktopIconMode.ceramicBlue);
    expect(restored.resolvedLauncherFamily, CardockLauncherFamily.ceramicBlue);
    expect(restored.customTheme, CardockCustomTheme.defaults);
    expect(invalidLegacyLogo, isNotNull);
    expect(
      invalidLegacyLogo!.desktopIconMode,
      CardockDesktopIconMode.ceramicBlue,
    );
  });

  test('V2迁移保留原固定桌面选择且切主题不会改成跟随', () {
    final restored = AppearancePreferences.tryParse(<String, Object>{
      'version': 2,
      'family': 'standard',
      'desktopIconFamily': 'prime',
      'brightnessMode': 'system',
    });

    expect(restored, isNotNull);
    expect(restored!.desktopIconMode, CardockDesktopIconMode.obsidianGold);
    expect(restored.resolvedLauncherFamily, CardockLauncherFamily.obsidianGold);
    expect(
      restored
          .copyWith(family: CardockThemeFamily.mistCoral)
          .resolvedLauncherFamily,
      CardockLauncherFamily.obsidianGold,
    );
  });

  test('v1/v2 仅迁移历史三主题且继续拒绝伪造 Mono 与 Custom', () {
    final expected = <String, CardockThemeFamily>{
      'standard': CardockThemeFamily.ceramicBlue,
      'prime': CardockThemeFamily.obsidianGold,
      'vivid': CardockThemeFamily.mistCoral,
    };
    for (final entry in expected.entries) {
      final v1 = AppearancePreferences.tryParse(<String, Object>{
        'version': 1,
        'family': entry.key,
        'logoFamily': 'ignored',
        'brightnessMode': 'light',
      });
      final v2 = AppearancePreferences.tryParse(<String, Object>{
        'version': 2,
        'family': entry.key,
        'desktopIconFamily': 'vivid',
        'brightnessMode': 'dark',
      });
      expect(v1?.family, entry.value, reason: 'v1 ${entry.key}');
      expect(v1?.brightnessMode, CardockBrightnessMode.light);
      expect(v2?.family, entry.value, reason: 'v2 ${entry.key}');
      expect(v2?.brightnessMode, CardockBrightnessMode.dark);
      expect(v2?.desktopIconMode, CardockDesktopIconMode.mistCoral);
    }
    for (final forged in <String>['mono', 'custom']) {
      expect(
        AppearancePreferences.tryParse(<String, Object>{
          'version': 1,
          'family': forged,
          'brightnessMode': 'system',
        }),
        isNull,
      );
      expect(
        AppearancePreferences.tryParse(<String, Object>{
          'version': 2,
          'family': forged,
          'desktopIconFamily': 'standard',
          'brightnessMode': 'system',
        }),
        isNull,
      );
    }
  });

  test('v3 五个旧主题精确迁移并保留亮度、桌面模式与 Custom', () {
    final expected = <String, CardockThemeFamily>{
      'standard': CardockThemeFamily.ceramicBlue,
      'prime': CardockThemeFamily.obsidianGold,
      'vivid': CardockThemeFamily.mistCoral,
      'mono': CardockThemeFamily.neonZero,
      'custom': CardockThemeFamily.custom,
    };
    final custom = CardockCustomTheme.defaults.copyWith(
      launcherFallback: CardockLauncherFamily.mistCoral,
    );
    for (final entry in expected.entries) {
      final restored = AppearancePreferences.tryParse(<String, Object>{
        'version': 3,
        'family': entry.key,
        'desktopIconMode': 'followTheme',
        'brightnessMode': 'dark',
        'customTheme': custom.toJson(),
      });
      expect(restored?.family, entry.value, reason: 'v3 ${entry.key}');
      expect(restored?.desktopIconMode, CardockDesktopIconMode.followTheme);
      expect(restored?.brightnessMode, CardockBrightnessMode.dark);
      expect(restored?.customTheme, custom);
    }
  });

  test('文件仓库成功读取 v3 后以原文件名回写 v5', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cardock-appearance-v5-writeback-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final file = File(
      '${directory.path}${Platform.pathSeparator}cardock_appearance_v1.json',
    );
    await file.writeAsString(
      jsonEncode(<String, Object>{
        'version': 3,
        'family': 'prime',
        'desktopIconMode': 'vivid',
        'brightnessMode': 'dark',
        'customTheme': CardockCustomTheme.defaults.toJson(),
      }),
    );

    final restored = await FileAppearancePreferencesStore(file).read();
    final rewritten =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;

    expect(restored?.family, CardockThemeFamily.obsidianGold);
    expect(restored?.brightnessMode, CardockBrightnessMode.dark);
    expect(restored?.desktopIconMode, CardockDesktopIconMode.mistCoral);
    expect(rewritten['version'], 5);
    expect(rewritten['family'], 'obsidianGold');
    expect(rewritten['brightnessMode'], 'dark');
    expect(rewritten['desktopIconMode'], 'mistCoral');
  });
  test('未知未来顶层安全拒绝，未来Custom子schema按已知token逐项恢复', () {
    final invalidValues = <Object?>[
      null,
      <Object?>[],
      <String, Object>{},
      <String, Object>{
        'version': AppearancePreferences.formatVersion + 1,
        'family': 'standard',
        'desktopIconMode': 'standard',
        'brightnessMode': 'system',
      },
      <String, Object>{
        'version': AppearancePreferences.formatVersion,
        'family': 'future',
        'desktopIconMode': 'standard',
        'brightnessMode': 'system',
      },
      <String, Object>{
        'version': AppearancePreferences.formatVersion,
        'family': 'standard',
        'desktopIconMode': 'future',
        'brightnessMode': 'system',
      },
      <String, Object>{
        'version': AppearancePreferences.formatVersion,
        'family': 'standard',
        'desktopIconMode': 'standard',
        'brightnessMode': 'future',
      },
      <String, Object>{
        'version': 2,
        'family': 'custom',
        'desktopIconFamily': 'standard',
        'brightnessMode': 'system',
      },
      <String, Object>{
        'version': 2,
        'family': 'standard',
        'desktopIconFamily': 'custom',
        'brightnessMode': 'system',
      },
    ];

    for (final value in invalidValues) {
      expect(AppearancePreferences.tryParse(value), isNull, reason: '$value');
    }

    final futureCustom = AppearancePreferences.tryParse(<String, Object>{
      'version': 3,
      'family': 'custom',
      'desktopIconMode': 'followTheme',
      'brightnessMode': 'system',
      'customTheme': <String, Object>{
        'schemaVersion': 99,
        'launcherFallback': 'vivid',
      },
    });
    expect(futureCustom, isNotNull);
    expect(
      futureCustom!.customTheme.launcherFallback,
      CardockLauncherFamily.mistCoral,
    );
    expect(
      futureCustom.resolvedLauncherFamily,
      CardockLauncherFamily.mistCoral,
    );
  });

  test('损坏JSON文件读取为空且不会改变安全默认外观', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cardock-appearance-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final file = File('${directory.path}${Platform.pathSeparator}appearance');
    await file.writeAsString('{not-json');
    final bridge = _RecordingDesktopIconBridge(
      active: CardockLauncherFamily.ceramicBlue,
    );
    final controller = CardockAppearanceController(
      store: FileAppearancePreferencesStore(file),
      desktopIconBridge: bridge,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isLoaded, isTrue);
    expect(controller.preferences, const AppearancePreferences());
    expect(controller.desktopIconMode, CardockDesktopIconMode.followTheme);
    expect(controller.customTheme, CardockCustomTheme.defaults);
    expect(bridge.setCalls, [CardockLauncherFamily.paperArchive]);
  });

  test('未来顶层外观文件安全拒绝且不读取或切换当前桌面别名', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cardock-appearance-future-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final file = File('${directory.path}${Platform.pathSeparator}appearance');
    await file.writeAsString(
      jsonEncode(<String, Object>{
        'version': AppearancePreferences.formatVersion + 1,
        'family': 'standard',
        'desktopIconMode': 'standard',
        'brightnessMode': 'system',
      }),
    );
    final bridge = _RecordingDesktopIconBridge(
      active: CardockLauncherFamily.obsidianGold,
    );
    final controller = CardockAppearanceController(
      store: FileAppearancePreferencesStore(file),
      desktopIconBridge: bridge,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.preferences, const AppearancePreferences());
    expect(bridge.getCalls, 0);
    expect(bridge.setCalls, isEmpty);
    expect(bridge.active, CardockLauncherFamily.obsidianGold);
  });

  test('Paper Archive跟随模式启动时把旧Prime别名强制迁移为专属别名', () async {
    const stored = AppearancePreferences(
      family: CardockThemeFamily.paperArchive,
      desktopIconMode: CardockDesktopIconMode.followTheme,
    );
    final bridge = _RecordingDesktopIconBridge(
      active: null,
      getError: const DesktopIconMigrationRequiredException('prime'),
    );
    final controller = CardockAppearanceController(
      store: MemoryAppearancePreferencesStore(stored),
      desktopIconBridge: bridge,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(bridge.setCalls, <CardockLauncherFamily>[
      CardockLauncherFamily.paperArchive,
    ]);
    expect(bridge.active, CardockLauncherFamily.paperArchive);
  });
  test('启动按保存模式解析alias且仅在活动alias不一致时修正', () async {
    final stored = AppearancePreferences(
      family: CardockThemeFamily.custom,
      desktopIconMode: CardockDesktopIconMode.followTheme,
      customTheme: CardockCustomTheme.defaults.copyWith(
        launcherFallback: CardockLauncherFamily.obsidianGold,
      ),
    );
    final matched = _RecordingDesktopIconBridge(
      active: CardockLauncherFamily.obsidianGold,
    );
    final matchedController = CardockAppearanceController(
      store: MemoryAppearancePreferencesStore(stored),
      desktopIconBridge: matched,
    );
    addTearDown(matchedController.dispose);
    await matchedController.load();
    expect(matched.getCalls, 1);
    expect(matched.setCalls, isEmpty);

    final mismatched = _RecordingDesktopIconBridge(
      active: CardockLauncherFamily.ceramicBlue,
    );
    final mismatchedController = CardockAppearanceController(
      store: MemoryAppearancePreferencesStore(stored),
      desktopIconBridge: mismatched,
    );
    addTearDown(mismatchedController.dispose);
    await mismatchedController.load();
    expect(mismatched.setCalls, <CardockLauncherFamily>[
      CardockLauncherFamily.obsidianGold,
    ]);
  });

  for (final errorCode in const <String>[
    'NO_ENABLED_ALIAS',
    'MULTIPLE_ENABLED_ALIASES',
  ]) {
    test('启动遇到$errorCode时按已解析launcher修复alias状态', () async {
      const stored = AppearancePreferences(
        desktopIconMode: CardockDesktopIconMode.mistCoral,
      );
      final bridge = _RecordingDesktopIconBridge(
        active: null,
        getError: PlatformException(code: errorCode),
      );
      final controller = CardockAppearanceController(
        store: MemoryAppearancePreferencesStore(stored),
        desktopIconBridge: bridge,
      );
      addTearDown(controller.dispose);

      await expectLater(controller.load(), completes);
      expect(bridge.setCalls, <CardockLauncherFamily>[
        CardockLauncherFamily.mistCoral,
      ]);
    });
  }

  test('其他PlatformException安全完成且不盲目切换alias', () async {
    final bridge = _RecordingDesktopIconBridge(
      active: null,
      getError: PlatformException(code: 'PACKAGE_MANAGER_FAILURE'),
    );
    final controller = CardockAppearanceController(
      store: MemoryAppearancePreferencesStore(
        const AppearancePreferences(
          desktopIconMode: CardockDesktopIconMode.obsidianGold,
        ),
      ),
      desktopIconBridge: bridge,
    );
    addTearDown(controller.dispose);

    await expectLater(controller.load(), completes);
    expect(bridge.setCalls, isEmpty);
  });

  test('固定手选不被切主题覆盖，setDesktopIconFamily保持固定选择兼容API', () async {
    final store = MemoryAppearancePreferencesStore();
    final bridge = _RecordingDesktopIconBridge(
      active: CardockLauncherFamily.ceramicBlue,
    );
    final controller = CardockAppearanceController(
      store: store,
      desktopIconBridge: bridge,
    );
    addTearDown(controller.dispose);
    await controller.load();
    bridge.setCalls.clear();

    await controller.setDesktopIconFamily(CardockLauncherFamily.mistCoral);
    await controller.setFamily(CardockThemeFamily.obsidianGold);

    expect(controller.desktopIconMode, CardockDesktopIconMode.mistCoral);
    expect(controller.resolvedLauncherFamily, CardockLauncherFamily.mistCoral);
    expect(bridge.setCalls, <CardockLauncherFamily>[
      CardockLauncherFamily.mistCoral,
    ]);
    expect(store.value?.toJson(), controller.preferences.toJson());
  });

  test('跟随模式切固定主题、自定义主题及回退会同步对应别名', () async {
    final store = MemoryAppearancePreferencesStore(
      const AppearancePreferences(
        family: CardockThemeFamily.ceramicBlue,
        desktopIconMode: CardockDesktopIconMode.followTheme,
      ),
    );
    final bridge = _RecordingDesktopIconBridge(
      active: CardockLauncherFamily.ceramicBlue,
    );
    final controller = CardockAppearanceController(
      store: store,
      desktopIconBridge: bridge,
    );
    addTearDown(controller.dispose);
    await controller.load();

    await controller.setFamily(CardockThemeFamily.obsidianGold);
    await controller.setFamily(CardockThemeFamily.custom);
    await controller.setCustomTheme(
      CardockCustomTheme.defaults.copyWith(
        launcherFallback: CardockLauncherFamily.mistCoral,
      ),
    );

    expect(bridge.setCalls, <CardockLauncherFamily>[
      CardockLauncherFamily.obsidianGold,
      CardockLauncherFamily.ceramicBlue,
      CardockLauncherFamily.mistCoral,
    ]);
    expect(controller.resolvedLauncherFamily, CardockLauncherFamily.mistCoral);
  });

  test('跟随主题原生切换失败回滚主题和持久化且可重试', () async {
    final store = MemoryAppearancePreferencesStore(
      const AppearancePreferences(
        desktopIconMode: CardockDesktopIconMode.followTheme,
      ),
    );
    final bridge = _RecordingDesktopIconBridge(
      active: CardockLauncherFamily.paperArchive,
      remainingSetFailures: 1,
    );
    final controller = CardockAppearanceController(
      store: store,
      desktopIconBridge: bridge,
    );
    addTearDown(controller.dispose);
    await controller.load();

    await expectLater(
      controller.setFamily(CardockThemeFamily.obsidianGold),
      throwsA(isA<StateError>()),
    );
    expect(controller.family, CardockThemeFamily.paperArchive);
    expect(store.value?.family, CardockThemeFamily.paperArchive);

    await controller.setFamily(CardockThemeFamily.obsidianGold);
    expect(controller.family, CardockThemeFamily.obsidianGold);
    expect(bridge.active, CardockLauncherFamily.obsidianGold);
  });

  test('偏好写入失败先回滚且不会调用原生桌面图标切换', () async {
    final store = _FailingWriteAppearanceStore();
    final bridge = _RecordingDesktopIconBridge(
      active: CardockLauncherFamily.ceramicBlue,
    );
    final controller = CardockAppearanceController(
      store: store,
      desktopIconBridge: bridge,
    );
    addTearDown(controller.dispose);
    await controller.load();
    bridge.setCalls.clear();
    store.failNextWrite = true;

    await expectLater(
      controller.setDesktopIconMode(CardockDesktopIconMode.obsidianGold),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.desktopIconMode, CardockDesktopIconMode.followTheme);
    expect(bridge.setCalls, isEmpty);
  });

  test('自定义主题对比度不合格在持久化和通道前精确拒绝', () async {
    final store = MemoryAppearancePreferencesStore();
    final bridge = _RecordingDesktopIconBridge(
      active: CardockLauncherFamily.ceramicBlue,
    );
    final controller = CardockAppearanceController(
      store: store,
      desktopIconBridge: bridge,
    );
    addTearDown(controller.dispose);
    await controller.load();
    bridge.setCalls.clear();
    final before = store.value;
    final invalid = CardockCustomTheme.defaults.copyWith(
      light: CardockCustomTheme.defaults.light.copyWith(text: Colors.white),
    );

    await expectLater(
      controller.setCustomTheme(invalid),
      throwsA(
        isA<CardockCustomThemeValidationException>().having(
          (error) => error.issues.map((issue) => issue.token),
          'tokens',
          contains('light.foundation.text/background'),
        ),
      ),
    );
    expect(controller.customTheme, CardockCustomTheme.defaults);
    expect(store.value, before);
    expect(bridge.setCalls, isEmpty);
  });

  test('未等待的启动加载吞掉仓库与桥错误并保持安全默认值', () async {
    final controller = CardockAppearanceController(
      store: _ThrowingReadAppearanceStore(),
      desktopIconBridge: _ThrowingDesktopIconBridge(),
    );
    addTearDown(controller.dispose);

    await expectLater(controller.load(), completes);
    expect(controller.isLoaded, isTrue);
    expect(controller.preferences, const AppearancePreferences());
  });
}

final class _RecordingDesktopIconBridge implements DesktopIconBridge {
  _RecordingDesktopIconBridge({
    required this.active,
    this.getError,
    this.remainingSetFailures = 0,
  });

  CardockLauncherFamily? active;
  final Object? getError;
  int remainingSetFailures;
  int getCalls = 0;
  final List<CardockLauncherFamily> setCalls = <CardockLauncherFamily>[];

  @override
  Future<CardockLauncherFamily?> getActiveIcon() async {
    getCalls += 1;
    if (getError case final error?) throw error;
    return active;
  }

  @override
  Future<void> setIcon(CardockLauncherFamily family) async {
    setCalls.add(family);
    if (remainingSetFailures > 0) {
      remainingSetFailures -= 1;
      throw StateError('test launcher icon switch failure');
    }
    active = family;
  }
}

final class _FailingWriteAppearanceStore
    extends MemoryAppearancePreferencesStore {
  _FailingWriteAppearanceStore([super.value]);

  bool failNextWrite = false;
  int writeCalls = 0;

  @override
  Future<void> write(AppearancePreferences preferences) async {
    writeCalls += 1;
    if (failNextWrite) {
      failNextWrite = false;
      throw const FileSystemException('test appearance write failure');
    }
    await super.write(preferences);
  }
}

final class _ThrowingReadAppearanceStore implements AppearancePreferencesStore {
  @override
  Future<AppearancePreferences?> read() async {
    throw const FileSystemException('test appearance read failure');
  }

  @override
  Future<void> write(AppearancePreferences preferences) async {}
}

final class _ThrowingDesktopIconBridge implements DesktopIconBridge {
  @override
  Future<CardockLauncherFamily?> getActiveIcon() async {
    throw StateError('test launcher icon read failure');
  }

  @override
  Future<void> setIcon(CardockLauncherFamily family) async {
    throw StateError('test launcher icon switch failure');
  }
}
