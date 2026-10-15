import 'dart:math' as math;

import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:account_subscription_manager/core/preferences/appearance_preferences.dart';
import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:account_subscription_manager/core/security/vault_contract.dart';
import 'package:account_subscription_manager/features/accounts/domain/account_record.dart';
import 'package:account_subscription_manager/features/subscriptions/domain/subscription_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _masterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  const cases = <({CardockLanguage language, double scale, Size viewport})>[
    (language: CardockLanguage.english, scale: 1, viewport: Size(320, 640)),
    (language: CardockLanguage.english, scale: 1.3, viewport: Size(320, 640)),
    (language: CardockLanguage.english, scale: 1.5, viewport: Size(320, 640)),
    (language: CardockLanguage.english, scale: 2, viewport: Size(320, 640)),
    (language: CardockLanguage.english, scale: 2, viewport: Size(360, 800)),
    (
      language: CardockLanguage.simplifiedChinese,
      scale: 2,
      viewport: Size(320, 640),
    ),
    (language: CardockLanguage.japanese, scale: 2, viewport: Size(320, 640)),
  ];

  for (final testCase in cases) {
    testWidgets('首页 ${testCase.viewport.width.toInt()}px '
        '${testCase.language.storageCode} ${testCase.scale}x 无 Flex 溢出', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = testCase.viewport;
      tester.binding.platformDispatcher.textScaleFactorTestValue =
          testCase.scale;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );

      final account = _account();
      final languageController = CardockLanguageController(
        store: MemoryLanguagePreferencesStore(
          LanguagePreferences(language: testCase.language),
        ),
      );
      await languageController.load();
      addTearDown(languageController.dispose);

      await tester.pumpWidget(
        AccountSubscriptionApp(
          vaultStore: FakeVaultStore(
            configured: true,
            acceptedPassword: _masterPassword,
            snapshot: VaultSnapshot(
              nextAccountId: 2,
              accounts: <AccountRecord>[account],
              nextSubscriptionId: 7,
              subscriptions: _subscriptions(),
              recentAccountIds: <String>[account.id],
            ),
          ),
          appearanceStore: MemoryAppearancePreferencesStore(),
          languageController: languageController,
          purchaseGateway: MockStoreGateway(
            initialEntitlement: ProductEntitlement.purchased,
            simulationEnabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.takeException();

      await tester.enterText(
        find.byKey(const ValueKey<String>('unlock-master-password-field')),
        _masterPassword,
      );
      final unlockButton = find.byKey(
        const ValueKey<String>('unlock-vault-button'),
      );
      await tester.ensureVisible(unlockButton);
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('home-page')), findsOneWidget);
      _expectNoFlexOverflow(tester);

      final tickets = find.byKey(
        const ValueKey<String>('home-renewal-tickets'),
      );
      final pageScroll = find.descendant(
        of: find.byKey(const ValueKey<String>('home-page')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              (widget.axisDirection == AxisDirection.down ||
                  widget.axisDirection == AxisDirection.up),
        ),
      );
      for (
        var attempt = 0;
        attempt < 8 && tickets.evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(pageScroll.first, const Offset(0, -240));
        await tester.pumpAndSettle();
        _expectNoFlexOverflow(tester);
      }
      expect(tickets, findsOneWidget);
      await tester.ensureVisible(tickets);
      await tester.pumpAndSettle();
      _expectNoFlexOverflow(tester);
    });
  }
}

void _expectNoFlexOverflow(WidgetTester tester) {
  final overflows = <String>[];
  for (final element
      in find.byWidgetPredicate((widget) => widget is Flex).evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderFlex || !renderObject.hasSize) continue;
    var furthest = 0.0;
    final childMetrics = <String>[];
    RenderBox? child = renderObject.firstChild;
    while (child != null) {
      final parentData = child.parentData! as FlexParentData;
      childMetrics.add(
        '${child.runtimeType}@${parentData.offset}=${child.size}',
      );
      furthest = math.max(
        furthest,
        renderObject.direction == Axis.horizontal
            ? parentData.offset.dx + child.size.width
            : parentData.offset.dy + child.size.height,
      );
      child = renderObject.childAfter(child);
    }
    final available = renderObject.direction == Axis.horizontal
        ? renderObject.size.width
        : renderObject.size.height;
    if (furthest <= available + 0.1) continue;
    overflows.add(
      '${renderObject.direction.name} '
      '${available.toStringAsFixed(1)} -> ${furthest.toStringAsFixed(1)} '
      'text=${_descendantText(element).join('|')} '
      'children=${childMetrics.join(',')} '
      '${element.debugGetCreatorChain(12)}',
    );
  }
  final exception = tester.takeException();
  expect(<Object?>[?exception, ...overflows], isEmpty);
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
    boundEmail: 'long-account-name@example.invalid',
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
