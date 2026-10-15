import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_service.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:account_subscription_manager/core/platform/desktop_icon_controller.dart';
import 'package:account_subscription_manager/core/preferences/appearance_preferences.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:account_subscription_manager/core/theme/custom_theme.dart';
import 'package:account_subscription_manager/features/settings/presentation/custom_theme_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _customColorTokenNames = <String>{
  'background',
  'surface',
  'surfaceAlt',
  'text',
  'textSecondary',
  'border',
  'brandPrimary',
  'brandSecondary',
  'navigationActive',
  'focus',
  'overviewStart',
  'overviewEnd',
  'currencyAccent',
  'accountAccent',
  'accountIconBackground',
  'fieldLogin',
  'fieldPhone',
  'fieldEmail',
  'fieldPassword',
  'fieldUrl',
  'subscriptionAccent',
  'renewalAccent',
  'subscriptionIconBackground',
  'actionPrimary',
  'actionSecondary',
  'inputFocus',
  'success',
  'warning',
  'danger',
  'paused',
  'neutral',
};

void main() {
  testWidgets('Custom编辑器展示五类中性预览、四快捷控件、七组31色与固定图标回退', (tester) async {
    await _setViewport(tester, const Size(900, 5000));
    final harness = await _pumpEditor(
      tester,
      accountCount: 7,
      subscriptionCount: 11,
      renewalsWithinThirtyDays: 3,
    );
    addTearDown(harness.dispose);

    expect(
      find.byKey(const ValueKey<String>('custom-theme-editor-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('custom-theme-live-preview')),
      findsOneWidget,
    );
    expect(find.text('7 个账号 · 11 项订阅'), findsNothing);
    expect(find.text('3 项待续'), findsNothing);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('custom-theme-quick-controls')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('custom-quick-accent-hue')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('custom-quick-chroma')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('custom-quick-depth')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('custom-quick-temperature')),
      findsOneWidget,
    );

    for (final preview in <(String, String)>[
      ('首页', 'custom-preview-home'),
      ('账号卡', 'custom-preview-account'),
      ('订阅卡', 'custom-preview-subscription'),
      ('Dock', 'custom-preview-dock'),
      ('Logo C', 'custom-preview-logo'),
    ]) {
      await tester.tap(find.text(preview.$1).first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey<String>(preview.$2)),
        findsOneWidget,
        reason: preview.$1,
      );
    }

    await tester.tap(
      find.byKey(const ValueKey<String>('custom-theme-advanced-editor')),
    );
    await tester.pumpAndSettle();

    for (final label in <String>[
      '基础界面',
      '品牌与导航',
      '首页总览',
      '账号模块',
      '订阅模块',
      '表单与操作',
      '状态颜色（高级）',
    ]) {
      expect(find.text(label, skipOffstage: false), findsWidgets);
    }

    await tester.tap(
      find.byKey(const ValueKey<String>('custom-theme-semantic-states')),
    );
    await tester.pumpAndSettle();

    final actualTokenNames = tester
        .widgetList<Widget>(
          find.byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('custom-theme-color-');
          }, skipOffstage: false),
        )
        .map((widget) => (widget.key! as ValueKey<String>).value)
        .map((key) => key.replaceFirst('custom-theme-color-', ''))
        .toSet();
    expect(actualTokenNames, _customColorTokenNames);
    expect(actualTokenNames, hasLength(31));

    final fallbackField = find.byKey(
      const ValueKey<String>('custom-theme-launcher-fallback'),
    );
    final dropdown = tester.widget<DropdownButton<CardockLauncherFamily>>(
      find.descendant(
        of: fallbackField,
        matching: find.byType(DropdownButton<CardockLauncherFamily>),
      ),
    );
    expect(
      dropdown.items!.map((item) => item.value).toSet(),
      cardockLauncherFamilies,
    );
    expect(dropdown.items, hasLength(8));

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<Brightness>>(
            find.byKey(const ValueKey<String>('custom-theme-brightness')),
          )
          .selected,
      <Brightness>{Brightness.dark},
    );
    expect(harness.controller.customTheme, CardockCustomTheme.defaults);
  });

  testWidgets('非法对比度会列出精确问题并拒绝写入Custom配置', (tester) async {
    await _setViewport(tester, const Size(800, 1400));
    final harness = await _pumpEditor(
      tester,
      accountCount: 1,
      subscriptionCount: 2,
      renewalsWithinThirtyDays: 1,
    );
    addTearDown(harness.dispose);

    final textToken = find.byKey(
      const ValueKey<String>('custom-theme-color-text'),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('custom-theme-advanced-editor')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('custom-theme-advanced-editor')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(textToken);
    await tester.tap(textToken);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('custom-color-hex')),
      '#F5F7FC',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('custom-color-hex')),
          )
          .controller!
          .text,
      '#F5F7FC',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('custom-color-confirm')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('custom-color-confirm')),
    );
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey<String>('custom-theme-save'));
    expect(tester.widget<TextButton>(save).onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey<String>('custom-theme-validation-review')),
    );
    await tester.pumpAndSettle();

    expect(find.text('这些颜色暂时不能保存'), findsOneWidget);
    expect(find.textContaining('浅色 · 基础界面 · text/background'), findsOneWidget);
    expect(find.textContaining('前景 #F5F7FC / 背景 #F5F7FC'), findsWidgets);
    expect(find.textContaining('当前 1.00:1'), findsWidgets);
    expect(find.textContaining('至少 4.5:1'), findsWidgets);
    expect(find.textContaining('建议起点 #142033'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('custom-theme-auto-fix')),
      findsOneWidget,
    );
    expect(harness.controller.customTheme, CardockCustomTheme.defaults);
    expect(
      harness.store.value?.customTheme,
      CardockCustomTheme.defaults,
      reason: '校验失败不得落盘',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('custom-theme-auto-fix')),
    );
    await tester.pumpAndSettle();
    expect(find.text('这些颜色暂时不能保存'), findsNothing);
    expect(harness.controller.customTheme, CardockCustomTheme.defaults);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey<String>('custom-theme-undo')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('快速生成可一次撤销、单组重置并保存V2元数据', (tester) async {
    await _setViewport(tester, const Size(900, 5000));
    final harness = await _pumpEditor(
      tester,
      accountCount: 0,
      subscriptionCount: 0,
      renewalsWithinThirtyDays: 0,
    );
    addTearDown(harness.dispose);

    final hue = find.byKey(const ValueKey<String>('custom-quick-accent-hue'));
    expect(tester.widget<Slider>(hue).value, 232);
    await tester.drag(hue, const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(hue).value, isNot(232));

    await tester.tap(find.byKey(const ValueKey<String>('custom-theme-undo')));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(hue).value, 232);

    await tester.tap(find.byKey(const ValueKey<String>('custom-quick-depth')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OLED').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('custom-theme-advanced-editor')),
    );
    await tester.pumpAndSettle();
    final resetFoundation = find.byKey(
      const ValueKey<String>('custom-theme-reset-group-foundation'),
    );
    await tester.ensureVisible(resetFoundation);
    await tester.tap(resetFoundation);
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey<String>('custom-theme-save'));
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
      harness.controller.customTheme.quickSettings.backgroundDepth,
      CardockCustomBackgroundDepth.oled,
    );
    expect(
      harness.controller.customTheme.light.background,
      CardockCustomTheme.defaults.light.background,
    );
    expect(harness.controller.customTheme.validate(), isEmpty);
    expect(harness.controller.family, CardockThemeFamily.paperArchive);
    expect(
      harness.controller.desktopIconMode,
      CardockDesktopIconMode.followTheme,
    );
  });

  testWidgets('200%字体下预览、快捷控件与48dp操作热区不溢出', (tester) async {
    await _setViewport(tester, const Size(393, 1200));
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final harness = await _pumpEditor(
      tester,
      accountCount: 1,
      subscriptionCount: 1,
      renewalsWithinThirtyDays: 1,
    );
    addTearDown(harness.dispose);

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(TabBar), const Offset(-240, 0));
    await tester.pumpAndSettle();
    for (final label in <String>['首页', '账号卡', '订阅卡', 'Dock', 'Logo C']) {
      expect(find.text(label, skipOffstage: false), findsWidgets);
    }
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('custom-quick-accent-hue')),
          )
          .height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('恢复默认值只保存Custom且不改变主题亮度或固定桌面图标', (tester) async {
    await _setViewport(tester, const Size(900, 5000));
    final initialCustom = CardockCustomTheme.defaults.copyWith(
      launcherFallback: CardockLauncherFamily.obsidianGold,
    );
    final initialPreferences = AppearancePreferences(
      family: CardockThemeFamily.obsidianGold,
      desktopIconMode: CardockDesktopIconMode.mistCoral,
      brightnessMode: CardockBrightnessMode.dark,
      customTheme: initialCustom,
    );
    final harness = await _pumpEditor(
      tester,
      accountCount: 2,
      subscriptionCount: 4,
      renewalsWithinThirtyDays: 1,
      initialPreferences: initialPreferences,
      activeLauncher: CardockLauncherFamily.mistCoral,
    );
    addTearDown(harness.dispose);

    await tester.tap(find.byKey(const ValueKey<String>('custom-theme-reset')));
    await tester.pumpAndSettle();
    expect(find.text('恢复自定义默认值？'), findsOneWidget);
    expect(find.textContaining('八套固定主题不受影响'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey<String>('custom-theme-save'));
    expect(tester.widget<TextButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(harness.controller.family, CardockThemeFamily.obsidianGold);
    expect(harness.controller.brightnessMode, CardockBrightnessMode.dark);
    expect(
      harness.controller.desktopIconMode,
      CardockDesktopIconMode.mistCoral,
    );
    expect(
      harness.controller.desktopIconFamily,
      CardockLauncherFamily.mistCoral,
    );
    expect(harness.controller.customTheme, CardockCustomTheme.defaults);
    expect(harness.store.value?.family, CardockThemeFamily.obsidianGold);
    expect(harness.store.value?.brightnessMode, CardockBrightnessMode.dark);
    expect(
      harness.store.value?.desktopIconMode,
      CardockDesktopIconMode.mistCoral,
    );
    expect(harness.store.value?.customTheme, CardockCustomTheme.defaults);
    expect(harness.bridge.setCalls, isEmpty, reason: '固定桌面图标不应被Custom重置触发');
  });
}

Future<_EditorHarness> _pumpEditor(
  WidgetTester tester, {
  required int accountCount,
  required int subscriptionCount,
  required int renewalsWithinThirtyDays,
  AppearancePreferences initialPreferences = const AppearancePreferences(),
  CardockLauncherFamily activeLauncher = CardockLauncherFamily.ceramicBlue,
}) async {
  final store = MemoryAppearancePreferencesStore(initialPreferences);
  final bridge = _RecordingDesktopIconBridge(activeLauncher);
  final controller = CardockAppearanceController(
    store: store,
    desktopIconBridge: bridge,
  );
  await controller.load();
  final entitlementController = ProductEntitlementController(
    gateway: MockStoreGateway(
      initialEntitlement: ProductEntitlement.purchased,
      simulationEnabled: true,
    ),
  );
  await entitlementController.initialize();
  addTearDown(entitlementController.dispose);
  await tester.pumpWidget(
    ProductEntitlementScope(
      controller: entitlementController,
      child: CardockAppearanceScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(
            family: controller.family,
            customTheme: controller.customTheme,
          ),
          home: CustomThemeEditorPage(
            controller: controller,
            accountCount: accountCount,
            subscriptionCount: subscriptionCount,
            renewalsWithinThirtyDays: renewalsWithinThirtyDays,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _EditorHarness(controller: controller, store: store, bridge: bridge);
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

final class _EditorHarness {
  const _EditorHarness({
    required this.controller,
    required this.store,
    required this.bridge,
  });

  final CardockAppearanceController controller;
  final MemoryAppearancePreferencesStore store;
  final _RecordingDesktopIconBridge bridge;

  void dispose() => controller.dispose();
}

final class _RecordingDesktopIconBridge implements DesktopIconBridge {
  _RecordingDesktopIconBridge(this.active);

  CardockLauncherFamily active;
  final List<CardockLauncherFamily> setCalls = <CardockLauncherFamily>[];

  @override
  Future<CardockLauncherFamily?> getActiveIcon() async => active;

  @override
  Future<void> setIcon(CardockLauncherFamily family) async {
    setCalls.add(family);
    active = family;
  }
}
