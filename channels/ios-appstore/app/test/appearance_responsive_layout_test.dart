import 'dart:math' as math;

import 'package:account_subscription_manager/app/account_subscription_app.dart';
import 'package:account_subscription_manager/core/entitlements/entitlement_model.dart';
import 'package:account_subscription_manager/core/entitlements/mock_store_gateway.dart';
import 'package:account_subscription_manager/core/preferences/appearance_preferences.dart';
import 'package:account_subscription_manager/core/preferences/language_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vault_store.dart';

const _masterPassword = 'TEST-ONLY-MASTER-1234';

void main() {
  for (final viewport in const <Size>[Size(393, 873), Size(411, 915)]) {
    testWidgets('英文外观页 ${viewport.width.toInt()}px 150% 无布局溢出', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );

      final languageController = CardockLanguageController(
        store: MemoryLanguagePreferencesStore(
          const LanguagePreferences(language: CardockLanguage.english),
        ),
      );
      await languageController.load();
      addTearDown(languageController.dispose);

      await tester.pumpWidget(
        AccountSubscriptionApp(
          vaultStore: FakeVaultStore(
            configured: true,
            acceptedPassword: _masterPassword,
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
      await tester.enterText(
        find.byKey(const ValueKey<String>('unlock-master-password-field')),
        _masterPassword,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('unlock-vault-button')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey<String>('nav-settings')));
      await tester.pumpAndSettle();
      final settingsPage = find.byKey(const ValueKey<String>('settings-page'));
      final appearanceEntry = find.byKey(
        const ValueKey<String>('appearance-settings-entry'),
      );
      await tester.scrollUntilVisible(
        appearanceEntry,
        280,
        scrollable: find
            .descendant(of: settingsPage, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(appearanceEntry);
      await tester.pumpAndSettle();

      final exception = tester.takeException();
      final overflowDetails = _overflowingFlexes().join('\n');
      expect(
        exception,
        isNull,
        reason: '${viewport.width.toInt()}px / 150%\n$overflowDetails',
      );
      expect(
        overflowDetails,
        isEmpty,
        reason: '${viewport.width.toInt()}px / 150%',
      );
    });
  }
}

List<String> _overflowingFlexes() {
  final results = <String>[];
  for (final element
      in find.byWidgetPredicate((widget) => widget is Flex).evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderFlex) continue;
    var furthestExtent = 0.0;
    RenderBox? child = renderObject.firstChild;
    while (child != null) {
      final parentData = child.parentData! as FlexParentData;
      final extent = renderObject.direction == Axis.horizontal
          ? parentData.offset.dx + child.size.width
          : parentData.offset.dy + child.size.height;
      furthestExtent = math.max(furthestExtent, extent);
      child = renderObject.childAfter(child);
    }
    final availableExtent = renderObject.direction == Axis.horizontal
        ? renderObject.size.width
        : renderObject.size.height;
    if (furthestExtent <= availableExtent + 0.1) continue;
    results.add(
      '${element.widget.runtimeType} ${renderObject.direction.name} '
      '${availableExtent.toStringAsFixed(1)} -> '
      '${furthestExtent.toStringAsFixed(1)} '
      '${element.debugGetCreatorChain(12)}',
    );
  }
  return results;
}
