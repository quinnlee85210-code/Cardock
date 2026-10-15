import 'dart:math' as math;

import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:account_subscription_manager/core/preferences/appearance_preferences.dart';
import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/core/theme/app_theme.dart';
import 'package:account_subscription_manager/core/theme/cardock_tokens.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/accounts/presentation/account_editor_page.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:account_subscription_manager/features/subscriptions/presentation/subscription_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _testMasterPassword = 'TEST-ONLY-MASTER-1234';

const _viewports = <({String label, Size size})>[
  (label: '320x640', size: Size(320, 640)),
  (label: '360x800', size: Size(360, 800)),
  (label: '393x873', size: Size(393, 873)),
  (label: '411x915', size: Size(411, 915)),
];

const _textScales = <double>[1, 1.3, 1.5, 2];

void main() {
  for (final language in CardockLanguage.values) {
    for (final viewport in _viewports) {
      for (final textScale in _textScales) {
        testWidgets('Cardock响应式 ${language.storageCode} ${viewport.label} '
            '文字$textScale 首页订阅设置无溢出', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport.size;
          tester.binding.platformDispatcher.textScaleFactorTestValue =
              textScale;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(
            tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
          );

          final account = _account();
          final subscriptions = _subscriptions();
          final appearanceStore = MemoryAppearancePreferencesStore();
          final languageController = CardockLanguageController(
            store: MemoryLanguagePreferencesStore(
              LanguagePreferences(language: language),
            ),
          );
          await languageController.load();
          addTearDown(languageController.dispose);
          final store = FakeVaultStore(
            configured: true,
            acceptedPassword: _testMasterPassword,
            snapshot: VaultSnapshot(
              nextAccountId: 2,
              accounts: <AccountRecord>[account],
              nextSubscriptionId: 7,
              subscriptions: subscriptions,
              recentAccountIds: <String>[account.id],
            ),
          );
          final caseLabel =
              '${language.storageCode} / ${viewport.label} / $textScale';

          await tester.pumpWidget(
            AccountSubscriptionApp(
              vaultStore: store,
              appearanceStore: appearanceStore,
              languageController: languageController,
              purchaseGateway: MockStoreGateway(
                initialEntitlement: ProductEntitlement.purchased,
                simulationEnabled: true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          _expectNoLayoutException(tester, '$caseLabel 解锁页');

          await tester.enterText(
            find.byKey(const ValueKey<String>('unlock-master-password-field')),
            _testMasterPassword,
          );
          final unlockButton = find.byKey(
            const ValueKey<String>('unlock-vault-button'),
          );
          await tester.ensureVisible(unlockButton);
          await tester.tap(unlockButton);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey<String>('home-page')),
            findsOneWidget,
          );
          _expectNoLayoutException(tester, '$caseLabel 首页首屏');
          final renewalOverview = find.byKey(
            const ValueKey<String>('home-renewal-overview'),
          );
          await _revealPageTarget(
            tester,
            pageKey: const ValueKey<String>('home-page'),
            target: renewalOverview,
            label: '$caseLabel V6续费雷达',
          );
          expect(
            find.byKey(
              const ValueKey<String>('home-metric-auto-renew-this-month'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(
              const ValueKey<String>('home-metric-renewals-next-month'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(
              const ValueKey<String>('home-metric-renewing-within-thirty-days'),
            ),
            findsOneWidget,
          );
          _expectNoLayoutException(tester, '$caseLabel V6续费雷达');
          await _exerciseVerticalPage(
            tester,
            pageKey: const ValueKey<String>('home-page'),
            label: '$caseLabel 首页滚动',
          );

          await tester.tap(find.byKey(const ValueKey<String>('nav-accounts')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey<String>('accounts-page')),
            findsOneWidget,
          );
          expect(
            find.byKey(
              const ValueKey<String>('account-category-group-非常长的自定义分类名称'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(
              const ValueKey<String>('account-category-toggle-非常长的自定义分类名称'),
            ),
            findsOneWidget,
          );
          if (viewport.label == '320x640' && textScale == 2) {
            final categoryHeader = find.byKey(
              const ValueKey<String>('account-category-group-非常长的自定义分类名称'),
            );
            await tester.tap(categoryHeader);
            await tester.pump();
            expect(
              find.byKey(const ValueKey<String>('account-card-account-1')),
              findsNothing,
            );
            _expectNoLayoutException(tester, '$caseLabel 账号分类折叠');
            await tester.tap(categoryHeader);
            await tester.pump();
            expect(
              find.byKey(const ValueKey<String>('account-card-account-1')),
              findsOneWidget,
            );
          }
          expect(
            find.text('设置'),
            findsWidgets,
            reason: '$caseLabel 用户输入即使等于 UI 文案也不得翻译',
          );
          _expectNoLayoutException(tester, '$caseLabel 账号首屏');
          await _exerciseVerticalPage(
            tester,
            pageKey: const ValueKey<String>('accounts-page'),
            label: '$caseLabel 账号滚动',
          );

          await tester.tap(
            find.byKey(const ValueKey<String>('nav-subscriptions')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey<String>('subscriptions-page')),
            findsOneWidget,
          );
          _expectNoLayoutException(tester, '$caseLabel 订阅首屏');
          await _exerciseVerticalPage(
            tester,
            pageKey: const ValueKey<String>('subscriptions-page'),
            label: '$caseLabel 订阅滚动',
          );

          await tester.tap(find.byKey(const ValueKey<String>('nav-settings')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey<String>('settings-page')),
            findsOneWidget,
          );
          _expectNoLayoutException(tester, '$caseLabel 设置首屏');

          await _revealPageTarget(
            tester,
            pageKey: const ValueKey<String>('settings-page'),
            target: find.byKey(
              const ValueKey<String>('appearance-settings-entry'),
            ),
            label: '$caseLabel 外观入口',
          );
          await tester.tap(
            find.byKey(const ValueKey<String>('appearance-settings-entry')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey<String>('appearance-settings-page')),
            findsOneWidget,
          );
          _expectNoLayoutException(tester, '$caseLabel 外观页首屏');

          await _revealPageTarget(
            tester,
            pageKey: const ValueKey<String>('appearance-settings-page'),
            target: find.byKey(
              const ValueKey<String>('appearance-brightness-mode'),
            ),
            label: '$caseLabel 外观模式',
          );
          final brightnessMode = find.byKey(
            const ValueKey<String>('appearance-brightness-mode'),
          );
          final brightnessButton = tester
              .widget<SegmentedButton<CardockBrightnessMode>>(brightnessMode);
          expect(
            brightnessButton.direction,
            viewport.size.width <= 360 || textScale >= 1.5
                ? Axis.vertical
                : Axis.horizontal,
            reason: '$caseLabel 外观模式方向',
          );
          for (final mode in CardockBrightnessMode.values) {
            expect(
              find.byKey(
                ValueKey<String>('appearance-brightness-${mode.name}'),
              ),
              findsOneWidget,
              reason: '$caseLabel ${mode.name}',
            );
          }
          await Scrollable.ensureVisible(
            tester.element(brightnessMode),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          final brightnessRect = tester.getRect(brightnessMode);
          final darkIndex = CardockBrightnessMode.values.indexOf(
            CardockBrightnessMode.dark,
          );
          final segmentCount = CardockBrightnessMode.values.length;
          final darkSegmentCenter = brightnessButton.direction == Axis.vertical
              ? Offset(
                  brightnessRect.center.dx,
                  brightnessRect.top +
                      brightnessRect.height * (darkIndex + 0.5) / segmentCount,
                )
              : Offset(
                  brightnessRect.left +
                      brightnessRect.width * (darkIndex + 0.5) / segmentCount,
                  brightnessRect.center.dy,
                );
          await tester.tapAt(darkSegmentCenter);
          await tester.pumpAndSettle();
          expect(
            appearanceStore.value?.brightnessMode,
            CardockBrightnessMode.dark,
            reason: '$caseLabel 亮度保存',
          );
          _expectNoLayoutException(tester, '$caseLabel 切换亮度');

          await _revealPageTarget(
            tester,
            pageKey: const ValueKey<String>('appearance-settings-page'),
            target: find.byKey(
              const ValueKey<String>('appearance-theme-custom'),
            ),
            label: '$caseLabel 主题选项',
          );
          await tester.tap(
            find.byKey(const ValueKey<String>('appearance-theme-custom')),
          );
          await tester.pumpAndSettle();
          await _revealPageTarget(
            tester,
            pageKey: const ValueKey<String>('appearance-settings-page'),
            target: find.byKey(
              const ValueKey<String>('appearance-apply-theme'),
            ),
            label: '$caseLabel 应用主题',
          );
          await tester.tap(
            find.byKey(const ValueKey<String>('appearance-apply-theme')),
          );
          await tester.pumpAndSettle();
          expect(
            appearanceStore.value?.family,
            CardockThemeFamily.custom,
            reason: '$caseLabel 主题保存',
          );
          _expectNoLayoutException(tester, '$caseLabel 切换主题');

          await _revealPageTarget(
            tester,
            pageKey: const ValueKey<String>('appearance-settings-page'),
            target: find.byKey(
              const ValueKey<String>('appearance-desktop-icon-obsidianGold'),
            ),
            label: '$caseLabel 桌面图标选项',
          );
          await tester.tap(
            find.byKey(
              const ValueKey<String>('appearance-desktop-icon-obsidianGold'),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            appearanceStore.value?.desktopIconFamily,
            CardockLauncherFamily.obsidianGold,
            reason: '$caseLabel 桌面图标保存',
          );
          expect(
            find.byKey(
              const ValueKey<String>('appearance-desktop-icon-custom'),
            ),
            findsNothing,
            reason: '$caseLabel 桌面区不得派生 Custom 启动器资源',
          );
          _expectNoLayoutException(tester, '$caseLabel 切换桌面图标');
        });
      }
    }
  }

  test('Cardock正文、辅助文字和导航字号保持清晰层级', () {
    expect(CardockTypography.body, 12.5);
    expect(CardockTypography.caption, 9.5);
    expect(CardockTypography.navigation, greaterThanOrEqualTo(10));
    expect(CardockTypography.cardTitle, greaterThan(CardockTypography.body));
  });

  testWidgets('320x640大字体下建库页和解锁错误排版可滚动且无溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(
      AccountSubscriptionApp(vaultStore: FakeVaultStore()),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('vault-setup-page')),
      findsOneWidget,
    );
    _expectNoLayoutException(tester, '建库页首屏');
    await _exerciseVerticalPage(
      tester,
      pageKey: const ValueKey<String>('vault-setup-page'),
      label: '建库页大字体滚动',
    );

    await tester.pumpWidget(
      AccountSubscriptionApp(
        key: const ValueKey<String>('unlock-layout-test-app'),
        vaultStore: FakeVaultStore(
          configured: true,
          acceptedPassword: _testMasterPassword,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('unlock-master-password-field')),
      'WRONG-TEST-PASSWORD',
    );
    final unlockButton = find.byKey(
      const ValueKey<String>('unlock-vault-button'),
    );
    await tester.ensureVisible(unlockButton);
    await tester.tap(unlockButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('vault-state-error')),
      findsOneWidget,
    );
    _expectNoLayoutException(tester, '解锁错误大字体排版');
  });

  testWidgets('320x640大字体下账号与独立订阅编辑页可滚动且无溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const AccountEditorPage()),
    );
    await tester.pumpAndSettle();
    _expectNoLayoutException(tester, '账号编辑页首屏');
    await _exerciseVerticalPage(
      tester,
      pageKey: const ValueKey<String>('account-editor-page'),
      label: '账号编辑页大字体滚动',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const SubscriptionEditorPage(accounts: <AccountRecord>[]),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoLayoutException(tester, '独立订阅编辑页首屏');
    await _exerciseVerticalPage(
      tester,
      pageKey: const ValueKey<String>('subscription-editor-page'),
      label: '独立订阅编辑页大字体滚动',
    );
  });
}

Future<void> _exerciseVerticalPage(
  WidgetTester tester, {
  required ValueKey<String> pageKey,
  required String label,
}) async {
  final scrollable = _verticalScrollableWithin(pageKey);
  expect(scrollable, findsWidgets, reason: label);
  final scrollDistance = tester.view.physicalSize.height * 0.55;
  for (var step = 0; step < 5; step += 1) {
    await tester.drag(scrollable.first, Offset(0, -scrollDistance));
    await tester.pumpAndSettle();
    _expectNoLayoutException(tester, '$label 第${step + 1}段');
  }
}

Future<void> _revealPageTarget(
  WidgetTester tester, {
  required ValueKey<String> pageKey,
  required Finder target,
  required String label,
}) async {
  final scrollable = _verticalScrollableWithin(pageKey);
  expect(scrollable, findsWidgets, reason: label);
  final scrollDistance = tester.view.physicalSize.height * 0.45;
  for (
    var attempt = 0;
    attempt < 24 && target.evaluate().isEmpty;
    attempt += 1
  ) {
    await tester.drag(scrollable.first, Offset(0, -scrollDistance));
    await tester.pumpAndSettle();
    _expectNoLayoutException(tester, '$label 定位${attempt + 1}');
  }
  expect(target, findsOneWidget, reason: label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  _expectNoLayoutException(tester, '$label 可见');
}

Finder _verticalScrollableWithin(ValueKey<String> pageKey) => find.descendant(
  of: find.byKey(pageKey),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable &&
        (widget.axisDirection == AxisDirection.down ||
            widget.axisDirection == AxisDirection.up),
  ),
);

void _expectNoLayoutException(WidgetTester tester, String label) {
  final overflowingFlexes = <String>[];
  for (final element
      in find.byWidgetPredicate((widget) => widget is Flex).evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderFlex ||
        renderObject.direction != Axis.horizontal) {
      continue;
    }
    var furthestRight = 0.0;
    RenderBox? child = renderObject.firstChild;
    while (child != null) {
      final parentData = child.parentData! as FlexParentData;
      furthestRight = math.max(
        furthestRight,
        parentData.offset.dx + child.size.width,
      );
      child = renderObject.childAfter(child);
    }
    if (furthestRight > renderObject.size.width + 0.1) {
      overflowingFlexes.add(
        '${element.widget.runtimeType} '
        '${renderObject.size.width.toStringAsFixed(1)} -> '
        '${furthestRight.toStringAsFixed(1)} '
        'text=${_descendantText(element).join('|')} '
        '${element.debugGetCreatorChain(12)}',
      );
    }
  }
  final exception = tester.takeException();
  if (exception == null) return;
  final details = exception is FlutterError
      ? exception.toStringDeep()
      : exception.toString();
  fail('$label\n$details\n${overflowingFlexes.join('\n')}');
}

List<String> _descendantText(Element root) {
  final values = <String>[];
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Text && widget.data != null) values.add(widget.data!);
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return values;
}

AccountRecord _account() => AccountRecord.fromDraft(
  id: 'account-1',
  draft: AccountDraft(
    platformName: '设置',
    category: '非常长的自定义分类名称',
    username: '中文用户名',
    loginAccount: 'long-account-name@example.invalid',
    boundPhone: '13800000000',
    boundEmail: 'long-account-name@example.invalid',
    website: 'https://example.invalid/a/very/long/login/path',
    notes: '用于响应式布局验证的长备注内容。',
  ),
);

List<SubscriptionRecord> _subscriptions() => <SubscriptionRecord>[
  for (var index = 1; index <= 6; index += 1)
    SubscriptionRecord.fromDraft(
      id: 'subscription-$index',
      draft: SubscriptionDraft(
        accountId: 'account-1',
        details: SubscriptionDetailsDraft(
          serviceName: '名称很长的中文云服务订阅 Cardock $index',
          planName: '企业高级年度套餐与附加服务 $index',
          amount: '1888.88',
          currency: 'USD',
          firstSubscribedOn: DateTime(2026, 1, 1),
          nextRenewalOn: subscriptionDateOnly(
            DateTime.now(),
          ).add(Duration(days: 5 + index * 8)),
          paymentMethod: '本机记录的银行卡尾号提示',
        ),
      ),
    ),
];
